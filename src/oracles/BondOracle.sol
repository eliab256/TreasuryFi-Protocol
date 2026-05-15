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
    bool private s_consumerSet;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setFunctionsConsumer(address _consumer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (s_consumerSet) revert BondOracle__ConsumerAlreadySet();
        if (_consumer == address(0)) revert BondOracle__ZeroAddress();
        _grantRole(UPDATER_ROLE, _consumer);
        s_functionsConsumer = _consumer;
        s_consumerSet = true;
        emit ConsumerSet(_consumer);
    }

    /// @dev Inherited from IBondOracle. See interface for details.
    function updateYields(
        uint256[] memory _values,
        uint256 _timestamp,
        bytes memory _err
    ) external onlyRole(UPDATER_ROLE) {
        if (_err.length > 0) {
            emit YieldUpdateFailed(_err);
            return;
        }

        // already checked in the consumer contract but we add this check here for extra security.
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

    /// @dev Inherited from IBondOracle. See interface for details.
    function getYield(uint256 _slot) external view returns (uint256) {
        BondYieldsResponse memory yields = s_bondYieldsResponse;
        if (_isStale(yields.timestamp)) revert BondOracle__DataIsStale();

        if (_slot == 1) return yields.twoYearYield;
        if (_slot == 2) return yields.fiveYearYield;
        if (_slot == 3) return yields.tenYearYield;
        if (_slot == 4) return yields.thirtyYearYield;

        revert BondOracle__InvalidSlot();
    }

    /**
     * @dev Checks if the yield data is stale.
     * @param _yieldTimestamp The timestamp of the yield data.
     * @return True if the data is stale, false otherwise.
     */
    function _isStale(uint256 _yieldTimestamp) internal view returns (bool) {
        if (_yieldTimestamp == 0) return true;
        return (block.timestamp - _yieldTimestamp) > STALENESS_THRESHOLD;
    }


    /// @dev Inherited from IBondOracle. See interface for details.
    function getAllYields() external view returns (BondYieldsResponse memory) {
        BondYieldsResponse memory yields = s_bondYieldsResponse;
        if (_isStale(yields.timestamp)) revert BondOracle__DataIsStale();
        return yields;
    }

    /// @dev Inherited from IBondOracle. See interface for details.
    function isStale() public view returns (bool) {
        return _isStale(s_bondYieldsResponse.timestamp);
    }

    /// @dev Inherited from IBondOracle. See interface for details.
    function getLastUpdatedTimestamp() public view returns (uint256) {
        return s_bondYieldsResponse.timestamp;
    }

    /// @dev Inherited from IBondOracle. See interface for details.
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
