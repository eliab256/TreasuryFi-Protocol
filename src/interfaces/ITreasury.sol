//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    // ------ Errors ------
    error Treasury__AmountExceedsTotalFeesToBeCollected();
    error Treasury__AmountExceedsFeesToBeCollected();
    error Treasury__InsufficientLiquidity();

    // ------ Events ------
    event usdcDepositedFromOpenNewPosition(uint256 indexed amount, address indexed from, uint256 indexed slot, uint256 feeAmount);
    event usdcWithdrawnFromClosePosition(uint256 indexed amount, address indexed to, uint256 indexed slot, uint256 exitFee);
    event LiquidityInjected(uint256 indexed amount, uint256 indexed slot);
    event FeesUsedToInjectLiquidity(uint256 indexed amount, uint256 indexed slot);

    // ------ Main functions ------
    function depositUsdcFromOpenNewPosition(uint256 _amount, address _from, uint256 _slot, uint256 _feeAmount) external; 
    function withdrawUsdcFromClosePosition(uint256 _amount, address _to, uint256 _slot, uint256 _exitFee) external;
    function injectLiquidity(uint256 _amount, uint256 _slot) external;
    function useFeesCollectedToInjectLiquidity(uint256 _amount, uint256 _slot) external;

    // ------ Getters ------
    function getTotalFeesCollected() external view returns (uint256);
    function getTotalFeesToBeCollected() external view returns (uint256);
    function getTotalUsdcPerSlot(uint256 _slot) external view returns (uint256);

}