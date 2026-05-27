// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ITreasury} from "../../../src/interfaces/ITreasury.sol";

contract TreasuryTest is Test {

    ITreasury treasury;
    uint256 constant INVALID_SLOT = 999;

    function setUp() public {
        // Deploy Treasury contract and set up initial state for testing
    }   

        function test_Constructor_SetsInitialState() public {
        // test immutable variable initialization

        // test initial role

    }

    function test_Constructor_RevertIfAddressZero() public {

    }

    function test_SetTokenContract_AddressRoleAssignment() public {

    }

    function test_SetTokenContract_RevertIfNotAdmin() public {

    }

    function test_SetTokenContract_RevertIfAdrressZero() public {

    }

    function test_SetTokenContract_RevertIfAlreadySet() public {

    }

    function test_DepositUsdcFromOpenNewPosition_RevertIfNotCalledByTokenContract() public {

    }

    function  test_DepositUsdcFromOpenNewPosition_RevertIfInvalidSlot() public {

    }

    function test_DepositUsdcFromOpenNewPosition_RevertIfTransferFromFails() public {

    }

    function test_DepositUsdcFromOpenNewPosition_UpdateStatesAndEmitEvent() public {

    }

    function test_WithdrawUsdcFromClosePosition_RevertIfNotCalledByTokenContract() public {

    }

    function test_WithdrawUsdcFromClosePosition_RevertIfInvalidSlot() public {

    }

    function test_WithdrawUsdcFromClosePosition_RevertIfTransferToUserFails() public {

    }

    function test_WithdrawUsdcFromClosePosition_RevertIfTreasuryHasNotSufficientLiquidity() public {

    }

    function test_WithdrawUsdcFromClosePosition_UpdateStatesAndEmitEvent() public {

    }

    function test_transferUsdcFromYieldClaim_RevertIfNotCalledByTokenContract() public {

    }

    function test_transferUsdcFromYieldClaim_RevertIfInvalidSlot() public {

    }

    function test_transferUsdcFromYieldClaim_RevertIfTransferToUserFails() public {

    }

    function test_transferUsdcFromYieldClaim_RevertIfTreasuryHasNotSufficientLiquidity() public {

    }

    function test_transferUsdcFromYieldClaim_UpdateStatesAndEmitEvent() public {

    }

    function test_useFeesCollectedToInjectLiquidity_RevertIfNotFeesCollector() public {

    }

    function test_useFeesCollectedToInjectLiquidity_RevertIfAmountExceedFeesCollected() public {

    }

    function test_useFeesCollectedToInjectLiquidity_UpdateStatesAndEmitEvent() public {

    }

    function test_useFeesCollectedToInjectLiquidity_\() public {

    }

    function test_CollectFees_RevertIfNotFeesCollector() public {

    }

    function test_CollectFees_RevertIfAmountExceedFeesToBeCollected() public {

    }

    function test_CollectFees_RevertIfTransferToCollectorFails() public {

    }

    function test_CollectFees_UpdateStatesAndEmitEvent() public {

    }

    function test_CollectFees_TransferAllFeesIfAmountIsUint256Max() public {

    }

    function test_InjectLiquidity_RevertIfNotLiquidityDepositor() public {

    }

    function test_InjectLiquidity_RevertIfInvalidSlot() public {

    }

    function test_InjectLiquidity_RevertIfTransferFromFails() public {

    }

    function test_InjectLiquidity_UpdateStatesAndEmitEvent() public {

    }

    function test_InjectLiquidityOnMultipleSlots_RevertIfNotLiquidityDepositor() public {

    }

    function test_InjectLiquidityOnMultipleSlots_RevertIfArrayLengthMismatch() public {

    }

    function test_InjectLiquidityOnMultipleSlots_RevertIfInvalidSlot() public {

    }

    function test_InjectLiquidityOnMultipleSlots_RevertIfTransferFromFails() public {

    }

    function test_InjectLiquidityOnMultipleSlots_UpdateStatesAndEmitEventsForEachSlotUpdated() public {
    }

    function test_InjectLiquidityOnMultipleSlots_TokenBalanceAndInternalAccountingAreAligned() public {

    }

    function test_Getters_ReturnCorrectValues() public {

    }
}


