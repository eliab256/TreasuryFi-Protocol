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
    error RiskManager__StaleOracleData();
    error RiskManager__InvalidReserve(uint256 slot, uint256 reserve);

    event SlotFrozen(uint256 indexed slot);
    event SlotUnfrozen(uint256 indexed slot);
    event InvalidYield(uint256 indexed slot, uint256 yield);
    event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);
    event InvalidReserve(uint256 indexed slot, uint256 reserve);
    event ExcessiveReserveShock(uint256 indexed slot, uint256 shock);
    event InvalidCashBuffer(uint256 indexed slot, uint256 cashBuffer);
    event ExcessiveCashBufferShock(uint256 indexed slot, uint256 shock);

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
    mapping(uint256 => bool) internal s_slotFrozenByYields;
    mapping(uint256 => bool) internal s_slotFrozenByReserves;
    
    /// @dev global mapping to check if a slot is frozen, like false || false = false
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

////////////////////////////////////////////////////////////////////
////////////////////// freeze slots functions ////////////////////// 
////////////////////////////////////////////////////////////////////  
    function _setYieldsSlotFrozen(uint256 _slot, bool _frozen) private {
        s_slotFrozenByYields[_slot] = _frozen;    
        bool shouldBeFrozen = _frozen || s_slotFrozenByReserves[_slot];
        _setSlotFrozen(_slot, shouldBeFrozen);
    }

    function _setReservesSlotFrozen(uint256 _slot, bool _frozen) private {
        s_slotFrozenByReserves[_slot] = _frozen;
        bool shouldBeFrozen = _frozen || s_slotFrozenByYields[_slot];
        _setSlotFrozen(_slot, shouldBeFrozen);
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
        s_slotFrozenByYields[_slot] = _frozen;
        s_slotFrozenByReserves[_slot] = _frozen;
        _setSlotFrozen(_slot, _frozen);
    }

    function _updateYieldsValues() internal {
        (bool freeze1, bool freeze2, bool freeze3, bool freeze4) = _updateLastValidYields();
        _setYieldsSlotFrozen(C.SLOT_2Y,  freeze1);
        _setYieldsSlotFrozen(C.SLOT_5Y,  freeze2);
        _setYieldsSlotFrozen(C.SLOT_10Y, freeze3);
        _setYieldsSlotFrozen(C.SLOT_30Y, freeze4);
    }

    function _updateReservesValues() internal {
        ( bool freeze1, bool freeze2, bool freeze3, bool freeze4) = _updateLastValidReserves();
        _setReservesSlotFrozen(C.SLOT_2Y,  freeze1);
        _setReservesSlotFrozen(C.SLOT_5Y,  freeze2);
        _setReservesSlotFrozen(C.SLOT_10Y, freeze3);
        _setReservesSlotFrozen(C.SLOT_30Y, freeze4);
    }

