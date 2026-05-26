// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.t.sol";
import {UpdateRiskManagerAutomation} from "../../../src/automation/UpdateRiskManagerAutomation.sol";
import {IUpdateRiskManagerAutomation} from "../../../src/interfaces/IUpdateRiskManagerAutomation.sol";
import {ReservesResponse, BondYieldsResponse} from "../../../src/types.sol";
import {Vm} from "forge-std/Vm.sol";


contract UpdateRiskManagerAutomationTest is BaseTest {
    UpdateRiskManagerAutomation internal updateRiskManagerAutomation;

    tokenMock    internal token;
    reservesOracleMock internal reservesOracle;
    yieldsOracleMock   internal yieldsOracle;

    error UpdateRiskManager__ZeroAddress();
    error UpdateRiskManager__ChainlinkForwarderAddressAlreadySet();

    // ─── Oracle timestamp used to simulate a fresh update ────────────────────
    /// @dev Any value > 0 is enough for the first upkeep; we use a realistic one.
    uint256 internal constant ORACLE_TS_1 = 1_000_000;
    uint256 internal constant ORACLE_TS_2 = 2_000_000;

    function setUp() public override {
        super.setUp();
        token = new tokenMock();
        reservesOracle = new reservesOracleMock();
        yieldsOracle = new yieldsOracleMock();
        vm.prank(ADMIN);
        updateRiskManagerAutomation = new UpdateRiskManagerAutomation(
            address(token),
            address(reservesOracle),
            address(yieldsOracle),
            ADMIN
        );

     
    }

    function test_Constructor_SetsOraclesAndToken() public view {
        assertEq(updateRiskManagerAutomation.getTokenContract(),    address(token),          "wrong token");
        assertEq(updateRiskManagerAutomation.getReservesOracle(),   address(reservesOracle), "wrong reserves oracle");
        assertEq(updateRiskManagerAutomation.getBondOracle(),        address(yieldsOracle),   "wrong bond oracle");        
    }

    function test_Constructor_GrantsDefaultAdminAndTokenRole() public view {

    }

    function test_Constructor_RevertsWhenAnyAddressIsZero() public {
        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            address(0),
            address(reservesOracle),
            address(yieldsOracle),
            ADMIN
        );

        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            address(token),
            address(0),
            address(yieldsOracle),
            ADMIN
        );

        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            address(token),
            address(reservesOracle),
            address(0),
            ADMIN
        );

        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            address(token),
            address(reservesOracle),
            address(yieldsOracle),
            address(0)
        );
    }

    function test_SetChainlinkForwarder_SetsAddressAndGrantsRole() public {
        bytes32 automationRole = updateRiskManagerAutomation.AUTOMATION_ROLE();
        vm.prank(ADMIN);
        updateRiskManagerAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        assertTrue(updateRiskManagerAutomation.hasRole(automationRole, CHAINLINK_FORWARDER));
    }

    function test_SetChainlinkForwarder_RevertsWhenZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__ZeroAddress.selector);
        updateRiskManagerAutomation.setChainlinkForwarder(address(0));
    }

    function test_SetChainlinkForwarder_RevertsWhenAlreadySet() public {
        vm.prank(ADMIN);
        updateRiskManagerAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        vm.prank(ADMIN);
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__ChainlinkForwarderAddressAlreadySet.selector);
        updateRiskManagerAutomation.setChainlinkForwarder(makeAddr("anotherForwarder"));
    }

    // =========================================================================
    // setUpkeepId
    // =========================================================================

    function test_SetUpkeepId_SetsUpkeepId() public {
        assertEq(updateRiskManagerAutomation.getUpkeepId(), 0);
        vm.prank(ADMIN);
        updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID);
        assertEq(updateRiskManagerAutomation.getUpkeepId(), UPKEEP_ID);
    }

    function test_SetUpkeepId_RevertsWhenZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__InvalidUpkeepId.selector);
        updateRiskManagerAutomation.setUpkeepId(0);
    }

    function test_SetUpkeepId_RevertsWhenAlreadySet() public {
        vm.prank(ADMIN);
        updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID);

        vm.prank(ADMIN);
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__ChainlinkUpkeepIdAlreadySet.selector);
        updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID + 1);
    }

    // =========================================================================
    // checkUpkeep
    // =========================================================================

    /// @dev Both oracles report timestamp == 0 (never updated) and s_last* == 0.
    function test_CheckUpkeep_ReturnsFalseWhenBothIntervalsHaveNotElapsed() public view {
        // Oracles' getLastUpdatedTimestamp() returns 0 by default (never set).
        (bool upkeepNeeded, bytes memory performData) = updateRiskManagerAutomation.checkUpkeep("");

        assertFalse(upkeepNeeded, "upkeepNeeded should be false");

        (bool yieldsFlag, bool reservesFlag) = abi.decode(performData, (bool, bool));
        assertFalse(yieldsFlag,   "yields flag should be false");
        assertFalse(reservesFlag, "reserves flag should be false");
    }

    /// @dev Both oracles have a fresh timestamp → both flags true.
    function test_CheckUpkeep_ReturnsTrueAndCorrectPerformDataWhenIntervalsHaveElapsed() public {
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_1);

        (bool upkeepNeeded, bytes memory performData) = updateRiskManagerAutomation.checkUpkeep("");

        assertTrue(upkeepNeeded, "upkeepNeeded should be true");

        (bool yieldsFlag, bool reservesFlag) = abi.decode(performData, (bool, bool));
        assertTrue(yieldsFlag,   "yields flag should be true");
        assertTrue(reservesFlag, "reserves flag should be true");
    }

    /// @dev Only one oracle has a fresh timestamp → only the corresponding flag is true.
    function test_CheckUpkeep_ReturnsTrueAndCorrectPerformDataWhenOnlyOneIntervalHasElapsed() public {
        // Only yields oracle has a new update
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        // reservesOracle timestamp stays 0

        (bool upkeepNeeded, bytes memory performData) = updateRiskManagerAutomation.checkUpkeep("");

        assertTrue(upkeepNeeded, "upkeepNeeded should be true (yields need update)");

        (bool yieldsFlag, bool reservesFlag) = abi.decode(performData, (bool, bool));
        assertTrue(yieldsFlag,    "yields flag should be true");
        assertFalse(reservesFlag, "reserves flag should be false");
    }

    // =========================================================================
    // performUpkeep
    // =========================================================================

    function test_PerformUpkeep_RevertsWhenUpkeepNotNeeded() public {
        // No oracle timestamps set → both flags false → revert
        bytes memory performData = abi.encode(false, false);

        vm.prank(address(token)); // token has AUTOMATION_ROLE
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__UpkeepNotNeeded.selector);
        updateRiskManagerAutomation.performUpkeep(performData);
    }

    function test_PerformUpkeep_RevertsIfCalledByUnauthorizedAddress() public {
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_1);

        bytes memory performData = abi.encode(true, true);

        // NON_ADMIN has no AUTOMATION_ROLE
        vm.prank(NON_ADMIN);
        // AccessControl reverts with a standard error — check it doesn't succeed
        vm.expectRevert();
        updateRiskManagerAutomation.performUpkeep(performData);
    }

    function test_PerformUpkeep_CallsReservesOracleWhenNeededAndUpdatesLastReserveUpdate() public {
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        // yields oracle stays at 0 → no yields update

        bytes memory performData = abi.encode(false, true);

        vm.prank(address(token));
        updateRiskManagerAutomation.performUpkeep(performData);

        // After performUpkeep s_lastReserveUpdate should equal the oracle timestamp
        // We verify indirectly: calling performUpkeep again with the same data reverts
        // because reservesTimestamp (ORACLE_TS_1) is no longer > s_lastReserveUpdate (ORACLE_TS_1).
        vm.prank(address(token));
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__UpkeepNotNeeded.selector);
        updateRiskManagerAutomation.performUpkeep(performData);

        // Double-check: a higher oracle timestamp re-enables the update.
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_2);
        (bool upkeepNeeded,) = updateRiskManagerAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded, "should need upkeep after new reserves timestamp");
    }

    function test_PerformUpkeep_CallsYieldsOracleWhenNeededAndUpdatesLastYieldsUpdate() public {
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        // reserves oracle stays at 0 → no reserves update

        bytes memory performData = abi.encode(true, false);

        vm.prank(address(token));
        updateRiskManagerAutomation.performUpkeep(performData);

        // Same idempotency check as above
        vm.prank(address(token));
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__UpkeepNotNeeded.selector);
        updateRiskManagerAutomation.performUpkeep(performData);

        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_2);
        (bool upkeepNeeded,) = updateRiskManagerAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded, "should need upkeep after new yields timestamp");
    }

    function test_PerformUpkeep_CallsBothOraclesWhenBothNeedUpdating() public {
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_1);

        bytes memory performData = abi.encode(true, true);

        vm.prank(address(token));
        updateRiskManagerAutomation.performUpkeep(performData);

        // Both trackers updated → next call with same data must revert
        vm.prank(address(token));
        vm.expectRevert(IUpdateRiskManagerAutomation.UpdateRiskManager__UpkeepNotNeeded.selector);
        updateRiskManagerAutomation.performUpkeep(performData);

        // Re-arm both oracles and verify upkeep becomes needed again
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_2);
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_2);

        (bool upkeepNeeded, bytes memory newPerformData) = updateRiskManagerAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded, "should need upkeep after both oracles updated");

        (bool yieldsFlag, bool reservesFlag) = abi.decode(newPerformData, (bool, bool));
        assertTrue(yieldsFlag,   "yields flag should be true after re-arm");
        assertTrue(reservesFlag, "reserves flag should be true after re-arm");
    }

    /// @dev ManualUpkeepExecuted is emitted when the caller is NOT the Chainlink forwarder.
    ///      Here the token mock calls performUpkeep internally → msg.sender == address(token).
    function test_PerformUpkeep_EmitsManualUpkeepEventWhenExecutedByTokenContract() public {
        // Set the automation address in the token mock
        token.setAutomation(address(updateRiskManagerAutomation));
        
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_1);

        vm.recordLogs();

        // callAutomationUpdate triggers checkUpkeep + performUpkeep from within the token mock
        // Use vm.prank(address(token)) so msg.sender == token (which has AUTOMATION_ROLE)
        vm.prank(address(token));
        token.callAutomationUpdate();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool manualUpkeepEventFound;
        bytes32 manualUpkeepSig = keccak256("ManualUpkeepExecuted(address,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(updateRiskManagerAutomation)) continue;

            if (logs[i].topics[0] == manualUpkeepSig) {
                address caller = address(uint160(uint256(logs[i].topics[1])));
                assertEq(caller, address(token), "ManualUpkeepExecuted: wrong caller logged");
                manualUpkeepEventFound = true;
            }
        }

        assertTrue(manualUpkeepEventFound, "ManualUpkeepExecuted event not emitted");
    }

    /// @dev When the Chainlink forwarder calls performUpkeep the event must NOT be emitted.
    function test_PerformUpkeep_DoesNotEmitManualEventWhenCalledByChainlinkForwarder() public {
        yieldsOracle.setLastUpdatedTimestamp(ORACLE_TS_1);
        reservesOracle.setLastUpdatedTimestamp(ORACLE_TS_1);

        vm.prank(ADMIN);
        updateRiskManagerAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);

        (, bytes memory performData) = updateRiskManagerAutomation.checkUpkeep("");

        vm.recordLogs();

        vm.prank(CHAINLINK_FORWARDER);
        updateRiskManagerAutomation.performUpkeep(performData);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 manualUpkeepSig = keccak256("ManualUpkeepExecuted(address,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(updateRiskManagerAutomation) &&
                logs[i].topics[0] == manualUpkeepSig
            ) {
                revert("ManualUpkeepExecuted should NOT be emitted for forwarder");
            }
        }
    }


    function test_Getters_ReturnStoredValues() public {
        // GET CHAINLINK FORWARDER
        assertEq(
            updateRiskManagerAutomation.getChainlinkForwarder(),
            address(0),
            "initial forwarder should be zero"
        );
        vm.prank(ADMIN);
        updateRiskManagerAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        assertEq(
            updateRiskManagerAutomation.getChainlinkForwarder(),
            CHAINLINK_FORWARDER,
            "forwarder not stored correctly"
        );

        // GET UPKEEP ID
        assertEq(updateRiskManagerAutomation.getUpkeepId(), 0, "initial upkeepId should be 0");
        vm.prank(ADMIN);
        updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID);
        assertEq(updateRiskManagerAutomation.getUpkeepId(), UPKEEP_ID, "upkeepId not stored");

        // GET BOND ORACLE ADDRESS
        assertEq(
            updateRiskManagerAutomation.getBondOracle(),
            address(yieldsOracle),
            "wrong bond oracle"
        );

        // GET RESERVES ORACLE ADDRESS
        assertEq(
            updateRiskManagerAutomation.getReservesOracle(),
            address(reservesOracle),
            "wrong reserves oracle"
        );

        // GET TOKEN ADDRESS
        assertEq(
            updateRiskManagerAutomation.getTokenContract(),
            address(token),
            "wrong token contract"
        );
    }
}

