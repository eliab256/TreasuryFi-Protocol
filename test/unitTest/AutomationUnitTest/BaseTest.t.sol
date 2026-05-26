// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockBondFunctionsConsumer} from "../../mocks/MockBondFunctionsConsumer.sol";
import {MockReservesFunctionsConsumer} from "../../mocks/MockReservesFunctionsConsumer.sol";


abstract contract BaseTest is Test {

    address internal ADMIN   = makeAddr("admin");
    address internal NON_ADMIN  = makeAddr("nonAdmin");
    address internal CHAINLINK_FORWARDER = makeAddr("chainlinkForwarder");

    // ─── Protocol constants (must mirror the production values) ───────────────
    uint256 internal constant INTERVAL     = 1 days;   // passed to constructors
    uint256 internal constant GRACE_PERIOD = 6 hours;  // hard-coded in BaseAutomation
    uint256 internal constant UPKEEP_ID   = 42;

    // ─── Mocks ────────────────────────────────────────────────────────────────
    MockBondFunctionsConsumer    internal mockBondConsumer;
    MockReservesFunctionsConsumer internal mockReservesConsumer;

    function setUp() public virtual {
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
