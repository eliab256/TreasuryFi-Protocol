//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITreasury} from "../interfaces/ITreasury.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Treasury is AccessControl, ITreasury {

    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE");
    address private immutable i_treasuryBondToken;
    IERC20 private immutable i_usdc;
    
    // Fee variables packed in a single storage slot

    /// @dev total fees collected by the protocol, updated on entry, exit and yield claim
    /// @dev is a 6 decimals value, since fees are collected in USDC
    uint128 private s_totalFeesCollected; 

    /// @dev total fees not already collected but not yet transferred to the fee collector
    /// @dev is a 6 decimals value, since fees are collected in USDC
    uint128 private s_totalFeesToBeCollected; 

    /// @dev total USDC deposited in the protocol per slot, updated on entry and exit
    mapping (uint256 => uint256) private s_totalUsdcPerSlot;

    constructor(address _treasuryBondToken, address _usdc) {
        i_treasuryBondToken = _treasuryBondToken;
        i_usdc = IERC20(_usdc);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(WITHDRAW_ROLE, _treasuryBondToken);
        _setupRole(DEPOSIT_ROLE, _treasuryBondToken);
    }

    function depositUsdcFromOpenNewPosition(
        uint256 _amount, address _from, uint256 _slot, uint256 _feeAmount
        ) external onlyRole(DEPOSIT_ROLE){
        // 1. update accounting 
        s_totalFeesCollected += _feeAmount.toUint128();
        s_totalFeesToBeCollected += _feeAmount.toUint128();
        s_totalUsdcPerSlot[_slot] += _amount - _feeAmount;
        // 2. transfer USDC from the user to the treasury
        i_usdc.safeTransferFrom(_from, address(this), _amount);

        // 3. emit event usdcDepositedFromOpenNewPosition
        emit usdcDepositedFromOpenNewPosition(_amount, _from, _slot, _feeAmount);

    }

    function withdrawUsdcFromClosePosition(uint256 _amount, address _to, uint256 _slot) external onlyRole(WITHDRAW_ROLE){
        if(_amount > s_totalUsdcPerSlot[_slot]){
            revert Treasury__AmountExceedsUsdcInSlot();
        }
        // 1. update accounting 
        s_totalUsdcPerSlot[_slot] -= _amount;
        // 2. transfer USDC from the treasury to the user
        i_usdc.safeTransfer(_to, _amount);
        
        // 3. emit event usdcWithdrawnFromClosePosition
        emit usdcWithdrawnFromClosePosition(_amount, _to, _slot);
    }

    function injectLiquidity(uint256 _amount, uint256 _slot) external onlyRole(DEPOSIT_ROLE){
        // 1. update accounting 
        s_totalUsdcPerSlot[_slot] += _amount;
        // 2. transfer USDC from the admin to the treasury
        i_usdc.safeTransferFrom(msg.sender, address(this), _amount);

        // 3.  emit event LiquidityInjected
        emit LiquidityInjected(_amount, _slot);
    }

    function useFeesCollectedToInjectLiquidity(uint256 _amount, uint256 _slot) external onlyRole(DEPOSIT_ROLE){
        if(_amount > s_totalFeesToBeCollected){
            revert Treasury__AmountExceedsFeesToBeCollected();
        }

        // 1. update accounting
        unchecked{
        s_totalFeesToBeCollected -= _amount.toUint128();
        s_totalUsdcPerSlot[_slot] += _amount;
        }

        // 2. emit event FeesUsedToInjectLiquidity
        emit FeesUsedToInjectLiquidity(_amount, _slot);
    }

    function collectFees(uint256 _amount, address _to) external onlyRole(DEPOSIT_ROLE){
        if(_amount > s_totalFeesToBeCollected){
            revert Treasury__AmountExceedsTotalFeesToBeCollected();
        }
        // 1. update accounting
        s_totalFeesToBeCollected -= _amount.toUint128();

        // 2. transfer USDC from the treasury to the fee collector
        i_usdc.safeTransfer(_to, _amount);
    }

    function getTotalFeesCollected() external view returns (uint256){
        return s_totalFeesCollected;
    }

    function getTotalFeesToBeCollected() external view returns (uint256){
        return s_totalFeesToBeCollected;
    }

    function getTotalUsdcPerSlot(uint256 _slot) external view returns (uint256){
        return s_totalUsdcPerSlot[_slot];
    }


}