//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IBaseAutomation} from "../interfaces/IBaseAutomation.sol";

/**
 * @title BaseAutomation
 * @notice Abstract base contract for Chainlink Automation with grace period logic.
 * Implements the common upkeep check and perform logic for all automation contracts.
 */
abstract contract BaseAutomation is IBaseAutomation, AccessControl {
    bytes32 public constant AUTOMATION_ADMIN_ROLE =
        keccak256("AUTOMATION_ADMIN_ROLE");

    uint256 internal constant GRACE_PERIOD = 6 hours;

    address private s_chainlinkForwarder;
    uint256 private s_upkeepId;
    uint256 internal s_interval;
    uint256 internal s_lastUpkeep;

    constructor(address initialAdmin, uint256 _interval) {
        s_interval = _interval;
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(AUTOMATION_ADMIN_ROLE, initialAdmin);
    }

    /**
     * @notice Sets the Chainlink Automation forwarder address
     * @dev Can only be set once by an admin
     */
    function setChainlinkForwarder(
        address _chainlinkForwarder
    ) external onlyRole(AUTOMATION_ADMIN_ROLE) {
        if (s_chainlinkForwarder != address(0)) {
            revert BaseAutomation__ChainlinkForwarderAddressAlreadySet();
        }
        s_chainlinkForwarder = _chainlinkForwarder;
    }

    /**
     * @notice Sets the upkeep ID
     * @dev Can only be set once by an admin
     */
    function setUpkeepId(
        uint256 _upkeepId
    ) external onlyRole(AUTOMATION_ADMIN_ROLE) {
        if (s_upkeepId != 0) {
            revert BaseAutomation__ChainlinkUpkeepIdAlreadySet();
        }
        s_upkeepId = _upkeepId;
    }

    /**
     * @notice Checks if upkeep is needed based on the interval
     */
    function checkUpkeep(
        bytes calldata
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = block.timestamp >= (s_lastUpkeep + s_interval);
        return (upkeepNeeded, "");
    }

    /**
     * @notice Performs the upkeep with grace period logic
     * - During grace period: only Chainlink Automation can call
     * - After grace period: owner or Chainlink Automation can call
     */
    function performUpkeep(bytes calldata performData) external override {
        (bool upkeepNeeded, ) = checkUpkeep(performData);
        if (!upkeepNeeded) {
            revert BaseAutomation__UpkeepNotNeeded();
        }

        bool withinGracePeriod = block.timestamp <
            (s_lastUpkeep + GRACE_PERIOD + s_interval);

        if (withinGracePeriod) {
            // During grace period: only Chainlink Automation can call
            if (msg.sender != address(s_chainlinkForwarder)) {
                revert BaseAutomation__OnlyChainlinkAutomation();
            }
        } else {
            // After grace period: only Chainlink Automation or admin can call
            if (
                msg.sender != address(s_chainlinkForwarder) &&
                !hasRole(AUTOMATION_ADMIN_ROLE, msg.sender)
            ) {
                revert BaseAutomation__OnlyChainlinkAutomationOrOwner();
            }
            emit ManualUpkeepExecuted(msg.sender, block.timestamp);
        }

        s_lastUpkeep = block.timestamp;
        _triggerRequest();
    }

    /**
     * @notice Internal hook to trigger the oracle request
     * @dev Must be implemented by subclasses
     */
    function _triggerRequest() internal virtual;

    // --- Getters ---
    function getChainlinkForwarder() external view returns (address) {
        return s_chainlinkForwarder;
    }

    function getUpkeepId() external view returns (uint256) {
        return s_upkeepId;
    }

    function getInterval() external view returns (uint256) {
        return s_interval;
    }

    function getLastUpkeep() external view returns (uint256) {
        return s_lastUpkeep;
    }
}
