//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    // ------ Errors ------
    error Treasury__AmountExceedsTotalFeesToBeCollected();
    error Treasury__AmountExceedsFeesToBeCollected();
    error Treasury__InsufficientLiquidity();
    error TreasuryBondToken__InvalidSlot();
    error Treasury__InvalidArrayInput();

    // ------ Events ------
    event usdcDepositedFromOpenNewPosition(uint256 indexed amount, address indexed from, uint256 indexed slot);
    event usdcWithdrawnFromClosePosition(uint256 indexed amount, address indexed to, uint256 indexed slot);
    event LiquidityInjected(uint256 indexed amount, uint256 indexed slot);
    event FeesUsedToInjectLiquidity(uint256 indexed amount, uint256 indexed slot);
    event usdcWithdrawnFromClaimYield(uint256 indexed amount, address indexed to, uint256 indexed slot);
    event FeeGenerated(uint256 indexed depositFee, uint256 indexed yieldFee, uint256 indexed exitFee, uint256 slot);


    // ------ Main functions ------
    function depositUsdcFromOpenNewPosition(uint256 _amount, address _from, uint256 _slot, uint256 _feeAmount) external; 
    function withdrawUsdcFromClosePosition(uint256 _usdcPayout, address _to, uint256 _slot, uint256 _yieldPayout, uint256 _exitFee, uint256 _managementFee) external;
    function transferUsdcFromYieldClaim(uint256 _yieldPayout, address _to, uint256 _slot, uint256 _feeOnYield) external;
    function injectLiquidity(uint256 _amount, uint256 _slot) external;
    function injectLiquidityOnMultipleSlots(uint256[] calldata _amounts, uint256[] calldata _slots) external;
    function useFeesCollectedToInjectLiquidity(uint256 _amount, uint256 _slot) external;
    function collectFees(uint256 _amount, address _to) external;

    // ------ Getters ------
    function getTotalFeesCollected() external view returns (uint256);
    function getTotalFeesToBeCollected() external view returns (uint256);
    function getTotalUsdcPerSlot(uint256 _slot) external view returns (uint256);

}