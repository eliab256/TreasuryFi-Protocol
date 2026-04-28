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
        if (_functionsConsumer == address(0))
            revert BondOracle__ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, _functionsConsumer);
        s_functionsConsumer = _functionsConsumer;
    }

    function updateYields(
        uint64[] memory _values,
        uint256 _timestamp,
        bytes memory _err
    ) external onlyRole(UPDATER_ROLE) {
        if (_err.length > 0) {
            emit YieldUpdateFailed(_err);
            return;
        }

        // lunghezza già verificata nel Consumer, doppio check difensivo
        if (_values.length < 4)
            revert BondOracle__IncompleteResponse(_values.length);

        s_bondYieldsResponse = BondYieldsResponse({
            twoYearYield: _values[0],
            fiveYearYield: _values[1],
            tenYearYield: _values[2],
            thirtyYearYield: _values[3],
            timestamp: _timestamp
        });

        emit YieldUpdated(
            _values[0],
            _values[1],
            _values[2],
            _values[3],
            _timestamp
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