////////////////////////////////////////////////////////////////////
////////////////// update yields and reserves ////////////////////// 
////////////////////////////////////////////////////////////////////  

    function _updateLastValidYields() internal returns (bool freezeSlot1, bool freezeSlot2, bool freezeSlot3, bool freezeSlot4) {
            // 1. Check if oracle data is newer than the last valid data we have
            uint256 lastUpdateTimestamp = i_yieldsOracle.getLastUpdatedTimestamp();
            if (s_lastValidYields.timestamp >= lastUpdateTimestamp) {
                return (false, false, false, false);
            }

            // 2. Retrieve new data and validate each slot
            BondYieldsResponse memory newYieldsResponse = i_yieldsOracle.getAllYields();
            freezeSlot1 = _validateAndUpdateLastValidYield(C.SLOT_2Y,  newYieldsResponse.twoYearYield);
            freezeSlot2 = _validateAndUpdateLastValidYield(C.SLOT_5Y,  newYieldsResponse.fiveYearYield);
            freezeSlot3 = _validateAndUpdateLastValidYield(C.SLOT_10Y, newYieldsResponse.tenYearYield);
            freezeSlot4 = _validateAndUpdateLastValidYield(C.SLOT_30Y, newYieldsResponse.thirtyYearYield);

            // 3. All slots valid — update storage with new data
            if (!freezeSlot1 && !freezeSlot2 && !freezeSlot3 && !freezeSlot4) {
                s_lastValidYields = newYieldsResponse;
                return (false, false, false, false);
            }

            // 4. At least one anomaly — build mixed response
            // frozen slots keep old values, healthy slots get new values
            BondYieldsResponse memory cached = s_lastValidYields;
            s_lastValidYields = BondYieldsResponse({
                twoYearYield:    freezeSlot1 ? cached.twoYearYield    : newYieldsResponse.twoYearYield,
                fiveYearYield:   freezeSlot2 ? cached.fiveYearYield   : newYieldsResponse.fiveYearYield,
                tenYearYield:    freezeSlot3 ? cached.tenYearYield    : newYieldsResponse.tenYearYield,
                thirtyYearYield: freezeSlot4 ? cached.thirtyYearYield : newYieldsResponse.thirtyYearYield,
                timestamp:       cached.timestamp
            });
    }

    function _updateLastValidReserves () internal returns (bool freezeSlot1, bool freezeSlot2, bool freezeSlot3, bool freezeSlot4) {
        // 1. Check if oracle data is newer than the last valid data we have
        uint256 lastUpdateTimestamp = i_reservesOracle.getLastUpdatedTimestamp();
        if (s_lastValidReserves.timestamp >= lastUpdateTimestamp) {
            return (false, false, false, false);
        }

        // 2. Retrieve new data and validate bond value per slot
        ReservesResponse memory newReservesResponse = i_reservesOracle.getAllReserves();
        freezeSlot1 = _validateAndUpdateLastValidReserve(C.SLOT_2Y,  newReservesResponse.twoYearUsdBondsValue);
        freezeSlot2 = _validateAndUpdateLastValidReserve(C.SLOT_5Y,  newReservesResponse.fiveYearUsdBondsValue);
        freezeSlot3 = _validateAndUpdateLastValidReserve(C.SLOT_10Y, newReservesResponse.tenYearUsdBondsValue);
        freezeSlot4 = _validateAndUpdateLastValidReserve(C.SLOT_30Y, newReservesResponse.thirtyYearUsdBondsValue);

        // 3. Validate cash buffer per slot — only if bond value was valid
        if (!freezeSlot1) freezeSlot1 = _validateAndUpdateLastValidCashBuffer(C.SLOT_2Y,  newReservesResponse.twoYearUsdCashValue);
        if (!freezeSlot2) freezeSlot2 = _validateAndUpdateLastValidCashBuffer(C.SLOT_5Y,  newReservesResponse.fiveYearUsdCashValue);
        if (!freezeSlot3) freezeSlot3 = _validateAndUpdateLastValidCashBuffer(C.SLOT_10Y, newReservesResponse.tenYearUsdCashValue);
        if (!freezeSlot4) freezeSlot4 = _validateAndUpdateLastValidCashBuffer(C.SLOT_30Y, newReservesResponse.thirtyYearUsdCashValue);

        // 4. All slots valid — update storage with new data
        if (!freezeSlot1 && !freezeSlot2 && !freezeSlot3 && !freezeSlot4) {
            s_lastValidReserves = newReservesResponse;
            return (false, false, false, false);
        }

        // 5. At least one anomaly — build mixed response
        // frozen slots keep old values, healthy slots get new values
        ReservesResponse memory cached = s_lastValidReserves;
        s_lastValidReserves = ReservesResponse({
            twoYearUsdBondsValue:    freezeSlot1 ? cached.twoYearUsdBondsValue    : newReservesResponse.twoYearUsdBondsValue,
            fiveYearUsdBondsValue:   freezeSlot2 ? cached.fiveYearUsdBondsValue   : newReservesResponse.fiveYearUsdBondsValue,
            tenYearUsdBondsValue:    freezeSlot3 ? cached.tenYearUsdBondsValue    : newReservesResponse.tenYearUsdBondsValue,
            thirtyYearUsdBondsValue: freezeSlot4 ? cached.thirtyYearUsdBondsValue : newReservesResponse.thirtyYearUsdBondsValue,

            twoYearUsdCashValue:    freezeSlot1 ? cached.twoYearUsdCashValue    : newReservesResponse.twoYearUsdCashValue,
            fiveYearUsdCashValue:   freezeSlot2 ? cached.fiveYearUsdCashValue   : newReservesResponse.fiveYearUsdCashValue,
            tenYearUsdCashValue:    freezeSlot3 ? cached.tenYearUsdCashValue    : newReservesResponse.tenYearUsdCashValue,
            thirtyYearUsdCashValue: freezeSlot4 ? cached.thirtyYearUsdCashValue : newReservesResponse.thirtyYearUsdCashValue,

            // total cash buffer: se almeno uno slot è frozen, tieni il valore cached
            cashBufferUsdTotalValue: (freezeSlot1 || freezeSlot2 || freezeSlot3 || freezeSlot4)
                ? cached.cashBufferUsdTotalValue
                : newReservesResponse.cashBufferUsdTotalValue,

            // total bonds value: solo se tutti frozen tieni cached, altrimenti ricalcola
            totalUsdBondsValue: (freezeSlot1 && freezeSlot2 && freezeSlot3 && freezeSlot4)
                ? cached.totalUsdBondsValue
                : newReservesResponse.totalUsdBondsValue,

            // total portfolio value: solo se tutti frozen tieni cached, altrimenti ricalcola
            totalUsdPortfolioValue: (freezeSlot1 && freezeSlot2 && freezeSlot3 && freezeSlot4)
                ? cached.totalUsdPortfolioValue
                : newReservesResponse.totalUsdPortfolioValue,

            timestamp: cached.timestamp
        });
    }




