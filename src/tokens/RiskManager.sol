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
    error RiskManager__SlotAlreadyFrozen(uint256 slot);
    error RiskManager__SlotNotFrozen(uint256 slot);
    error RiskManager__SlotFrozen(uint256 slot);
    error RiskManager__SlotAlreadyInState(uint256 slot, bool frozen);

    event SlotFrozen(uint256 indexed slot);
    event SlotUnfrozen(uint256 indexed slot);
    event InvalidYield(uint256 indexed slot, uint256 yield);
    event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);

    uint256 internal constant MAX_YIELD_SHOCK_BPS = 5 * C.PERCENTAGE_PRECISION; // 5% shock
    uint256 internal constant MAX_YIELD = 20 * C.PERCENTAGE_PRECISION; // 20% max yield for sanity checks
    uint256 internal constant MAX_RESERVES_SHOCK_BPS = 30 * C.PERCENTAGE_PRECISION; // 30% shock
    IBondAutomation internal immutable i_yieldsAutomation;
    IReservesAutomation internal immutable i_reservesAutomation;

    IReservesOracle internal immutable i_reservesOracle;
    IBondOracle internal immutable i_yieldsOracle;

    uint256 internal immutable i_gracePeriod;
    uint256 internal immutable i_interval;
    uint256 internal s_lastUpkeepTriggerReserves;
    uint256 internal s_lastUpkeepTriggerYields;
    
    /// @dev Mapping to track possible shocks from oracle data for each slot
    mapping(uint256 => uint256) internal s_lastValidYieldPerSlot;

    /// @dev Mapping to track possible shocks from oracle data for each slot
    mapping(uint256 => uint256) internal s_lastValidReservePerSlot;

    /// @dev Mapping to track possible shocks from oracle data for each slot
    mapping(uint256 => uint256) internal s_lastValidCashBufferPerSlot;

    /// @dev to freeze specific slots in case of detected shock or oracle malfunction without needing to pause the entire contract, updated by governance or an automated mechanism in case of shock detection
    mapping(uint256 => bool) internal s_slotFrozen; 

    /// @dev liabilities for each slot, updated on mint, burn and yield claim
    mapping(uint256 => uint256) private s_totalLiabilitiesPerSlot;

    // @audit-issue forse queste struct si possono eliminar e passare ad avere i mapping
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

    function _setSlotFrozen(uint256 _slot, bool _frozen) private {
        if (s_slotFrozen[_slot] == _frozen) return;
        s_slotFrozen[_slot] = _frozen;
        if (_frozen) emit SlotFrozen(_slot);
        else emit SlotUnfrozen(_slot);
    }

    /**
     * @notice Sets the frozen state of a slot, implement access control on the main contract
     * @param _slot The slot to update
     * @param _frozen The new frozen state
     */
    function _setSlotFrozenOnMainContract(uint256 _slot, bool _frozen) internal {
    if (s_slotFrozen[_slot] == _frozen) revert RiskManager__SlotAlreadyInState(_slot, _frozen);
    _setSlotFrozen(_slot, _frozen);
    }

    function _getTotalLiabilitiesForSlot(uint256 _slot) internal view returns (uint256) {
        return s_totalLiabilitiesPerSlot[_slot];
    }

////////////////////////////////////////////////////////////////////
////////////////// update yields and reserves ////////////////////// 
////////////////////////////////////////////////////////////////////  

    // add role
    function _updateYieldsValues() internal {
        (BondYieldsResponse memory yieldsResponse, bool freezeNeededYields, bool freezeSlot1, bool freezeSlot2, bool freezeSlot3, bool freezeSlot4) = _updateLastValidYields();
        if(freezeNeededYields){
            _setSlotFrozen(C.SLOT_2Y, freezeSlot1);
            _setSlotFrozen(C.SLOT_5Y, freezeSlot2);
            _setSlotFrozen(C.SLOT_10Y, freezeSlot3);
            _setSlotFrozen(C.SLOT_30Y, freezeSlot4);
        }
    }

    function _updateReservesValues() internal {
        (ReservesResponse memory reservesResponse, bool freezeNeededReserves, bool freezeSlot1Reserves, bool freezeSlot2Reserves, bool freezeSlot3Reserves, bool freezeSlot4Reserves) = _updateLastValidReserves();
        if(freezeNeededReserves){
            _setSlotFrozen(C.SLOT_2Y, freezeSlot1Reserves);
            _setSlotFrozen(C.SLOT_5Y, freezeSlot2Reserves);
            _setSlotFrozen(C.SLOT_10Y, freezeSlot3Reserves);
            _setSlotFrozen(C.SLOT_30Y, freezeSlot4Reserves);
        }
    }


