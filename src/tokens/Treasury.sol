//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITreasury} from "../interfaces/ITreasury.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TokenConstants as C} from "./TokenConstants.sol";

/**
 * @title Treasury
 * @author Eliab B. (@eliab256)
 * @notice This contract manages the USDC deposits, withdrawals, and fee accounting for the TreasuryFi protocol.
 */
contract Treasury is AccessControl, ITreasury {

    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant TOKEN_CONTRACT_ROLE = keccak256("TOKEN_CONTRACT_ROLE");
    bytes32 public constant FEES_COLLECTOR_ROLE = keccak256("FEES_COLLECTOR_ROLE");
    bytes32 public constant LIQUIDITY_DEPOSITOR_ROLE = keccak256("LIQUIDITY_DEPOSITOR_ROLE");
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

    modifier onlyValidSlot(uint256 slot) {
        _onlyValidSlot(slot);
        _;
    }

    constructor(address _treasuryBondToken, address _usdc, address _feeCollector, address _liquidityDepositor) {
        i_treasuryBondToken = _treasuryBondToken;
        i_usdc = IERC20(_usdc);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(TOKEN_CONTRACT_ROLE, _treasuryBondToken);
        _setupRole(FEES_COLLECTOR_ROLE, _feeCollector);
        _setupRole(LIQUIDITY_DEPOSITOR_ROLE, _liquidityDepositor);
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function depositUsdcFromOpenNewPosition(
        uint256 _amount, address _from, uint256 _slot, uint256 _feeAmount
        ) external onlyRole(TOKEN_CONTRACT_ROLE) onlyValidSlot(_slot){
        // 1. update accounting 
        uint256 totalAmount = _amount + _feeAmount;
        s_totalUsdcPerSlot[_slot] += totalAmount;
        _updateFeeAccounting(_feeAmount, 0, 0, _slot);
        // 2. transfer USDC from the user to the treasury
        i_usdc.safeTransferFrom(_from, address(this), totalAmount);

        // 3. emit event usdcDepositedFromOpenNewPosition
        emit usdcDepositedFromOpenNewPosition(_amount, _from, _slot);
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function withdrawUsdcFromClosePosition(uint256 _usdcPayout, address _to, uint256 _slot,uint256 _yieldPayout, uint256 _exitFee, uint256 _managementFee) 
        external onlyRole(TOKEN_CONTRACT_ROLE) onlyValidSlot(_slot){
        // 1. get total payout
        uint256 totalPayout = _usdcPayout + _yieldPayout;

        //2. check if treasury has enough liquidity to pay the user
        if(totalPayout > s_totalUsdcPerSlot[_slot]){
            revert Treasury__InsufficientLiquidity();
        }
      
        // 3. update accounting 
        s_totalUsdcPerSlot[_slot] -= (totalPayout + _exitFee + _managementFee);
        _updateFeeAccounting(0, _exitFee, _yieldPayout, _slot);

        // 4. transfer USDC from the treasury to the user
        i_usdc.safeTransfer(_to, totalPayout);
        
        // 5. emit event usdcWithdrawnFromClosePosition
        emit usdcWithdrawnFromClosePosition(totalPayout, _to, _slot);
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function transferUsdcFromYieldClaim(uint256 _yieldPayout, address _to, uint256 _slot, uint256 _feeOnYield) external onlyRole(WITHDRAW_ROLE) onlyValidSlot(_slot){
        if(_yieldPayout > s_totalUsdcPerSlot[_slot]){
            revert Treasury__InsufficientLiquidity();
        }

        uint256 totalAmount = _yieldPayout + _feeOnYield;

        // 1. update accounting 
        s_totalUsdcPerSlot[_slot] -= totalAmount;
        _updateFeeAccounting(0, 0, _feeOnYield, _slot);
        // 2. transfer USDC from the treasury to the user
        i_usdc.safeTransfer(_to, _yieldPayout);
        
        // 3. emit event usdcWithdrawnFromClosePosition
        emit usdcWithdrawnFromClaimYield(_yieldPayout, _to, _slot);
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function useFeesCollectedToInjectLiquidity(uint256 _amount, uint256 _slot) external onlyRole(FEES_COLLECTOR_ROLE) onlyValidSlot(_slot){
        if(_amount == type(uint256).max){
            _amount = s_totalFeesToBeCollected;
        }

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

    /// @dev Inherited from ITreasury. See interface for details.
    function collectFees(uint256 _amount, address _to) external onlyRole(FEES_COLLECTOR_ROLE){
        if(_amount > s_totalFeesToBeCollected){
            revert Treasury__AmountExceedsTotalFeesToBeCollected();
        }
        // 1. update accounting
        s_totalFeesToBeCollected -= _amount.toUint128();

        // 2. transfer USDC from the treasury to the fee collector
        i_usdc.safeTransfer(_to, _amount);
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function injectLiquidity(uint256 _amount, uint256 _slot) external onlyRole(LIQUIDITY_DEPOSITOR_ROLE) onlyValidSlot(_slot){
        // 1. update accounting 
        s_totalUsdcPerSlot[_slot] += _amount;

        // 2. transfer USDC from the admin to the treasury
        i_usdc.safeTransferFrom(msg.sender, address(this), _amount);

        // 3.  emit event LiquidityInjected
        emit LiquidityInjected(_amount, _slot);
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function injectLiquidityOnMultipleSlots(uint256[] calldata _amounts, uint256[] calldata _slots) external onlyRole(LIQUIDITY_DEPOSITOR_ROLE){
        uint256 amountsLength = _amounts.length;
        uint256 slotsLength = _slots.length;
        if(amountsLength != 4 || slotsLength != 4){
            revert Treasury__InvalidArrayInput();
        }

        unchecked{
            for(uint256 i = 0; i < slotsLength; i++){
                _onlyValidSlot(_slots[i]);
            }
        }
            
        uint256 totalAmount;
        for(uint256 i = 0; i < slotsLength; i++){
            s_totalUsdcPerSlot[_slots[i]] += _amounts[i];
            totalAmount += _amounts[i];
            emit LiquidityInjected(_amounts[i], _slots[i]);
        }
        i_usdc.safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    /**
     * @notice Internal function to update fee accounting variables and emit FeeGenerated event.
     * @dev This function is called whenever fees are generated on deposit, exit or yield claim to 
     *      keep track of total fees collected and fees to be collected.
     * @param _feeOnDeposit The amount of fees generated on deposit.
     * @param _feeOnExit The amount of fees generated on exit.
     * @param _feeOnYield The amount of fees generated on yield claim.
     * @param _slot The slot corresponding to the bond for which fees are being generated (2Y, 5Y, 10Y, or 30Y).
     */
    function _updateFeeAccounting(uint256 _feeOnDeposit, uint256 _feeOnExit, uint256 _feeOnYield, uint256 _slot) internal {
        s_totalFeesCollected += (_feeOnDeposit + _feeOnExit + _feeOnYield).toUint128();
        s_totalFeesToBeCollected += (_feeOnDeposit + _feeOnExit + _feeOnYield).toUint128();

        emit FeeGenerated(_feeOnDeposit, _feeOnYield, _feeOnExit, _slot);
    }

    /**
     * @notice Internal function to validate that a slot is one of the predefined constants.
     * @dev Ensures that the provided slot is valid.
     * @param _slot The slot to validate.
     * Reverts if the slot is not one of the predefined constants (2Y, 5Y, 10Y, 30Y).
     */
    function _onlyValidSlot(uint256 _slot) internal pure {
        if (
            _slot != C.SLOT_2Y &&
            _slot != C.SLOT_5Y &&
            _slot != C.SLOT_10Y &&
            _slot != C.SLOT_30Y
        ) {
            revert TreasuryBondToken__InvalidSlot();
        }
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function getTotalFeesCollected() external view returns (uint256){
        return s_totalFeesCollected;
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function getTotalFeesToBeCollected() external view returns (uint256){
        return s_totalFeesToBeCollected;
    }

    /// @dev Inherited from ITreasury. See interface for details.
    function getTotalUsdcLiquidityPerSlot(uint256 _slot) external view returns (uint256){
        return s_totalUsdcPerSlot[_slot];
    }


}