/////////////////////////////////////////////////////////////////////
//////////////////////// Reserves validation ////////////////////////
/////////////////////////////////////////////////////////////////////

    function _validateAndUpdateLastValidReserve(uint256 _slot, uint256 _reserve) private  returns (bool freezeSlot) {
        if(_reserve == 0) {
            freezeSlot = true;
            emit InvalidReserve(_slot, _reserve);
            return freezeSlot;
        }
        uint256 lastValidReserve = s_lastValidReservePerSlot[_slot];
        if(lastValidReserve != 0) {
            uint256 shock = _reserve > lastValidReserve ? _reserve - lastValidReserve : 
            lastValidReserve - _reserve;
            if (shock > MAX_RESERVES_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveReserveShock(_slot, shock);
                return freezeSlot;
            }
        }
        s_lastValidReservePerSlot[_slot] = _reserve;
        freezeSlot = false;
    }

    function _validateAndUpdateLastValidCashBuffer(uint256 _slot, uint256 _cashBuffer) private returns (bool freezeSlot){
        if (_cashBuffer == 0) {
            freezeSlot = true;
            emit InvalidCashBuffer(_slot, _cashBuffer);
            return freezeSlot;
        }
        uint256 lastValidCashBuffer = s_lastValidCashBufferPerSlot[_slot];
        if(lastValidCashBuffer != 0) {
            uint256 shock = _cashBuffer > lastValidCashBuffer ? _cashBuffer - lastValidCashBuffer : 
            lastValidCashBuffer - _cashBuffer;
            if (shock > MAX_RESERVES_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveCashBufferShock(_slot, shock);
                return freezeSlot;
            }
        }
        s_lastValidCashBufferPerSlot[_slot] = _cashBuffer;
        freezeSlot = false;
    }

    function _getTotalLiabilitiesForSlot(uint256 _slot) internal view returns (uint256) {
        return s_totalLiabilitiesPerSlot[_slot];
    }

