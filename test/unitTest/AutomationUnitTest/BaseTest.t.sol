// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockBondFunctionsConsumer} from "../../mocks/MockBondFunctionsConsumer.sol";
import {MockReservesFunctionsConsumer} from "../../mocks/MockReservesFunctionsConsumer.sol";


abstract contract BaseTest is Test {
    // ─── Roles ────────────────────────────────────────────────────────────────
    bytes32 internal constant DEFAULT_ADMIN_ROLE  = bytes32(0);
    bytes32 internal constant AUTOMATION_ADMIN_ROLE = keccak256("AUTOMATION_ADMIN_ROLE");

    // ─── Accounts (set in setUp to avoid constant address collisions) ─────────
    address internal ADMIN;
    address internal NON_ADMIN;
    address internal CHAINLINK_FORWARDER;

    // ─── Protocol constants (must mirror the production values) ───────────────
    uint256 internal constant INTERVAL     = 1 days;   // passed to constructors
    uint256 internal constant GRACE_PERIOD = 6 hours;  // hard-coded in BaseAutomation
    uint256 internal constant UPKEEP_ID   = 42;

    // ─── Mocks ────────────────────────────────────────────────────────────────
    MockBondFunctionsConsumer    internal mockBondConsumer;
    MockReservesFunctionsConsumer internal mockReservesConsumer;

    // ─── Events (mirrors of IBaseAutomation – needed for vm.expectEmit) ──────
    event ManualUpkeepExecuted(address indexed caller, uint256 indexed timestamp);

    // ─── BaseAutomation custom errors (mirror of IBaseAutomation) ────────────
    error BaseAutomation__ChainlinkForwarderAddressAlreadySet();
    error BaseAutomation__ChainlinkUpkeepIdAlreadySet();
    error BaseAutomation__UpkeepNotNeeded();
    error BaseAutomation__OnlyChainlinkAutomation();
    error BaseAutomation__OnlyChainlinkAutomationOrOwner();

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public virtual {
        ADMIN              = makeAddr("admin");
        NON_ADMIN          = makeAddr("nonAdmin");
        CHAINLINK_FORWARDER = makeAddr("chainlinkForwarder");

        mockBondConsumer    = new MockBondFunctionsConsumer();
        mockReservesConsumer = new MockReservesFunctionsConsumer();
    }

    // ─── Time-travel helpers ──────────────────────────────────────────────────

    /**
     * @dev Warps block.timestamp to just past the interval starting from
     *      `lastUpkeepTimestamp`. This puts us inside the grace window.
     */
    function _warpInsideGracePeriod(uint256 lastUpkeepTimestamp) internal {
        vm.warp(lastUpkeepTimestamp + INTERVAL + 1);
    }

    /**
     * @dev Warps block.timestamp to exactly past the grace period, making
     *      manual (admin) upkeep execution permissible.
     */
    function _warpPastGracePeriod(uint256 lastUpkeepTimestamp) internal {
        vm.warp(lastUpkeepTimestamp + INTERVAL + GRACE_PERIOD + 1);
    }

}
