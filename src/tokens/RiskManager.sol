//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "./TokenConstants.sol";
import {BondYieldsResponse, ReservesResponse, SlotRiskParams} from "../types.sol";
import {IBondAutomation} from "../interfaces/IBondAutomation.sol";
import {IReservesAutomation} from "../interfaces/IReservesAutomation.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title RiskManager
 * @author Eliab B. (@eliab256)
 * @notice This abstract contract implements the risk managment layer for the TreasuryFi protocol
 *         It provides 
 *         - functions to validate the yields and reserves data retrieved from the oracles,
 *         - functions to freeze/unfreeze slots in case of anomalies.
 *         - functions to keep track of the last valid yields and reserves data, as well as the last valid yield, 
 *           reserve and cash buffer values per slot to detect possible shocks.
 *         - functions to verify the sanity of protocol after every transaction detecting liquidity or reserves issues.
 */
abstract contract RiskManager {
    using SafeCast for uint256;

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
    error RiskManager__InsufficientLiquidity(uint256 slot, uint256 availableLiquidity, uint256 requiredLiquidity);
    error RiskManager__InsufficientReserves(uint256 slot, uint256 availableReserves, uint256 requiredReserves);
    error RiskManager__DailyRedeemLimitExceeded(uint256 slot, uint256 requestedAmount, uint256 dailyLimit);
    error RiskManager__RedemptionWindowClosed(uint256 slot, uint256 currentTime, uint256 windowOpen, uint256 windowClose);
    error RiskManager__InvalidSlotParams();
    error RiskManager__InvalidReserveBuffer();
    error RiskManager__SlotRiskParamsNotSet(uint256 slot);
    error RiskManager__SolvencyNotGuaranteed();

    event SlotFrozen(uint256 indexed slot);
    event SlotUnfrozen(uint256 indexed slot);
    event InvalidYield(uint256 indexed slot, uint256 yield);
    event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);
    event InvalidReserve(uint256 indexed slot, uint256 reserve);
    event ExcessiveReserveShock(uint256 indexed slot, uint256 shock);
    event InvalidCashBuffer(uint256 indexed slot, uint256 cashBuffer);
    event ExcessiveCashBufferShock(uint256 indexed slot, uint256 shock);
    event SlotRiskParamsUpdated(uint256 indexed slot, uint256 reserveBuffer, uint256 maxDailyRedeemBps, uint256 redeemWindowOpen, uint256 redeemWindowDuration);

    uint256 internal constant MAX_YIELD_SHOCK_BPS = 5 * C.PERCENTAGE_PRECISION; // 5% shock
    uint256 internal constant MAX_YIELD = 20 * C.PERCENTAGE_PRECISION; // 20% max yield for sanity checks
    uint256 internal constant MAX_RESERVES_SHOCK_BPS = 30 * C.PERCENTAGE_PRECISION; // 30% shock
    uint256 private constant USD8_TO_USD18 = 1e10;

    IBondAutomation internal immutable i_yieldsAutomation;
    IReservesAutomation internal immutable i_reservesAutomation;

    IReservesOracle internal immutable i_reservesOracle;
    IBondOracle internal immutable i_yieldsOracle;
    ITreasury internal immutable i_treasury;

    uint256 internal immutable i_gracePeriod;
    uint256 internal immutable i_interval;
    uint256 internal s_lastUpkeepTriggerReserves;
    uint256 internal s_lastUpkeepTriggerYields;

    struct SlotMarketData {
        uint32 yield;        // bps, e.g. 4.50% = 45000
        uint112 reserve;     // USD 18 dec (converted from 8 dec oracle value)
        uint112 cashBuffer;  // USD 18 dec (converted from 8 dec oracle value)
    }
    /// @dev slot => last valid market data for the slot, used to detect shocks and freeze slots if needed
    /// @dev used to use only 1SLOAD to get all the data for a slot
    mapping(uint256 => SlotMarketData) private s_lastValidSlotMarketData; 
    
    /// @dev Mapping to track risk parameters for each slot
    mapping(uint256 => SlotRiskParams) private s_slotRiskParams;

    /// @dev Per-slot freeze state packed into one storage slot 
    ///      (frozenByYields + frozenByReserves + frozen = 3 bools → 1 SLOAD)
    struct SlotFreezeState {
        bool frozenByYields;
        bool frozenByReserves;
        bool frozen;
    }
    mapping(uint256 => SlotFreezeState) private s_slotFrozenState;

    /// @dev liabilities for each slot, updated on mint, burn and yield claim
    mapping(uint256 => uint256) private s_totalLiabilitiesPerSlot;

    /// @dev daily redeem volume per slot, reset every 24h, used by _validateRedeemRateLimit
    mapping(uint256 => uint256) private s_dailyRedeemVolume;
    /// @dev timestamp of the start of the current 24h redeem window per slot
    mapping(uint256 => uint256) private s_dailyRedeemWindowStart;

    BondYieldsResponse private s_lastValidYields;
    ReservesResponse private s_lastValidReserves;

    /**
     * @notice Constructor to initialize the RiskManager with references to automation and oracle contracts.
     * @dev All addresses checks are done on the main contract
     * @param _yieldsAutomation Address of the BondAutomation contract.
     * @param _reservesAutomation Address of the ReservesAutomation contract.
     * @param _reservesOracle Address of the ReservesOracle contract.
     * @param _yieldsOracle Address of the BondOracle contract.
     * @param _treasury Address of the Treasury contract, used to check liquidity for close and claim operations.
     */
    constructor(address _yieldsAutomation, address _reservesAutomation, address _reservesOracle, address _yieldsOracle, address _treasury) {
        i_yieldsAutomation = IBondAutomation(_yieldsAutomation);
        i_reservesAutomation = IReservesAutomation(_reservesAutomation);
        i_reservesOracle = IReservesOracle(_reservesOracle);
        i_yieldsOracle = IBondOracle(_yieldsOracle);
        i_treasury = ITreasury(_treasury);
        (i_interval , i_gracePeriod, ) = i_yieldsAutomation.getAllUpkeepInfo();
    }