/////////////////////////////////////////////////////////////////////
///////////////////////// Yields validation /////////////////////////
/////////////////////////////////////////////////////////////////////

    function _validateAndUpdateLastValidReserve(uint256 _slot, uint256 _reserve) private  returns (bool freezeSlot) {
        if(_reserve == 0) {
            freezeSlot = true;
            emit InvalidYield(_slot, _reserve);
            return freezeSlot;
        }
        uint256 lastValidReserve = s_lastValidReservePerSlot[_slot];
        if(lastValidReserve != 0) {
            uint256 shock = _reserve > lastValidReserve ? _reserve - lastValidReserve : 
            lastValidReserve - _reserve;
            if (shock > MAX_RESERVES_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveYieldShock(_slot, shock);
                return freezeSlot;
            }
        }
        s_lastValidReservePerSlot[_slot] = _reserve;
        freezeSlot = false;
    }


    function _validateAndUpdateLastValidYield(uint256 _slot, uint256 _yield) private returns (bool freezeSlot) {
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
        freezeSlot = false;
    }

    function _validateAndUpdateLastValidCashBuffer(uint256 _slot, uint256 _cashBuffer) private returns (bool freezeSlot){
        if (_cashBuffer == 0) {
            freezeSlot = true;
            emit InvalidYield(_slot, _cashBuffer);
            return freezeSlot;
        }
        uint256 lastValidCashBuffer = s_lastValidCashBufferPerSlot[_slot];
        if(lastValidCashBuffer != 0) {
            uint256 shock = _cashBuffer > lastValidCashBuffer ? _cashBuffer - lastValidCashBuffer : 
            lastValidCashBuffer - _cashBuffer;
            if (shock > MAX_RESERVES_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveYieldShock(_slot, shock);
                return freezeSlot;
            }
        }
        s_lastValidCashBufferPerSlot[_slot] = _cashBuffer;
        freezeSlot = false;
    }

