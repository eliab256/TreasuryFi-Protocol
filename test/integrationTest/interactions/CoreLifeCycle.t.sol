//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Base} from "./Base.t.sol";
import {OracleDataExamples} from "./OracleDataExamples.sol";
import {TokenConstants as C} from "../../../src/tokens/TokenConstants.sol";
import {ReservesResponse} from "../../../src/types.sol";
import {IRiskManager} from "../../../src/interfaces/IRiskManager.sol";
import {Vm} from "forge-std/Vm.sol";

import {console2} from "forge-std/console2.sol";

contract CoreLifeCycleTest is Base {

    function setUp() public override {
        super.setUp();
    }

    function test_OpenPositionSuccessfulMint() public {
        uint256 slot = C.SLOT_2Y;
        uint256 totalDeposit = mockUsdc.balanceOf(USER_1);
        vm.prank(USER_1);
        uint256 newTokenId = treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);

        uint256 usdcFeeAmount = (totalDeposit * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
        uint256 netUsdcAmountLessFees = totalDeposit - usdcFeeAmount;
        // 0,2% entry fee on the deposit amount
        uint256 feeAmountManually = totalDeposit * 2 / 1000;
        assertEq(usdcFeeAmount, feeAmountManually, "Calculated fee amount should match manual calculation");

        uint256 expectedLiabilities = netUsdcAmountLessFees  *10 ** ( treasuryBondToken.valueDecimals()- mockUsdc.decimals());

        assertEq(treasuryBondToken.ownerOf(newTokenId), USER_1, "Token owner should be USER_1");
        assertEq(treasuryBondToken.balanceOf(USER_1), 1, "USER_1 should have 1 token");
        assertEq(treasuryBondToken.totalSupply(), 1, "Total supply should be 1 after minting");
        assertEq(treasury.getTotalUsdcLiquidityPerSlot(slot), netUsdcAmountLessFees, "Total USDC liquidity for the slot should match the deposited amount minus fees");
        assertEq(treasury.getTotalFeesCollected(), usdcFeeAmount, "Treasury should have collected the correct fee amount");
    
        assertEq(treasuryBondToken.getTotalLiabilitiesPerSlot(slot), expectedLiabilities, "Total liabilities for the slot should match the deposited amount");
        assertEq(treasuryBondToken.balanceOf(newTokenId), expectedLiabilities, "Token balance should reflect the correct liabilities for the position");
    }

    function test_ClosePosition_FullBurn_NoTimePassed() public {
        uint256 slot = C.SLOT_2Y;
        uint256 totalDeposit = mockUsdc.balanceOf(USER_1);

        vm.startPrank(USER_1);
        uint256 newTokenId = treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);

        uint256 usdcEntryFeeAmount = (totalDeposit * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
        uint256 netUsdcAmountLessEntryFees = totalDeposit - usdcEntryFeeAmount;
        uint256 tokenBalance = treasuryBondToken.balanceOf(newTokenId); // 18 decimals

        //vm.warp(block.timestamp + 1);
        treasuryBondToken.closePosition(newTokenId);
        uint256 calculateExitFee = (netUsdcAmountLessEntryFees * C.PERCENTAGE_EXIT_FEE_MAX) / C.MAX_PERCENTAGE;
        uint256 expectedUsdcReturnedToUser = netUsdcAmountLessEntryFees - calculateExitFee;

        uint256 newUserUsdcBalance = mockUsdc.balanceOf(USER_1);
        uint256 totalFeesCollected = usdcEntryFeeAmount + calculateExitFee;
        assertEq(newUserUsdcBalance, expectedUsdcReturnedToUser, "USER_1 should receive the correct USDC amount after closing the position");
        assertEq(treasuryBondToken.totalSupply(), 0, "Total supply should be 0 after burning the token");
        assertEq(treasury.getTotalUsdcLiquidityPerSlot(slot), 0, "Total USDC liquidity for the slot should be 0 after closing the position");
        assertEq(treasuryBondToken.getTotalLiabilitiesPerSlot(slot), 0, "Total liabilities for the slot should be 0 after closing the position");

        assertEq(treasury.getTotalUsdcLiquidityPerSlot(slot), 0, "Total USDC liquidity for the slot should match the deposited amount minus fees");
        assertEq(treasury.getTotalFeesCollected(), totalFeesCollected, "Treasury should have collected the correct fee amount");
    }

    function test_ClosePosition_FullBurn_PenaltyPeriodElapsed() public {
        uint256 slot = C.SLOT_2Y;
        uint256 totalDeposit = mockUsdc.balanceOf(USER_1);

        vm.prank(USER_1);
        uint256 newTokenId = treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);

        uint256 usdcEntryFeeAmount = (totalDeposit * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
        uint256 netUsdcAmountLessEntryFees = totalDeposit - usdcEntryFeeAmount;
        uint256 tokenBalance = treasuryBondToken.balanceOf(newTokenId); // 18 decimals

        vm.startPrank(deployer);
        uint256 liquidityInjectionAmount = 100000*1e6;
        mockUsdc.approve(address(treasury), liquidityInjectionAmount);
        treasury.injectLiquidity(liquidityInjectionAmount, slot);
        vm.stopPrank();

        vm.warp(block.timestamp + C.PENALTY_PERIOD_2Y + 1);
        _refreshAllDataFeeds();

        uint256 claimableYield = treasuryBondToken.getClaimableYieldInUsdc(newTokenId);
        console2.log("Claimable yield:", claimableYield);
        vm.prank(USER_1);
        treasuryBondToken.closePosition(newTokenId);

        uint256 expectedUsdcReturnedToUser = netUsdcAmountLessEntryFees + claimableYield;
        uint256 expectedUsdcLiquidityRemainingOnTreasury = liquidityInjectionAmount - netUsdcAmountLessEntryFees - claimableYield  ;
        uint256 newUserUsdcBalance = mockUsdc.balanceOf(USER_1);

        assertEq(newUserUsdcBalance, expectedUsdcReturnedToUser, "USER_1 should receive the deposited amount minus entry fees plus interests, since penalty period has elapsed ");

        assertEq(treasuryBondToken.totalSupply(), 0, "Total supply should be 0 after burning the token");
        assertEq(treasuryBondToken.getTotalLiabilitiesPerSlot(slot), 0, "Total liabilities for the slot should be 0 after closing the position");

        //assertEq(treasury.getTotalUsdcLiquidityPerSlot(slot), expectedUsdcLiquidityRemainingOnTreasury, "Total USDC liquidity for the slot should match the deposited amount minus fees");
        assertGt(treasury.getTotalFeesCollected(), usdcEntryFeeAmount, "Treasury should have collected depositAmount plus some fees from the yield claim, so total fees collected should be greater than entry fee amount");
    }

    // function test_ClosePartialPosition_ProportionalPayout() public {

    // }

    // function test_ClaimYield_AfterLockPeriod_CorrectAmount() public {

    // }

    function test_OpenPosition_RevertsIfInsufficientReserves() public {
        uint256 slot = C.SLOT_10Y;
        ReservesResponse memory reserves = reservesOracle.getAllReserves();
        uint256 spvReservesForSlot = reserves.tenYearUsdBondsValue;
        uint256 spvCashBufferForSlot = reserves.tenYearUsdCashValue;
        uint256 spvTotalLiquidityForSlot = spvReservesForSlot + spvCashBufferForSlot;
        
        mockUsdc.mint(USER_1, spvTotalLiquidityForSlot); 
        uint256 totalDeposit = mockUsdc.balanceOf(USER_1);
        
        uint256 usdcEntryFeeAmount = (totalDeposit * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;

        // Second deposit should fail with insufficient reserves
        vm.prank(USER_1);
        vm.expectRevert();
        treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);
    
    }
    function test_UpdateYields_BrokenData_FreezesAnomalousSlot() public {
        vm.recordLogs();
        
        // Push broken yields data (30Y ×100 error) and trigger RiskManager validation
        _updateYieldsDataBroken();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool invalidYieldFound;
        bool slotFrozenFound;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(treasuryBondToken)) continue;

            if (logs[i].topics[0] == IRiskManager.InvalidYield.selector) {
                uint256 slot = uint256(logs[i].topics[1]);
                (uint256 yield) = abi.decode(logs[i].data, (uint256));
                if (slot == C.SLOT_30Y) {
                    assertEq(yield, yieldsDataBroken.thirtyYearYield, "InvalidYield: wrong yield value logged");
                    invalidYieldFound = true;
                }
            }

            if (logs[i].topics[0] == IRiskManager.SlotFrozen.selector) {
                uint256 slot = uint256(logs[i].topics[1]);
                if (slot == C.SLOT_30Y) {
                    slotFrozenFound = true;
                }
            }
        }

        assertTrue(invalidYieldFound, "InvalidYield event not emitted for SLOT_30Y");
        assertTrue(slotFrozenFound,   "SlotFrozen event not emitted for SLOT_30Y");
    }

    function test_UpdateReserves_BrokenData_FreezesAnomalousSlot() public {
        vm.recordLogs();
        
        // Push broken reserves data (10Y ×100 error) and trigger RiskManager validation
        _updateReservesDataBroken();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool excessiveReserveShockFound;
        bool slotFrozenFound;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(treasuryBondToken)) continue;

            if (logs[i].topics[0] == IRiskManager.ExcessiveReserveShock.selector) {
                uint256 slot = uint256(logs[i].topics[1]);
                if (slot == C.SLOT_10Y) {
                    (uint256 shock) = abi.decode(logs[i].data, (uint256));
                    assertGt(shock, 0, "ExcessiveReserveShock: shock value should be > 0");
                    excessiveReserveShockFound = true;
                }
            }

            if (logs[i].topics[0] == IRiskManager.SlotFrozen.selector) {
                uint256 slot = uint256(logs[i].topics[1]);
                if (slot == C.SLOT_10Y) {
                    slotFrozenFound = true;
                }
            }
        }

        assertTrue(excessiveReserveShockFound, "ExcessiveReserveShock event not emitted for SLOT_10Y");
        assertTrue(slotFrozenFound,            "SlotFrozen event not emitted for SLOT_10Y");
    }

    // function test_ClosePosition_EarlyRedeemFee_Applied() public {

    // }

    function test_OpenPosition_RevertsIfSlotFrozen() public {
        // Push broken reserves data that freezes the 10Y slot
        _updateReservesDataBroken();

        uint256 slot = C.SLOT_10Y;
        uint256 totalDeposit = 1000 * 1e6; // 1000 USDC
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(IRiskManager.RiskManager__SlotFrozen.selector, slot));
        treasuryBondToken.openNewPosition(USER_1, slot, totalDeposit);
    }

    // function test_Solvency_AfterMultipleMints_Holds() public {

    // }
}