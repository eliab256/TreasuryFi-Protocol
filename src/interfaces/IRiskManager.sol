//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRiskManager {

    // --- Errors ---
    error RiskManager__InvalidYield(uint256  slot, uint256 yield);
    error RiskManager__ExcessiveYieldShock(uint256  slot, uint256 shock);
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

    // --- Events ---
    event SlotFrozen(uint256 indexed slot);
    event SlotUnfrozen(uint256 indexed slot);
    event InvalidYield(uint256 indexed slot, uint256 yield);
    event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);
    event InvalidReserve(uint256 indexed slot, uint256 reserve);
    event ExcessiveReserveShock(uint256 indexed slot, uint256 shock);
    event InvalidCashBuffer(uint256 indexed slot, uint256 cashBuffer);
    event ExcessiveCashBufferShock(uint256 indexed slot, uint256 shock);
    event SlotRiskParamsUpdated(uint256 indexed slot, uint256 reserveBuffer, uint256 maxDailyRedeemBps, uint256 redeemWindowOpen, uint256 redeemWindowDuration);

    // --- Functions ---
    function getBondAutomation() external view returns (address);
    function getReservesAutomation() external view returns (address);
    function getBondOracle() external view returns (address);
    function getReservesOracle() external view returns (address);
    function getTreasury() external view returns (address);
    function getInterval() external view returns (uint256);
    function getGracePeriod() external view returns (uint256);
}