//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    function depositUsdcFromOpenNewPosition(uint256 _amount, address _from, uint256 _slot, uint256 _netValue, uint256 _feeAmount) external;
    
    function withdrawUsdc(uint256 _amount, address _to, uint256 _slot) external;
    
    function injectLiquidity(uint256 _amount, uint256 _slot) external;
    
    function emergencyWithdraw(uint256 _amount, address _to) external;
}