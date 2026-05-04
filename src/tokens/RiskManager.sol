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
    mapping(uint256 => uint64) internal s_lastValidYieldPerSlot;

    /// @dev to freeze specific slots in case of detected shock or oracle malfunction without needing to pause the entire contract, updated by governance or an automated mechanism in case of shock detection
    mapping(uint256 => bool) internal s_slotFrozen; 

    /// @dev liabilities for each slot, updated on mint, burn and yield claim
    mapping(uint256 => uint256) private s_totalValuePerSlot;

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
////////////////// manual triggers for automation ////////////////// 
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

    function _freezeSlot(uint256 _slot) internal {
        if (s_slotFrozen[_slot]) revert RiskManager__SlotAlreadyFrozen(_slot);
        s_slotFrozen[_slot] = true;
        emit SlotFrozen(_slot);
    }

    function _unfreezeSlot(uint256 _slot) internal {
        if (!s_slotFrozen[_slot]) revert RiskManager__SlotNotFrozen(_slot);
        s_slotFrozen[_slot] = false;
        emit SlotUnfrozen(_slot);
    }


/////////////////////////////////////////////////////////////////////
///////////////////////// Yields validation /////////////////////////
/////////////////////////////////////////////////////////////////////

    // Lo yield non cambia a ogni tx ma a ogni aggiornamento dell' oracolo
    function _validSingleYield(uint256 _slot, uint64 _yield) private view returns (bool) {

    }

    function _validateSingleReserve(uint256 _slot) private view returns (bool) {

    }


    function _updateLastValidYield(uint256 _slot, uint256 _yield) private returns (bool freezeSlot) {
        if (_yield == 0 || _yield > MAX_YIELD) {
            freezeSlot = true;
            emit InvalidYield(_slot, _yield);
            return freezeSlot;
        }
        uint256 lastValidYield = s_lastValidYieldPerSlot[_slot];
        if(lastValidYield != 0) {
            uint256 shock = _yield > lastValidYield ? _yield - lastValidYield : 
            lastValidYield - _yield;
            if (shock > MAX_YIELD_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveYieldShock(_slot, shock);
                return freezeSlot;
            }
        }
        s_lastValidYieldPerSlot[_slot] = _yield;
        return false;
    }

////////////////////////////////////////////////////////////////////
/////////////////////// Oracles Data Getter //////////////////////// 
////////////////////////////////////////////////////////////////////  
    function _updateLastValidYields() private returns (BondYieldsResponse memory) {
        // 1. Declare cache struct
        BondYieldsResponse memory yieldResponseCached = s_lastValidYields;

        // 2. Check if oracle data is newer than the last valid data we have
        uint256 lastUpdateTimestamp = i_yieldsOracle.getLastUpdatedTimestamp();

        // 3. No update needed — return cache directly without touching storage
        if (yieldResponseCached.timestamp >= lastUpdateTimestamp) {
            return yieldResponseCached;
        }

        // 4. Retrieve new data and validate each slot
        BondYieldsResponse memory newYieldsResponse = i_yieldsOracle.getAllYields();
        bool freezeSlot1 = _updateLastValidYield(C.SLOT_2Y,  newYieldsResponse.twoYearYield);
        bool freezeSlot2 = _updateLastValidYield(C.SLOT_5Y,  newYieldsResponse.fiveYearYield);
        bool freezeSlot3 = _updateLastValidYield(C.SLOT_10Y, newYieldsResponse.tenYearYield);
        bool freezeSlot4 = _updateLastValidYield(C.SLOT_30Y, newYieldsResponse.thirtyYearYield);

        // 5. No freeze — all slots valid, update storage and return new data directly
        if (!freezeSlot1 && !freezeSlot2 && !freezeSlot3 && !freezeSlot4) {
            s_lastValidYields = newYieldsResponse;
            return newYieldsResponse;
        }

        // 6. At least one slot frozen, freeze flagged slots
        if (freezeSlot1) _freezeSlot(C.SLOT_2Y);
        if (freezeSlot2) _freezeSlot(C.SLOT_5Y);
        if (freezeSlot3) _freezeSlot(C.SLOT_10Y);
        if (freezeSlot4) _freezeSlot(C.SLOT_30Y);

        // 7. Build mixed response, keep old values for frozen slots, new values for healthy ones
        BondYieldsResponse memory mixedYieldsResponse = BondYieldsResponse({
            twoYearYield:    freezeSlot1 ? yieldResponseCached.twoYearYield    : newYieldsResponse.twoYearYield,
            fiveYearYield:   freezeSlot2 ? yieldResponseCached.fiveYearYield   : newYieldsResponse.fiveYearYield,
            tenYearYield:    freezeSlot3 ? yieldResponseCached.tenYearYield    : newYieldsResponse.tenYearYield,
            thirtyYearYield: freezeSlot4 ? yieldResponseCached.thirtyYearYield : newYieldsResponse.thirtyYearYield,
            timestamp:       yieldResponseCached.timestamp
        });

        // 8. Update storage with mixed response and return mixed response
        s_lastValidYields = mixedYieldsResponse;
        return mixedYieldsResponse;
    }

    function _updateLastValidReserves () private {
        uint256 lastUpdateTimestamp= i_reservesOracle.getLastUpdatedTimestamp();
    }


////////////////////////////////////////////////////////////////////
///////////////////////// Lifecycle Hooks ////////////////////////// 
////////////////////////////////////////////////////////////////////  

    function _beforeMinting(uint256 _slot, uint256 _value) internal {
        // 1.  Retrieve latest bond yields and reserves data from oracles (freshness checks are done in the oracles)
        BondYieldsResponse memory yieldsResponse = _updateLastValidYields();
        ReservesResponse memory reservesResponse = _updateLastValidReserves();
        // 2. Check if the slot is frozen, if yes revert
        if (s_slotFrozen[_slot]) {
            revert RiskManager__SlotFrozen(_slot);
        }
        
        // 3. Check if the new total liabilities for the slot after minting would exceed the reserves, if yes revert
        
    }

    function _beforeRedeeming(uint256 _slot, uint256 _value) internal {
        // 1.  Retrieve latest bond yields and reserves data from oracles (freshness checks are done in the oracles)
        BondYieldsResponse memory yieldsResponse = _updateLastValidYields();
        ReservesResponse memory reservesResponse = _updateLastValidReserves();

        // 2. Check if the slot is frozen, if yes revert
        if (s_slotFrozen[_slot]) {
            revert RiskManager__SlotFrozen(_slot);
        }
    }

    function _beforeClaimingYield(uint256 _slot, uint256 _value) internal {
        // 1.  Retrieve latest bond yields and reserves data from oracles (freshness checks are done in the oracles)
        BondYieldsResponse memory yieldsResponse = _updateLastValidYields();
        ReservesResponse memory reservesResponse = _updateLastValidReserves();

        // 2. Check if the slot is frozen, if yes revert
        if (s_slotFrozen[_slot]) {
            revert RiskManager__SlotFrozen(_slot);
        }

        // 3. Check if the new total liabilities for the slot after minting would exceed the reserves, if yes revert
    }


}