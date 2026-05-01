//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "./TokenConstants.sol";
import {BondYieldsResponse, ReservesResponse} from "../types.sol";
import {IBondAutomation} from "../interfaces/IBondAutomation.sol";
import {IReservesAutomation} from "../interfaces/IReservesAutomation.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";


abstract contract RiskManager {
    error RiskManager__InvalidYield(uint256 slot, uint256 yield);
    error RiskManager__ExcessiveYieldShock(uint256 slot, uint256 shock);
    error RiskManager__ZeroAddress();
    error RiskManager__AutomationGracePeriodNotElapsed();

    uint256 internal constant MAX_YIELD_SHOCK_BPS = 5 * C.PERCENTAGE_PRECISION; // 5% shock
    uint256 internal constant MAX_YIELD = 20 * C.PERCENTAGE_PRECISION; // 20% max yield for sanity checks
    IBondAutomation internal immutable i_yieldsAutomation;
    IReservesAutomation internal immutable i_reservesAutomation;

    IReservesOracle internal immutable i_reservesOracle;
    IBondOracle internal immutable i_yieldsOracle;

    uint256 internal immutable i_gracePeriod;
    uint256 internal immutable i_interval;
    uint256 internal s_lastUpkeepTriggerReserves;
    uint256 internal s_lastUpkeepTriggerYields;
    
    /// @dev Mapping to track possible shocks from oracle data for each slot
    mapping(uint256 => uint256) internal s_lastValidYield;
    BondYieldsResponse internal s_lastValidYields;
    ReservesResponse internal s_lastValidReserves;

    constructor(address _yieldsAutomation, address _reservesAutomation, address _reservesOracle, address _yieldsOracle) {
        i_yieldsAutomation = IBondAutomation(_yieldsAutomation);
        i_reservesAutomation = IReservesAutomation(_reservesAutomation);
        i_reservesOracle = IReservesOracle(_reservesOracle);
        i_yieldsOracle = IBondOracle(_yieldsOracle);
        (i_interval , i_gracePeriod, ) = i_yieldsAutomation.getAllUpkeepInfo();
    }

    /**
     * @notice Internal function to trigger yields upkeep automation.
     * @dev Returns true if upkeep was executed, false if grace period has not elapsed.
     * @return bool indicating whether upkeep was triggered.
     */
    function _triggerYieldsUpkeep() private returns (bool) {
        if (!_checkManualTriggerNeeded(s_lastUpkeepTriggerYields)) {
            return false;
        }

        // checkUpkeep needed to avoid causing revert on performUpkeep
        (bool upkeepNeeded, ) = i_yieldsAutomation.checkUpkeep("");
        if (upkeepNeeded) {
            i_yieldsAutomation.performUpkeep("");
            s_lastUpkeepTriggerYields = block.timestamp;
        }
        return true;
    }
    
    /**
     * @notice Internal function to trigger reserves upkeep automation only if grace period has elapsed since last trigger.
     * @dev Returns true if upkeep was executed, false if grace period has not elapsed.
     * @return bool indicating whether upkeep was triggered.
     */
     // @audit-issue valutare se togliere il bool di return
    function _triggerReservesUpkeep() private returns (bool) {
        if (!_checkManualTriggerNeeded(s_lastUpkeepTriggerReserves)) {
            return false;
        }

        // checkUpkeep needed to avoid causing revert on performUpkeep
        (bool upkeepNeeded, ) = i_reservesAutomation.checkUpkeep("");
        if (upkeepNeeded) {
            i_reservesAutomation.performUpkeep("");
            s_lastUpkeepTriggerReserves = block.timestamp;
        }
        return true;
    }

    function _checkManualTriggerNeeded(uint256 lastTriggerTimestamp) private view returns (bool) {
        if (block.timestamp > lastTriggerTimestamp + i_interval + i_gracePeriod) {
            return true;
        } else {
            return false;
        }
    }

    //function che verifica l' affidabilità dei dati ricevuti da oracle yelds
    function _validateYields() internal returns (bool) {
        // 1. If automation doens't work for some reason and grace period has elapsed, trigger it manually. otherwise do nothing
        _triggerYieldsUpkeep();
        // 2. Check if data are not stale, if they are, return false (data not valid)
        if (i_yieldsOracle.isStale()) {
            return false;
        } 
    }

    //function che verifica l' affidabilità dei dati ricevuti da oracle reserves
    function _validateReserves() internal returns (bool) {
        // 1. If automation doens't work for some reason and grace period has elapsed, trigger it manually. otherwise do nothing
        _triggerReservesUpkeep();
        // 2. Check if data are not stale, if they are, return false (data not valid)
        if (i_reservesOracle.isStale()) {
            return false;
            }
    }



    function _updateLastValidYield(uint256 _slot, uint256 _yield) internal {
        if (_yield != 0 && _yield > MAX_YIELD) {
            revert RiskManager__InvalidYield(_slot, _yield);
        }
        if(s_lastValidYield[_slot] != 0) {
            uint256 shock = _yield > s_lastValidYield[_slot] ? _yield - s_lastValidYield[_slot] : 
            s_lastValidYield[_slot] - _yield;
            if (shock > MAX_YIELD_SHOCK_BPS) {
                revert RiskManager__ExcessiveYieldShock(_slot, shock);
            }
        }
        s_lastValidYield[_slot] = _yield;
    }

    function _bondYieldsNeedUpdate() internal view returns (bool) {
        if(s_lastValidYields.timestamp > block.timestamp ){ 
            return true;
        }
        else return false; 
    }


}