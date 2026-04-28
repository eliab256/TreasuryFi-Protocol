//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "./TokenConstants.sol";

abstract contract RiskManager {
    error RiskManager__InvalidYield(uint256 slot, uint256 yield);
    error RiskManager__ExcessiveYieldShock(uint256 slot, uint256 shock);

    uint256 internal constant MAX_YIELD_SHOCK_BPS = 5 * C.PERCENTAGE_PRECISION; // 5% shock
    uint256 internal constant MAX_YIELD = 20 * C.PERCENTAGE_PRECISION; // 20% max yield for sanity checks
    /// @dev Mapping to track possible shocks from oracle data for each slot
    mapping(uint256 => uint256) internal s_lastValidYield;

    function _updateLastValidYield(uint256 _slot, uint256 _yield) internal {
        if (!_isValidYield(_slot, _newYield)) {
            Revert RiskManager__InvalidYield(_slot, _yield);
        }
        if(s_lastValidYield[_slot] != 0) {
            uint256 shock = _yield > s_lastValidYield[_slot] ? _yield - s_lastValidYield[_slot] : s_lastValidYield[_slot] - _yield;
            if (shock > MAX_YIELD_SHOCK_BPS) {
                Revert RiskManager__ExcessiveYieldShock(_slot, shock);
            }
        }
        s_lastValidYield[_slot] = _yield;
    }

    function _isValidYield(uint256 _slot, uint256 _newYield) internal view returns (bool) {
        if (_newYield != 0 && _newYield < MAX_YIELD) {
            return true;
        } 
    }

}