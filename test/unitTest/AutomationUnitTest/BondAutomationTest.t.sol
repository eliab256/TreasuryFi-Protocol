// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.t.sol";
import {BondAutomation} from "../../../src/automation/BondAutomation.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @title BondAutomationTest
 * @notice Unit tests for BondAutomation + BaseAutomation (full branch coverage).
 */
contract BondAutomationTest is BaseTest {
    BondAutomation internal bondAutomation;
    error BondAutomation__ZeroAddress();

    function setUp() public override {
        super.setUp();
        bondAutomation = new BondAutomation(
            address(mockBondConsumer),
            ADMIN
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsInterval() public view {
        assertEq(bondAutomation.getInterval(), INTERVAL);
    }

    function test_Constructor_SetsFunctionsConsumer() public view {
        assertEq(bondAutomation.getFunctionsConsumer(), address(mockBondConsumer));
    }

    function test_Constructor_InitialisesLastUpkeepToZero() public view {
        assertEq(bondAutomation.getLastUpkeep(), 0);
    }

    function test_Constructor_GrantsDefaultAdminRoleToAdmin() public view {
        assertTrue(bondAutomation.hasRole(DEFAULT_ADMIN_ROLE, ADMIN));
    }

    function test_Constructor_GrantsAutomationAdminRoleToAdmin() public view {
        assertTrue(bondAutomation.hasRole(AUTOMATION_ADMIN_ROLE, ADMIN));
    }

    function test_Constructor_RevertsWhenFunctionsConsumerIsZeroAddress() public {
        vm.expectRevert(BondAutomation__ZeroAddress.selector);
        new BondAutomation(address(0), ADMIN);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setChainlinkForwarder
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetChainlinkForwarder_StoresAddress() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        assertEq(bondAutomation.getChainlinkForwarder(), CHAINLINK_FORWARDER);
    }

    function test_SetChainlinkForwarder_RevertsWhenCalledTwice() public {
        vm.startPrank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        vm.expectRevert(BaseAutomation__ChainlinkForwarderAddressAlreadySet.selector);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        vm.stopPrank();
    }

    function test_SetChainlinkForwarder_RevertsWhenCallerLacksAdminRole() public {
        vm.prank(NON_ADMIN);
        vm.expectRevert();
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setUpkeepId
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetUpkeepId_StoresId() public {
        vm.prank(ADMIN);
        bondAutomation.setUpkeepId(UPKEEP_ID);
        assertEq(bondAutomation.getUpkeepId(), UPKEEP_ID);
    }

    function test_SetUpkeepId_RevertsWhenCalledTwice() public {
        vm.startPrank(ADMIN);
        bondAutomation.setUpkeepId(UPKEEP_ID);
        vm.expectRevert(BaseAutomation__ChainlinkUpkeepIdAlreadySet.selector);
        bondAutomation.setUpkeepId(UPKEEP_ID);
        vm.stopPrank();
    }

    function test_SetUpkeepId_RevertsWhenCallerLacksAdminRole() public {
        vm.prank(NON_ADMIN);
        vm.expectRevert();
        bondAutomation.setUpkeepId(UPKEEP_ID);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // checkUpkeep
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CheckUpkeep_ReturnsFalseBeforeIntervalElapses() public view {
        // block.timestamp starts at 1 in Foundry; 1 < INTERVAL → not needed
        (bool upkeepNeeded, bytes memory data) = bondAutomation.checkUpkeep("");
        assertFalse(upkeepNeeded);
        assertEq(data, "");
    }

    function test_CheckUpkeep_ReturnsTrueAfterIntervalElapses() public {
        _warpInsideGracePeriod(0); // lastUpkeep == 0 initially
        (bool upkeepNeeded, ) = bondAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function test_CheckUpkeep_ReturnsTrueExactlyAtIntervalBoundary() public {
        vm.warp(INTERVAL); // block.timestamp == 0 + INTERVAL → upkeepNeeded
        (bool upkeepNeeded, ) = bondAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // performUpkeep – common guard
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PerformUpkeep_RevertsWhenUpkeepNotNeeded() public {
        vm.expectRevert(BaseAutomation__UpkeepNotNeeded.selector);
        bondAutomation.performUpkeep("");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // performUpkeep – WITHIN grace period
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PerformUpkeep_WithinGrace_ForwarderSucceeds() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpInsideGracePeriod(0);
        uint256 expectedTimestamp = block.timestamp;

        vm.prank(CHAINLINK_FORWARDER);
        bondAutomation.performUpkeep("");

        // State assertions
        assertEq(bondAutomation.getLastUpkeep(), expectedTimestamp);
        // _triggerRequest was called → sendRequest forwarded to mock
        assertEq(mockBondConsumer.sendRequestCallCount(), 1);
    }

    function test_PerformUpkeep_WithinGrace_RevertsForRandomCaller() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpInsideGracePeriod(0);

        vm.prank(NON_ADMIN);
        vm.expectRevert(BaseAutomation__OnlyChainlinkAutomation.selector);
        bondAutomation.performUpkeep("");
    }

    function test_PerformUpkeep_WithinGrace_RevertsForAdmin() public {
        // Even the admin must wait for grace period to expire
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpInsideGracePeriod(0);

        vm.prank(ADMIN);
        vm.expectRevert(BaseAutomation__OnlyChainlinkAutomation.selector);
        bondAutomation.performUpkeep("");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // performUpkeep – AFTER grace period
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PerformUpkeep_AfterGrace_AdminSucceedsAndEmitsEvent() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpPastGracePeriod(0);
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, false, false);
        emit ManualUpkeepExecuted(ADMIN, expectedTimestamp);

        vm.prank(ADMIN);
        bondAutomation.performUpkeep("");

        assertEq(bondAutomation.getLastUpkeep(), expectedTimestamp);
        assertEq(mockBondConsumer.sendRequestCallCount(), 1);
    }

    function test_PerformUpkeep_AfterGrace_ForwarderSucceedsAndDoesNotEmitManualEvent() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpPastGracePeriod(0);
        uint256 expectedTimestamp = block.timestamp;

        // The forwarder is NOT a manual caller, so ManualUpkeepExecuted must NOT be emitted
        vm.recordLogs();
        vm.prank(CHAINLINK_FORWARDER);
        bondAutomation.performUpkeep("");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 manualEventSig = keccak256("ManualUpkeepExecuted(address,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], manualEventSig);
        }

        assertEq(bondAutomation.getLastUpkeep(), expectedTimestamp);
    }

    function test_PerformUpkeep_AfterGrace_RevertsForRandomCaller() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpPastGracePeriod(0);

        vm.prank(NON_ADMIN);
        vm.expectRevert(BaseAutomation__OnlyChainlinkAutomationOrOwner.selector);
        bondAutomation.performUpkeep("");
    }

    function test_PerformUpkeep_AfterGrace_AdminCanExecuteWithoutForwarderSet() public {
        // Forwarder intentionally NOT set: after grace period admin must still succeed
        _warpPastGracePeriod(0);
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, false, false);
        emit ManualUpkeepExecuted(ADMIN, expectedTimestamp);

        vm.prank(ADMIN);
        bondAutomation.performUpkeep("");

        assertEq(bondAutomation.getLastUpkeep(), expectedTimestamp);
        assertEq(mockBondConsumer.sendRequestCallCount(), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // performUpkeep – state persistence across multiple rounds
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PerformUpkeep_UpdatesLastUpkeepAfterEachRound() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        // Round 1
        _warpInsideGracePeriod(0);
        uint256 t1 = block.timestamp;
        vm.prank(CHAINLINK_FORWARDER);
        bondAutomation.performUpkeep("");
        assertEq(bondAutomation.getLastUpkeep(), t1);

        // Round 2 – must warp relative to t1 now
        _warpInsideGracePeriod(t1);
        uint256 t2 = block.timestamp;
        vm.prank(CHAINLINK_FORWARDER);
        bondAutomation.performUpkeep("");
        assertEq(bondAutomation.getLastUpkeep(), t2);

        assertEq(mockBondConsumer.sendRequestCallCount(), 2);
    }

    function test_PerformUpkeep_NotNeededRightAfterExecution() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpInsideGracePeriod(0);
        vm.prank(CHAINLINK_FORWARDER);
        bondAutomation.performUpkeep("");

        // Immediately after execution upkeep should not be needed
        (bool upkeepNeeded, ) = bondAutomation.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Getters
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetGracePeriod_ReturnsExpectedConstant() public view {
        assertEq(bondAutomation.getGracePeriod(), GRACE_PERIOD);
    }

    function test_GetChainlinkForwarder_IsZeroAddressInitially() public view {
        assertEq(bondAutomation.getChainlinkForwarder(), address(0));
    }

    function test_GetUpkeepId_IsZeroInitially() public view {
        assertEq(bondAutomation.getUpkeepId(), 0);
    }

    function test_GetAllUpkeepInfo_ReturnsCorrectTuple() public view {
        (uint256 interval, uint256 gracePeriod, uint256 lastUpkeep) =
            bondAutomation.getAllUpkeepInfo();
        assertEq(interval,     INTERVAL);
        assertEq(gracePeriod,  GRACE_PERIOD);
        assertEq(lastUpkeep,   0);
    }

    function test_GetAllUpkeepInfo_ReflectsLastUpkeepAfterExecution() public {
        vm.prank(ADMIN);
        bondAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpInsideGracePeriod(0);
        uint256 expectedTs = block.timestamp;

        vm.prank(CHAINLINK_FORWARDER);
        bondAutomation.performUpkeep("");

        (, , uint256 lastUpkeep) = bondAutomation.getAllUpkeepInfo();
        assertEq(lastUpkeep, expectedTs);
    }
}
