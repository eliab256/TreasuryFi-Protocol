//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Base} from "./Base.t.sol";
import {OracleDataExamples} from "./OracleDataExamples.sol";
import {TokenConstants as C} from "../../../src/tokens/TokenConstants.sol";

contract CoreLifeCycleTest is Base {

    function setUp() public override {
        super.setUp();
    }

    // function test_OpenPositionSuccessfulMint() public {
    //     uint256 slot = C.SLOT_2Y;
    //     uint256 totalDeposit = mockUsdc.balanceOf(USER_1);
    //     vm.prank(USER_1);
    //     uint256 newTokenId = treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);

    //     uint256 expectedTreasuryUsdcBalanceForSlot = (totalDeposit * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
    //     // 0,2% entry fee on the deposit amount
    //     uint256 calculateBalanceManually = totalDeposit * 2 / 1000;
    //     assertEq(expectedTreasuryUsdcBalanceForSlot, calculateBalanceManually, "Expected balance should match manual calculation");

    //     uint256 expectedLiabities = expectedTreasuryUsdcBalanceForSlot  *10 ** ( treasuryBondToken.valueDecimals()- mockUsdc.decimals());
    //     uint256 expectedFeeAmount = totalDeposit - expectedTreasuryUsdcBalanceForSlot;

    //     assertEq(treasuryBondToken.ownerOf(newTokenId), USER_1, "Token owner should be USER_1");
    //     assertEq(treasuryBondToken.balanceOf(USER_1), 1, "USER_1 should have 1 token");
    //     assertEq(treasuryBondToken.totalSupply(), 1, "Total supply should be 1 after minting");
    //     assertEq(treasuryBondToken.getTotalLiabilitiesPerSlot(slot), expectedLiabities, "Total liabilities for the slot should match the deposited amount");
    //     assertEq(treasury.getTotalFeesCollected(), expectedFeeAmount, "Treasury should have collected the correct fee amount");
    // }

    // function test_ClosePosition_FullBurn() public {
    //     // vm.startPrank(USER_1);
    //     // uint256 slot = C.SLOT_2Y;
    //     // uint256 totalDeposit = mockUsdc.balanceOf(USER_1);
    //     // uint256 newTokenId = treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);

    //     // // Fast forward time to after lock period
    //     // vm.warp(block.timestamp + 1);
    //     // uint256 tokenBalance = treasuryBondToken.balanceOf(newTokenId); // 18 decimals
    //     // treasuryBondToken.closePosition(newTokenId);
    //     // uint256 calculateExitFee = (tokenBalance * C.PERCENTAGE_EXIT_FEE_MAX) / C.MAX_PERCENTAGE;
    //     // uint256 expectedUsdcReturnedToUser = (tokenBalance - calculateExitFee) / 10 ** ( treasuryBondToken.valueDecimals() - mockUsdc.decimals());

    //     // uint256 newUserUsdcBalance = mockUsdc.balanceOf(USER_1);

    //     // assertEq(newUserUsdcBalance, expectedUsdcReturnedToUser, "USER_1 should receive the correct USDC amount after closing the position");
    //     // assertEq(treasuryBondToken.totalSupply(), 0, "Total supply should be 0 after burning the token");
    //     // assertEq(treasuryBondToken.getTotalLiabilitiesPerSlot(slot), 0, "Total liabilities for the slot should be 0 after closing the position");
    // }

    // function test_ClosePartialPosition_ProportionalPayout() public {

    // }

    // function test_ClaimYield_AfterLockPeriod_CorrectAmount() public {

    // }

    // function test_OpenPosition_RevertsIfInsufficientReserves() public {

    // }

    // function test_UpdateYields_BrokenData_FreezesAnomalousSlot() public {

    // }

    // function test_UpdateReserves_BrokenData_FreezesAnomalousSlot() public {

    // }

    // function test_ClosePosition_EarlyRedeemFee_Applied() public {

    // }

    // function test_OpenPosition_RevertsIfSlotFrozen() public {

    // }

    // function test_Solvency_AfterMultipleMints_Holds() public {

    // }
}