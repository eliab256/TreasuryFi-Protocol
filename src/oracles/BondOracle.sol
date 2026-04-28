//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BondYieldsResponse} from "../types.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract BondOracle is IBondOracle, ERC165, AccessControl {
    uint256 internal constant STALENESS_THRESHOLD = 48 hours;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    BondYieldsResponse internal s_bondYieldsResponse;
    address internal s_functionsConsumer;

    constructor(address _functionsConsumer) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, _functionsConsumer);
        s_functionsConsumer = _functionsConsumer;
    }

    function updateYield(
        bytes memory response,
        bytes memory err
    ) external onlyRole(UPDATER_ROLE) {
        if (err.length > 0) {
            emit YieldUpdateFailed(err);
            return;
        }
        (uint64[] memory values, uint256 timestamp) = abi.decode(
            response,
            (uint64[], uint256)
        );
        s_bondYieldsResponse = BondYieldsResponse({
            twoYearYield: values[0],
            fiveYearYield: values[1],
            tenYearYield: values[2],
            thirtyYearYield: values[3],
            timestamp: timestamp
        });
        emit YieldUpdated(
            values[0],
            values[1],
            values[2],
            values[3],
            timestamp
        );
    }

    function getYield(uint256 _slot) external view returns (uint64) {
        BondYieldsResponse memory yields = s_bondYieldsResponse;
        if (_isStale(yields.timestamp)) revert BondOracle__DataIsStale();

        if (_slot == 1) return yields.twoYearYield;
        if (_slot == 2) return yields.fiveYearYield;
        if (_slot == 3) return yields.tenYearYield;
        if (_slot == 4) return yields.thirtyYearYield;

        revert BondOracle__InvalidSlot();
    }

    function isStale() public view returns (bool) {
        return _isStale(s_bondYieldsResponse.timestamp);
    }

    function _isStale(uint256 _yieldTimestamp) internal view returns (bool) {
        return (block.timestamp - _yieldTimestamp) > STALENESS_THRESHOLD;
    }

    function getLastUpdatedTimestamp() public view returns (uint256) {
        return s_bondYieldsResponse.timestamp;
    }

    function getFunctionsConsumer() public view returns (address) {
        return s_functionsConsumer;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC165) returns (bool) {
        return
            interfaceId == type(IBondOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