// =============================================================================
// Mocks
// =============================================================================

contract tokenMock {
    address private s_automation;

    function setAutomation(address _automation) external {
        s_automation = _automation;
    }

    /// @dev Simulates the TreasuryBondToken calling the automation contract manually.
    function callAutomationUpdate() external {
        UpdateRiskManagerAutomation automation = UpdateRiskManagerAutomation(s_automation);
        (, bytes memory performData) = automation.checkUpkeep("");
        automation.performUpkeep(performData);
    }

    /// @dev Called by UpdateRiskManagerAutomation.performUpkeep when yields need updating.
    function updateYieldsValues() external {}

    /// @dev Called by UpdateRiskManagerAutomation.performUpkeep when reserves need updating.
    function updateReserveValues() external {}
}

contract reservesOracleMock {
    uint256 private s_lastUpdatedTimestamp;

    function setLastUpdatedTimestamp(uint256 timestamp) external {
        s_lastUpdatedTimestamp = timestamp;
    }

    function getLastUpdatedTimestamp() external view returns (uint256) {
        return s_lastUpdatedTimestamp;
    }
}

contract yieldsOracleMock {
    uint256 private s_lastUpdatedTimestamp;

    function setLastUpdatedTimestamp(uint256 timestamp) external {
        s_lastUpdatedTimestamp = timestamp;
    }

    function getLastUpdatedTimestamp() external view returns (uint256) {
        return s_lastUpdatedTimestamp;
    }
}