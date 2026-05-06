//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITreasury} from "../interfaces/ITreasury.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Treasury is AccessControl, ITreasury {
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE");
    address private immutable i_treasuryBondToken;
    IERC20 private immutable i_usdc;

    /// @dev total fees collected by the protocol, updated on entry, exit and yield claim
    /// @dev is a 6 decimals value, since fees are collected in USDC
    uint256 private s_totalFeesCollected; 

    constructor(address _treasuryBondToken, address _usdc) {
        i_treasuryBondToken = _treasuryBondToken;
        i_usdc = IERC20(_usdc);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(WITHDRAW_ROLE, _treasuryBondToken);
        _setupRole(DEPOSIT_ROLE, _treasuryBondToken);
    }

    function depositUsdcFromOpenNewPosition(
        uint256 _amount, address _from, uint256 _slot, uint256 _netValue, uint256 _feeAmount
        ) external onlyRole(DEPOSIT_ROLE){
        // 1. transfer USDC from the user to the treasury
        i_usdc.transferFrom(_from, address(this), _amount);
        // 2. update accounting 
        s_totalFeesCollected += _feeAmount;
    }

    function withdrawUsdc(uint256 _amount, address _to, uint256 _slot) external onlyRole(WITHDRAW_ROLE){
        // 1. transfer USDC from the treasury to the user
        i_usdc.transfer(_to, _amount);
        // 2. update accounting 
    }

    function injectLiquidity(uint256 _amount, uint256 _slot) external onlyRole(DEPOSIT_ROLE){
        // 1. transfer USDC from the admin to the treasury
        i_usdc.transferFrom(msg.sender, address(this), _amount);
        // 2. update accounting 
    }

    function emergencyWithdraw(uint256 _amount, address _to) external onlyRole(WITHDRAW_ROLE){
        // 1. transfer USDC from the treasury to the admin
        i_usdc.transfer(_to, _amount);
        // 2. update accounting 
    }

}