// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.t.sol";
import {ReservesAutomation} from "../../../src/automation/ReservesAutomation.sol";

/**
 * @title ReservesAutomationTest
 * @notice Unit tests covering ReservesAutomation-specific code.
 */
contract ReservesAutomationTest is BaseTest {
    ReservesAutomation internal reservesAutomation;

    bytes32 internal DEFAULT_ADMIN_ROLE;
    bytes32 internal AUTOMATION_ROLE;

    error ReservesAutomation__ZeroAddress();

    function setUp() public override {
        super.setUp();
        reservesAutomation = new ReservesAutomation(
            address(mockReservesConsumer),
            ADMIN
        );

        DEFAULT_ADMIN_ROLE = reservesAutomation.DEFAULT_ADMIN_ROLE();
        AUTOMATION_ROLE = reservesAutomation.AUTOMATION_ROLE();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsInterval() public view {
        assertEq(reservesAutomation.getInterval(), INTERVAL);
    }

    function test_Constructor_SetsFunctionsConsumer() public view {
        assertEq(
            reservesAutomation.getFunctionsConsumer(),
            address(mockReservesConsumer)
        );
    }

    function test_Constructor_InitialisesLastUpkeepToZero() public view {
        assertEq(reservesAutomation.getLastUpkeep(), 0);
    }

    function test_Constructor_GrantsDefaultAdminRoleToAdmin() public view {
        assertTrue(reservesAutomation.hasRole(DEFAULT_ADMIN_ROLE, ADMIN));
    }

    function test_Constructor_GrantsAutomationRoleToAdmin() public view {
        assertTrue(reservesAutomation.hasRole(AUTOMATION_ROLE, ADMIN));
    }

    function test_Constructor_RevertsWhenFunctionsConsumerIsZeroAddress() public {
        vm.expectRevert(ReservesAutomation__ZeroAddress.selector);
        new ReservesAutomation(address(0), ADMIN);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getFunctionsConsumer
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetFunctionsConsumer_ReturnsStoredAddress() public view {
        assertEq(
            reservesAutomation.getFunctionsConsumer(),
            address(mockReservesConsumer)
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // _triggerRequest (reached via performUpkeep)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TriggerRequest_CallsSendRequestOnReservesConsumer() public {
        vm.prank(ADMIN);
        reservesAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        _warpInsideGracePeriod(0);

        vm.prank(CHAINLINK_FORWARDER);
        reservesAutomation.performUpkeep("");

        assertEq(mockReservesConsumer.sendRequestCallCount(), 1);
    }

    function test_TriggerRequest_IsCalledEachSuccessfulUpkeep() public {
        vm.prank(ADMIN);
        reservesAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        // Round 1
        _warpInsideGracePeriod(0);
        vm.prank(CHAINLINK_FORWARDER);
        reservesAutomation.performUpkeep("");

        uint256 lastUpkeep = reservesAutomation.getLastUpkeep();

        // Round 2
        _warpInsideGracePeriod(lastUpkeep);
        vm.prank(CHAINLINK_FORWARDER);
        reservesAutomation.performUpkeep("");

        assertEq(mockReservesConsumer.sendRequestCallCount(), 2);
    }
}