/////////////////////////////////////////////////////////////////////
///////////////////////// Yields validation /////////////////////////
/////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////
/////////////////// Return oracle data confirmed /////////////////// 
////////////////////////////////////////////////////////////////////  

    function _getLastValidYields(uint256 _slot) internal view returns (BondYieldsResponse memory yields){
        // 1. Check if oracle data is not stale, to avoid using outdated data
        if (i_yieldsOracle.isStale()) revert RiskManager__StaleOracleData();

        // 2. Check if slot is frozen due to detected shock or oracle malfunction
        if (s_slotFrozen[_slot]) revert RiskManager__SlotFrozen(_slot);

        // 3. Retreive the current data from oracles
        yields = s_lastValidYields;
    }

    function _getLastValidReserves(uint256 _slot) internal view returns (ReservesResponse memory reserves){
        // 1. Check if oracle data is not stale, to avoid using outdated data
        if (i_reservesOracle.isStale()) revert RiskManager__StaleOracleData();

        // 2. Check if slot is frozen due to detected shock or oracle malfunction
        if (s_slotFrozen[_slot]) revert RiskManager__SlotFrozen(_slot);

        // 3. Retreive the current data from oracles
        reserves = s_lastValidReserves;
    }

////////////////////////////////////////////////////////////////////
///////////////////////// Lifecycle Hooks ////////////////////////// 
////////////////////////////////////////////////////////////////////  

    function _riskManagerBeforeMint(uint256 _slot, uint256 _value) internal {

        // @audit-issue forse eliminare 1 2 e 3 perchè già presennti in _getLastValidYields e _getLastValidReserves, oppure chiamare questi ultimi per evitare di ripetere i check
        // 1. Check if oracle data is not stale, to avoid using outdated data
        if (i_yieldsOracle.isStale()) revert RiskManager__StaleOracleData();
        if (i_reservesOracle.isStale()) revert RiskManager__StaleOracleData();

        // 2. Check if slot is frozen due to detected shock or oracle malfunction
        if (s_slotFrozen[_slot]) revert RiskManager__SlotFrozen(_slot);

        // 3. Retreive the current data from oracles
        BondYieldsResponse memory yields = s_lastValidYields;
        ReservesResponse memory reserves = s_lastValidReserves;

        // 4. Check if reserves are sufficient for the new position, considering the new liabilities

        // 5. Update storage
        // 5.1 Update total liabilities for the slot
        s_totalLiabilitiesPerSlot[_slot] += _value;
    }

    function _riskManagerBeforeBurn(uint256 _slot, uint256 _value) internal {

        // 1. Check if oracle data is not stale, to avoid using outdated data
        if (i_yieldsOracle.isStale()) revert RiskManager__StaleOracleData();
        if (i_reservesOracle.isStale()) revert RiskManager__StaleOracleData();

        // 2. Check if slot is frozen due to detected shock or oracle malfunction
        if (s_slotFrozen[_slot]) revert RiskManager__SlotFrozen(_slot);

        // 3. Retreive the current data from oracles
        BondYieldsResponse memory yields = s_lastValidYields;
        ReservesResponse memory reserves = s_lastValidReserves;

        // 4. Check if liquidity is sufficient for the redemption, considering the new liabilities

        // 5. Update storage
        // 5.1 Update total liabilities for the slot
        s_totalLiabilitiesPerSlot[_slot] -= _value;
    }

    // claiming yield trigger before mint, attenzione
    function _riskManagerBeforeClaimingYield(uint256 _slot, uint256 _value) internal {

        // 1. Check if oracle data is not stale, to avoid using outdated data
        if (i_yieldsOracle.isStale()) revert RiskManager__StaleOracleData();
        if (i_reservesOracle.isStale()) revert RiskManager__StaleOracleData();
        // 2. Check if slot is frozen due to detected shock or oracle malfunction
        if (s_slotFrozen[_slot]) revert RiskManager__SlotFrozen(_slot);

        // 3. Retreive the current data from oracles
        BondYieldsResponse memory yields = s_lastValidYields;
        ReservesResponse memory reserves = s_lastValidReserves;

        // 5. Update storage
        // 5.1 Update total liabilities for the slot
       

    }


}