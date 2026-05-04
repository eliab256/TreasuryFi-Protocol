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

    /**
         * @notice Constructor to initialize the RiskManager with references to automation and oracle contracts.
         * @dev All addresses checks are done on the main contract
         * @param _yieldsAutomation Address of the BondAutomation contract.
         * @param _reservesAutomation Address of the ReservesAutomation contract.
         * @param _reservesOracle Address of the ReservesOracle contract.
         * @param _yieldsOracle Address of the BondOracle contract.

     */
    constructor(address _yieldsAutomation, address _reservesAutomation, address _reservesOracle, address _yieldsOracle) {
        i_yieldsAutomation = IBondAutomation(_yieldsAutomation);
        i_reservesAutomation = IReservesAutomation(_reservesAutomation);
        i_reservesOracle = IReservesOracle(_reservesOracle);
        i_yieldsOracle = IBondOracle(_yieldsOracle);
        (i_interval , i_gracePeriod, ) = i_yieldsAutomation.getAllUpkeepInfo();
    }

////////////////////////////////////////////////////////////////////
////////////////////// Oracle data validation ////////////////////// 
////////////////////////////////////////////////////////////////////  

    /**
     * @notice Internal function to manually trigger the bond yields upkeep
     * @dev Reverts if the grace period since the last trigger has not elapsed or if the upkeep is not needed, to avoid unnecessary calls.
     * @dev This function should be use on the main contract on his public function dedicated
     */
    function _triggerYieldsUpkeep() internal {
        bool upkeepNeedTrigger = _checkManualTriggerNeeded(s_lastUpkeepTriggerYields);
        if(!upkeepNeedTrigger) {
            revert RiskManager__AutomationGracePeriodNotElapsed();
        }
        // checkUpkeep needed to avoid causing revert on performUpkeep
        (bool upkeepNeeded, ) = i_yieldsAutomation.checkUpkeep("");
        if (upkeepNeeded) {
            i_yieldsAutomation.performUpkeep("");
            s_lastUpkeepTriggerYields = block.timestamp;
        }
    }
    
    /**
     * @notice Internal function to manually trigger the reserves upkeep
     * @dev Reverts if the grace period since the last trigger has not elapsed or if the upkeep is not needed, to avoid unnecessary calls.
     * @dev This function should be use on the main contract on his public function dedicated
     */
    function _triggerReservesUpkeep() internal  {
        bool upkeepNeedTrigger = _checkManualTriggerNeeded(s_lastUpkeepTriggerReserves);
        if(!upkeepNeedTrigger) {
            revert RiskManager__AutomationGracePeriodNotElapsed();
        }
        // checkUpkeep needed to avoid causing revert on performUpkeep
        (bool upkeepNeeded, ) = i_reservesAutomation.checkUpkeep("");
        if (upkeepNeeded) {
            i_reservesAutomation.performUpkeep("");
            s_lastUpkeepTriggerReserves = block.timestamp;
        }
    }


    function _checkManualTriggerNeeded(uint256 lastTriggerTimestamp) private view returns (bool) {
        if (block.timestamp > lastTriggerTimestamp + i_interval + i_gracePeriod) {
            return true;
        } else {
            return false;
        }
    }

    function _validSingleYield(uint256 _slot) private view returns (bool) {
        
    }

    function _validateSingleReserve(uint256 _slot) private view returns (bool) {

    }


    function _updateLastValidYield(uint256 _slot, uint256 _yield) private {
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


    function _beforeMinting() internal {
        BondYieldsResponse memory yieldsResponse;
        ReservesResponse memory reservesResponse;
        if(s_lastValidYields.timestamp + i_interval < block.timestamp || 
           s_lastValidReserves.timestamp + i_interval < block.timestamp) {
            yieldsResponse = i_yieldsOracle.getAllYields();
            reservesResponse = i_reservesOracle.getAllReserves();
        } else {
            yieldsResponse = s_lastValidYields;
            reservesResponse = s_lastValidReserves;
        }

        
    }


}