////////////////////////////////////////////////////////////////////
////////////////////////// slot risk params //////////////////////// 
////////////////////////////////////////////////////////////////////  

    /**
     * @notice Internal function to set the risk parameters for a slot.
     * @dev Reverts if the provided parameters are invalid.
     * @param _slot The slot for which to set the risk parameters.
     * @param _params The risk parameters to set for the slot. Check types.sol
     */
    function _setSlotRiskParams(uint256 _slot, SlotRiskParams memory _params) internal {
        if(_params.reserveBuffer < C.MAX_PERCENTAGE) revert RiskManager__InvalidReserveBuffer();
        if (_params.redeemWindowOpen >= 7 days) revert RiskManager__InvalidSlotParams();
        if (_params.redeemWindowOpen + _params.redeemWindowDuration > 7 days)
            revert RiskManager__InvalidSlotParams();
        s_slotRiskParams[_slot] = _params;
        emit SlotRiskParamsUpdated(
            _slot,
            _params.reserveBuffer,
            _params.maxDailyRedeem,
            _params.redeemWindowOpen,
            _params.redeemWindowDuration
        );
    }

    /**
     * @notice Internal function to check if the risk parameters for a slot are set.
     * @dev This function must be used on a modifier to ensure that the risk parameters 
     *      are set before allowing certain operations on a slot.
     * @dev Reverts if the risk parameters for the given slot are not set.
     * @param _slot The slot to check.
     */
    function _checkSlotRiskParamsSet(uint256 _slot) internal view {
        SlotRiskParams memory params = s_slotRiskParams[_slot];
        if (params.reserveBuffer == 0 ) {
            revert RiskManager__SlotRiskParamsNotSet(_slot);
        }
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
        SlotFreezeState storage frozenState = s_slotFrozenState[_slot];
        frozenState.frozenByYields = _frozen;
        bool shouldBeFrozen = _frozen || frozenState.frozenByReserves;
        _setSlotFrozen(_slot, frozenState, shouldBeFrozen);
    }

    function _setReservesSlotFrozen(uint256 _slot, bool _frozen) private {
        SlotFreezeState storage frozenState = s_slotFrozenState[_slot];
        frozenState.frozenByReserves = _frozen;
        bool shouldBeFrozen = _frozen || frozenState.frozenByYields;
        _setSlotFrozen(_slot, frozenState, shouldBeFrozen);
    }

    function _setSlotFrozen(uint256 _slot, SlotFreezeState storage state, bool _frozen) private {
        if (state.frozen == _frozen) return;
        state.frozen = _frozen;
        if (_frozen) emit SlotFrozen(_slot);
        else emit SlotUnfrozen(_slot);
    }

    /**
     * @notice Sets the frozen state of a slot, implement access control on the main contract
     * @param _slot The slot to update
     * @param _frozen The new frozen state
     */
    function _setSlotFrozenOnMainContract(uint256 _slot, bool _frozen) internal {
        SlotFreezeState storage frozenState = s_slotFrozenState[_slot];
        if (frozenState.frozen == _frozen) revert RiskManager__SlotAlreadyInState(_slot, _frozen);
        frozenState.frozenByYields = _frozen;
        frozenState.frozenByReserves = _frozen;
        _setSlotFrozen(_slot, frozenState, _frozen);
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

        // 4. All slots valid — update storage with new data (convert USD8 → USD18)
        if (!freezeSlot1 && !freezeSlot2 && !freezeSlot3 && !freezeSlot4) {
            s_lastValidReserves = ReservesResponse({
                twoYearUsdBondsValue:    newReservesResponse.twoYearUsdBondsValue    * USD8_TO_USD18,
                fiveYearUsdBondsValue:   newReservesResponse.fiveYearUsdBondsValue   * USD8_TO_USD18,
                tenYearUsdBondsValue:    newReservesResponse.tenYearUsdBondsValue    * USD8_TO_USD18,
                thirtyYearUsdBondsValue: newReservesResponse.thirtyYearUsdBondsValue * USD8_TO_USD18,
                twoYearUsdCashValue:    newReservesResponse.twoYearUsdCashValue    * USD8_TO_USD18,
                fiveYearUsdCashValue:   newReservesResponse.fiveYearUsdCashValue   * USD8_TO_USD18,
                tenYearUsdCashValue:    newReservesResponse.tenYearUsdCashValue    * USD8_TO_USD18,
                thirtyYearUsdCashValue: newReservesResponse.thirtyYearUsdCashValue * USD8_TO_USD18,
                cashBufferUsdTotalValue: newReservesResponse.cashBufferUsdTotalValue * USD8_TO_USD18,
                totalUsdBondsValue:      newReservesResponse.totalUsdBondsValue      * USD8_TO_USD18,
                totalUsdPortfolioValue:  newReservesResponse.totalUsdPortfolioValue  * USD8_TO_USD18,
                timestamp: newReservesResponse.timestamp
            });
            return (false, false, false, false);
        }

        // 5. At least one anomaly — build mixed response
        // frozen slots keep old values (already USD18), healthy slots get new values (convert USD8 → USD18)
        ReservesResponse memory cached = s_lastValidReserves;
        s_lastValidReserves = ReservesResponse({
            twoYearUsdBondsValue:    freezeSlot1 ? cached.twoYearUsdBondsValue    : newReservesResponse.twoYearUsdBondsValue    * USD8_TO_USD18,
            fiveYearUsdBondsValue:   freezeSlot2 ? cached.fiveYearUsdBondsValue   : newReservesResponse.fiveYearUsdBondsValue   * USD8_TO_USD18,
            tenYearUsdBondsValue:    freezeSlot3 ? cached.tenYearUsdBondsValue    : newReservesResponse.tenYearUsdBondsValue    * USD8_TO_USD18,
            thirtyYearUsdBondsValue: freezeSlot4 ? cached.thirtyYearUsdBondsValue : newReservesResponse.thirtyYearUsdBondsValue * USD8_TO_USD18,

            twoYearUsdCashValue:    freezeSlot1 ? cached.twoYearUsdCashValue    : newReservesResponse.twoYearUsdCashValue    * USD8_TO_USD18,
            fiveYearUsdCashValue:   freezeSlot2 ? cached.fiveYearUsdCashValue   : newReservesResponse.fiveYearUsdCashValue   * USD8_TO_USD18,
            tenYearUsdCashValue:    freezeSlot3 ? cached.tenYearUsdCashValue    : newReservesResponse.tenYearUsdCashValue    * USD8_TO_USD18,
            thirtyYearUsdCashValue: freezeSlot4 ? cached.thirtyYearUsdCashValue : newReservesResponse.thirtyYearUsdCashValue * USD8_TO_USD18,

            // total cash buffer: se almeno uno slot è frozen, tieni il valore cached
            cashBufferUsdTotalValue: (freezeSlot1 || freezeSlot2 || freezeSlot3 || freezeSlot4)
                ? cached.cashBufferUsdTotalValue
                : newReservesResponse.cashBufferUsdTotalValue * USD8_TO_USD18,

            // @audit-issue DISCREPANZA TOTALI AGGREGATI IN RAMO MIXED RESPONSE:
            // Se 1-3 slot sono frozen, i valori per-slot frozen mantengono il valore cached (vecchio),
            // ma totalUsdBondsValue e totalUsdPortfolioValue vengono presi da newReservesResponse
            // (totale oracolo) che include il valore NUOVO dello slot frozen (potenzialmente anomalo).
            // Risultato: totalUsdBondsValue != somma dei per-slot stored.
            // Fix: ricalcolare i totali sommando i per-slot cached/new in base ai freeze flag,
            // oppure eliminare i totali dalla struct e calcolarli on-demand dai per-slot.

            // total bonds value: solo se tutti frozen tieni cached, altrimenti ricalcola
            totalUsdBondsValue: (freezeSlot1 && freezeSlot2 && freezeSlot3 && freezeSlot4)
                ? cached.totalUsdBondsValue
                : newReservesResponse.totalUsdBondsValue * USD8_TO_USD18,

            // total portfolio value: solo se tutti frozen tieni cached, altrimenti ricalcola
            totalUsdPortfolioValue: (freezeSlot1 && freezeSlot2 && freezeSlot3 && freezeSlot4)
                ? cached.totalUsdPortfolioValue
                : newReservesResponse.totalUsdPortfolioValue * USD8_TO_USD18,

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
        uint256 reserve18 = _reserve * USD8_TO_USD18;
        uint256 lastValidReserve = s_lastValidSlotMarketData[_slot].reserve;
        if(lastValidReserve != 0) {
            uint256 delta = reserve18 > lastValidReserve ? reserve18 - lastValidReserve : 
            lastValidReserve - reserve18;
            uint256 shockBps = (delta * C.MAX_PERCENTAGE) / lastValidReserve;
            if (shockBps > MAX_RESERVES_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveReserveShock(_slot, shockBps);
                return freezeSlot;
            }
        }
        s_lastValidSlotMarketData[_slot].reserve = reserve18.toUint112();
        freezeSlot = false;
    }

    function _validateAndUpdateLastValidCashBuffer(uint256 _slot, uint256 _cashBuffer) private returns (bool freezeSlot){
        if (_cashBuffer == 0) {
            freezeSlot = true;
            emit InvalidCashBuffer(_slot, _cashBuffer);
            return freezeSlot;
        }
        uint256 cashBuffer18 = _cashBuffer * USD8_TO_USD18;
        uint256 lastValidCashBuffer = s_lastValidSlotMarketData[_slot].cashBuffer;
        if(lastValidCashBuffer != 0) {
            uint256 delta = cashBuffer18 > lastValidCashBuffer ? cashBuffer18 - lastValidCashBuffer : 
            lastValidCashBuffer - cashBuffer18;
            uint256 shockBps = (delta * C.MAX_PERCENTAGE) / lastValidCashBuffer;
            if (shockBps > MAX_RESERVES_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveCashBufferShock(_slot, shockBps);
                return freezeSlot;
            }
        }
        s_lastValidSlotMarketData[_slot].cashBuffer = cashBuffer18.toUint112();
        freezeSlot = false;
    }

    function _validateMintReserves(uint256 _slot, uint256 _value, uint256 _reserves, uint256 _cashBuffer, uint256 _bufferPecentage) internal view {
        uint256 portfolioValue   = _reserves + _cashBuffer;
        uint256 currentLiabilities = s_totalLiabilitiesPerSlot[_slot];
        uint256 requiredReserves = (currentLiabilities + _value) * _bufferPecentage / C.MAX_PERCENTAGE;

        if (portfolioValue < requiredReserves) {
            revert RiskManager__InsufficientReserves(_slot, portfolioValue, requiredReserves);
        }
    }

    function _getTotalLiabilitiesForSlot(uint256 _slot) internal view returns (uint256) {
        return s_totalLiabilitiesPerSlot[_slot];
    }

    function _getMarketDataForSlot(uint256 _slot) internal view returns (uint256 yield, uint256 reserve, uint256 cashBuffer) {
        SlotMarketData memory data = s_lastValidSlotMarketData[_slot];
        return (data.yield, data.reserve, data.cashBuffer);
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
        uint256 lastValidYield = s_lastValidSlotMarketData[_slot].yield;
        if(lastValidYield != 0) {
            uint256 shock = _yield > lastValidYield ? _yield - lastValidYield : 
            lastValidYield - _yield;
            if (shock > MAX_YIELD_SHOCK_BPS) {
                freezeSlot = true;
                emit ExcessiveYieldShock(_slot, shock);
                return freezeSlot;
            }
        }
        s_lastValidSlotMarketData[_slot].yield = _yield.toUint32();
        freezeSlot = false;
    }

////////////////////////////////////////////////////////////////////
////////////////////// Liquidity validation //////////////////////// 
////////////////////////////////////////////////////////////////////  
    function _validateInstantLiquidity(uint256 _slot, uint256 _requiredLiquidity) private view {
        uint256 availableLiquidity = i_treasury.getTotalUsdcLiquidityPerSlot(_slot);
        if (availableLiquidity < _requiredLiquidity) {
            revert RiskManager__InsufficientLiquidity(_slot, availableLiquidity, _requiredLiquidity);
        }
    } 

////////////////////////////////////////////////////////////////////
//////////////////////// Redemption functions ////////////////////// 
////////////////////////////////////////////////////////////////////  

    function _validateRedemptionWindow(uint256 _slot, SlotRiskParams memory _riskParams) private view {
        if(_riskParams.redeemWindowDuration == 0) return; // if duration is 0, redemption window is always open
        uint256 secondsIntoWeek = block.timestamp % 7 days;
        uint256 windowOpen = _riskParams.redeemWindowOpen;
        uint256 windowClose = _riskParams.redeemWindowOpen + _riskParams.redeemWindowDuration;
        if (secondsIntoWeek < windowOpen || secondsIntoWeek > windowClose) {
            revert RiskManager__RedemptionWindowClosed(_slot, secondsIntoWeek, windowOpen, windowClose);
        }
    }

    /**
     * @notice Internal function to get the redemption window for a slot based on its risk parameters.
     * @dev Implement on public function on the main contract to allow external user to check the redemption window for a slot.
     * @param _slot The slot for which to get the redemption window.
     * @return nextWindowOpen The timestamp when the redemption window opens.
     * @return windowDuration The duration of the redemption window in seconds.
     */
    function _getNextRedemptionWindow(uint256 _slot) internal view returns (uint256 nextWindowOpen, uint256 windowDuration){
        SlotRiskParams memory riskParams = s_slotRiskParams[_slot];
        if(riskParams.redeemWindowDuration == 0) {
            return (block.timestamp, 0); // if duration is 0, redemption window is always open
        }

        uint256 secondsIntoWeek = block.timestamp % 7 days;
        uint256 weekStart = block.timestamp - secondsIntoWeek;

        if (secondsIntoWeek <= riskParams.redeemWindowOpen) {
            nextWindowOpen = weekStart + riskParams.redeemWindowOpen;
        } else {
            nextWindowOpen = weekStart + 7 days + riskParams.redeemWindowOpen;
        }
    }

    function _validateRedeemRateLimit(uint256 _slot, uint256 _redeemAmount, SlotRiskParams memory _riskParams) private {
        if (_riskParams.maxDailyRedeem == 0) return; // rate limit disabled

        // Reset the 24h window if it has elapsed
        if (block.timestamp > s_dailyRedeemWindowStart[_slot] + 1 days) {
            s_dailyRedeemVolume[_slot] = 0;
            s_dailyRedeemWindowStart[_slot] = block.timestamp;
        }

        uint256 newVolume = s_dailyRedeemVolume[_slot] + _redeemAmount;
        if (newVolume > _riskParams.maxDailyRedeem) {
            revert RiskManager__DailyRedeemLimitExceeded(_slot, _redeemAmount, _riskParams.maxDailyRedeem);
        }

        s_dailyRedeemVolume[_slot] = newVolume;
    }

////////////////////////////////////////////////////////////////////
/////////////////// Return oracle data confirmed /////////////////// 
////////////////////////////////////////////////////////////////////  

    /// @dev Lightweight safety check used by lifecycle hooks that do not need to read oracle data.
    ///      Reverts if either oracle is stale or the slot is frozen.
    function _checkSlotSafe(uint256 _slot) internal view {
        if (i_yieldsOracle.isStale() || i_reservesOracle.isStale()) revert RiskManager__StaleOracleData();
        if (s_slotFrozenState[_slot].frozen) revert RiskManager__SlotFrozen(_slot);
    }

////////////////////////////////////////////////////////////////////
///////////////////////// Lifecycle Hooks //////////////////////////   
////////////////////////////////////////////////////////////////////  

    function _riskManagerBeforeMint(uint256 _slot, uint256 _value) internal {
        // 1. Check staleness and freeze — no struct loaded in memory
        _checkSlotSafe(_slot);
        // 2. Save in memory current market data and risk params for this slot to avoid multiple SLOADs during validation
        SlotMarketData memory marketData = s_lastValidSlotMarketData[_slot];
        SlotRiskParams memory riskParams = s_slotRiskParams[_slot];

        // 3. Check reserve coverage for the new position, revert if the mint would put the protocol in an undercollateralized state
        _validateMintReserves(_slot, _value, marketData.reserve, marketData.cashBuffer, riskParams.reserveBuffer);

        // 4. Update liabilities
        s_totalLiabilitiesPerSlot[_slot] += _value;
    }

    function _riskManagerBeforeBurn(uint256 _slot, uint256 _value) internal {
        // 1. Check staleness and freeze 
        _checkSlotSafe(_slot);

        // 2. Update liabilities
        s_totalLiabilitiesPerSlot[_slot] -= _value;
    }


    function _riskManagerBeforeTransferLiquidity(uint256 _slot, uint256 _requiredLiquidity) internal {
        // 1. Validate that the protocol has enough usdc liquidity to cover the transfer, revert if not
        _validateInstantLiquidity(_slot, _requiredLiquidity);

        // 2. Save in memory current risk params for this slot to avoid multiple SLOADs during validation
        SlotRiskParams memory riskParams = s_slotRiskParams[_slot];

        // 3. Validate that the transfer does not violate the redemption rate limit or window, revert if it does
        _validateRedeemRateLimit(_slot, _requiredLiquidity, riskParams);
        _validateRedemptionWindow(_slot,riskParams);
    }

    function _isSolvent() internal view returns(bool) {
        // 1. Check if reserves and liquidity buffers data are not compromised
        if(s_slotFrozenState[C.SLOT_2Y].frozenByReserves) revert RiskManager__SolvencyNotGuaranteed();
        if(s_slotFrozenState[C.SLOT_5Y].frozenByReserves) revert RiskManager__SolvencyNotGuaranteed();
        if(s_slotFrozenState[C.SLOT_10Y].frozenByReserves) revert RiskManager__SolvencyNotGuaranteed();
        if(s_slotFrozenState[C.SLOT_30Y].frozenByReserves) revert RiskManager__SolvencyNotGuaranteed();

        // 2. Get total usd portfolio value
        uint256 totalPortfolio = s_lastValidReserves.totalUsdPortfolioValue;

        // 3. get total liabilities
        uint256 totalLiabilities;
        for (uint256 slot = C.SLOT_2Y; slot <= C.SLOT_30Y; slot++) {
            totalLiabilities += s_totalLiabilitiesPerSlot[slot];
        }

        // 4. Compare total portfolio value with total liabilities
        return totalPortfolio >= totalLiabilities;
    }

    /**
     * @notice Internal function to assert the solvency of the protocol, used in lifecycle hooks after state changes.
     * @dev Reverts if the protocol is not solvent, meaning that the total portfolio value is less than the total liabilities.
     * @dev Wrapper for public function on the main contract to allow external users to check the solvency of the protocol after certain operations.
     */    
    function _assertSolvency() internal view {
        if(!_isSolvent()) {
            revert RiskManager__SolvencyNotGuaranteed();
        }
    }

    
}