////////////////////////////////////////////////////////////////////
/////////////////////// Oracles Data Getter //////////////////////// 
////////////////////////////////////////////////////////////////////  

    /**
     * @notice Retrieves the most recent valid bond yields, applying per-slot anomaly detection.
     * @dev Compares the oracle's latest timestamp against the cached `s_lastValidYields` timestamp.
     *      If the oracle has no newer data, the cached struct is returned immediately (no storage write).
     *      Otherwise, each slot (2Y, 5Y, 10Y, 30Y) is independently validated via `_updateLastValidYield`:
     *      - If all slots are healthy, `s_lastValidYields` is updated to the fresh oracle data.
     *      - If one or more slots trigger an anomaly, the affected slots are frozen via `_freezeSlot`
     *        and a mixed response is built: frozen slots retain their last valid value while healthy
     *        slots receive the new oracle value. The mixed struct is then persisted to storage.
     * @return A `BondYieldsResponse` struct containing the best available yields for each maturity.
     *         Frozen slots will hold their last known good value until manually unfrozen.
     */
    function _updateLastValidYields() private returns (BondYieldsResponse memory, bool freezeNeeded, bool freezeSlot1, bool freezeSlot2, bool freezeSlot3, bool freezeSlot4) {
        // 1. Declare cache struct
        BondYieldsResponse memory yieldResponseCached = s_lastValidYields;

        // 2. Check if oracle data is newer than the last valid data we have
        uint256 lastUpdateTimestamp = i_yieldsOracle.getLastUpdatedTimestamp();

        // 3. No update needed — return cache directly without touching storage
        if (yieldResponseCached.timestamp >= lastUpdateTimestamp) {
           // return cached response with freezeNeeded false, all other flags will not be used
            return (yieldResponseCached,false, false, false, false, false);
        }

        // 4. Retrieve new data and validate each slot
        BondYieldsResponse memory newYieldsResponse = i_yieldsOracle.getAllYields();
         freezeSlot1 = _validateAndUpdateLastValidYield(C.SLOT_2Y,  newYieldsResponse.twoYearYield);
         freezeSlot2 = _validateAndUpdateLastValidYield(C.SLOT_5Y,  newYieldsResponse.fiveYearYield);
         freezeSlot3 = _validateAndUpdateLastValidYield(C.SLOT_10Y, newYieldsResponse.tenYearYield);
         freezeSlot4 = _validateAndUpdateLastValidYield(C.SLOT_30Y, newYieldsResponse.thirtyYearYield);

        // 5. No freeze all slots valid, update storage and return new data directly 
        if (!freezeSlot1 && !freezeSlot2 && !freezeSlot3 && !freezeSlot4) {
            s_lastValidYields = newYieldsResponse;
            return (newYieldsResponse, true,  freezeSlot1, freezeSlot2, freezeSlot3, freezeSlot4);
        }

        // 6. Build mixed response, keep old values for frozen slots, new values for healthy ones
        BondYieldsResponse memory mixedYieldsResponse = BondYieldsResponse({
            twoYearYield:    freezeSlot1 ? yieldResponseCached.twoYearYield    : newYieldsResponse.twoYearYield,
            fiveYearYield:   freezeSlot2 ? yieldResponseCached.fiveYearYield   : newYieldsResponse.fiveYearYield,
            tenYearYield:    freezeSlot3 ? yieldResponseCached.tenYearYield    : newYieldsResponse.tenYearYield,
            thirtyYearYield: freezeSlot4 ? yieldResponseCached.thirtyYearYield : newYieldsResponse.thirtyYearYield,
            timestamp:       yieldResponseCached.timestamp
        });

        // 7. Update storage with mixed response and return mixed response
        s_lastValidYields = mixedYieldsResponse;
        return (mixedYieldsResponse, true,  freezeSlot1, freezeSlot2, freezeSlot3, freezeSlot4);
    }

    function _updateLastValidReserves () private returns (ReservesResponse memory, bool freezeNeeded, bool freezeSlot1, bool freezeSlot2, bool freezeSlot3, bool freezeSlot4) {
        
        // 1. Declare cache struct
        ReservesResponse memory reservesResponseCached = s_lastValidReserves;

        // 2. Check if oracle data is newer than the last valid data we have
        uint256 lastUpdateTimestamp= i_reservesOracle.getLastUpdatedTimestamp();

        // 3. No update needed — return cache directly without touching storage
        if (reservesResponseCached.timestamp >= lastUpdateTimestamp) {
            // return cached response with freezeNeeded false, all other flags will not be used
            return (reservesResponseCached,false, false, false, false, false);
        }

        // 4. Retrieve new data 
        ReservesResponse memory newReservesResponse = i_reservesOracle.getAllReserves();

        // 5. Validate each reserve slot, if shock freeze slot is true
        freezeSlot1 = _validateAndUpdateLastValidReserve(C.SLOT_2Y,  newReservesResponse.twoYearUsdBondsValue);
        freezeSlot2 = _validateAndUpdateLastValidReserve(C.SLOT_5Y,  newReservesResponse.fiveYearUsdBondsValue);
        freezeSlot3 = _validateAndUpdateLastValidReserve(C.SLOT_10Y, newReservesResponse.tenYearUsdBondsValue);
        freezeSlot4 = _validateAndUpdateLastValidReserve(C.SLOT_30Y, newReservesResponse.thirtyYearUsdBondsValue);

        // 6. Validate cash buffer, if shock freeze slot is true
        if(!freezeSlot1){
            freezeSlot1 = _validateAndUpdateLastValidCashBuffer(C.SLOT_2Y,  newReservesResponse.twoYearUsdCashValue);
        }
        if(!freezeSlot2){
            freezeSlot2 = _validateAndUpdateLastValidCashBuffer(C.SLOT_5Y,  newReservesResponse.fiveYearUsdCashValue);
        }
        if(!freezeSlot3){
            freezeSlot3 = _validateAndUpdateLastValidCashBuffer(C.SLOT_10Y, newReservesResponse.tenYearUsdCashValue);
        }
        if(!freezeSlot4){
            freezeSlot4 = _validateAndUpdateLastValidCashBuffer(C.SLOT_30Y, newReservesResponse.thirtyYearUsdCashValue);
        }

        // 6. At least one slot frozen, freeze flagged slots
        if (!freezeSlot1 && !freezeSlot2 && !freezeSlot3 && !freezeSlot4) {
            s_lastValidReserves = newReservesResponse;
            return (newReservesResponse, true,  freezeSlot1, freezeSlot2, freezeSlot3, freezeSlot4);
        }         
 
        // 7. Build mixed response, keep old values for frozen slots, new values for healthy ones
        ReservesResponse memory mixedReservesResponse = ReservesResponse({
            twoYearUsdBondsValue:    freezeSlot1 ? reservesResponseCached.twoYearUsdBondsValue    : newReservesResponse.twoYearUsdBondsValue,
            fiveYearUsdBondsValue:   freezeSlot2 ? reservesResponseCached.fiveYearUsdBondsValue   : newReservesResponse.fiveYearUsdBondsValue,
            tenYearUsdBondsValue:    freezeSlot3 ? reservesResponseCached.tenYearUsdBondsValue    : newReservesResponse.tenYearUsdBondsValue,
            thirtyYearUsdBondsValue: freezeSlot4 ? reservesResponseCached.thirtyYearUsdBondsValue : newReservesResponse.thirtyYearUsdBondsValue,

            twoYearUsdCashValue:    freezeSlot1 ? reservesResponseCached.twoYearUsdCashValue    : newReservesResponse.twoYearUsdCashValue,
            fiveYearUsdCashValue:   freezeSlot2 ? reservesResponseCached.fiveYearUsdCashValue   : newReservesResponse.fiveYearUsdCashValue,
            tenYearUsdCashValue:    freezeSlot3 ? reservesResponseCached.tenYearUsdCashValue    : newReservesResponse.tenYearUsdCashValue,
            thirtyYearUsdCashValue: freezeSlot4 ? reservesResponseCached.thirtyYearUsdCashValue : newReservesResponse.thirtyYearUsdCashValue,

            cashBufferUsdTotalValue:  freezeSlot1 ? reservesResponseCached.cashBufferUsdTotalValue  : newReservesResponse.cashBufferUsdTotalValue,
            totalUsdBondsValue:       freezeSlot1 && freezeSlot2 && freezeSlot3 && freezeSlot4 ? reservesResponseCached.totalUsdBondsValue : newReservesResponse.totalUsdBondsValue,
            timestamp:          reservesResponseCached.timestamp
        });

        // 8. Update storage with mixed response and return mixed response
        s_lastValidReserves = mixedReservesResponse;
        return (mixedReservesResponse, true,  freezeSlot1, freezeSlot2, freezeSlot3, freezeSlot4);
        
    }


////////////////////////////////////////////////////////////////////
///////////////////////// Lifecycle Hooks ////////////////////////// 
////////////////////////////////////////////////////////////////////  

    function _beforeOpenNewPosition(uint256 _slot, uint256 _value) internal {
        // 1.  Retrieve latest bond yields and reserves data from oracles (freshness checks are done in the oracles)
        
        
    }

    function _beforeRedeeming(uint256 _slot, uint256 _value) internal {
        // 1.  Retrieve latest bond yields and reserves data from oracles (freshness checks are done in the oracles)
       
    }

    // claimibg yield trigger before mint, attenzione
    function _beforeClaimingYield(uint256 _slot, uint256 _value) internal {
        // 1.  Retrieve latest bond yields and reserves data from oracles (freshness checks are done in the oracles)
    }


}