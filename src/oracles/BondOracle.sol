//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BondYieldsResponse} from "../types.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
contract BondOracle is IBondOracle, AccessControl {
    event YieldUpdated(
        uint64 twoYearYield,
        uint64 fiveYearYield,
        uint64 tenYearYield,
        uint64 thirtyYearYield,
        uint256 timestamp
    );

    error BondOracle__DataIsStale();
    error BondOracle__InvalidSlot();

    uint256 internal constant STALENESS_THRESHOLD = 48 hours;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    BondYieldsResponse internal s_bondYieldsResponse;
    address internal s_FunctionsConsumer;

    constructor(address _functionsConsumer) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, _functionsConsumer);
        s_FunctionsConsumer = _functionsConsumer;
    }

    function updateYield(
        BondYieldsResponse memory newYields
    ) external onlyRole(UPDATER_ROLE) {
        s_bondYieldsResponse = newYields;
        emit YieldUpdated(
            newYields.twoYearYield,
            newYields.fiveYearYield,
            newYields.tenYearYield,
            newYields.thirtyYearYield,
            newYields.timestamp
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
        return s_FunctionsConsumer;
    }
}
