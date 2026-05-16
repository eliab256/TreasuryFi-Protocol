//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IBaseAutomation} from "../interfaces/IBaseAutomation.sol";

/**
 * @title BaseAutomation
 * @notice Abstract base contract for Chainlink Automation with grace period logic.
 * Implements the common upkeep check and perform logic for all automation contracts.
 */
abstract contract BaseAutomation is IBaseAutomation, AccessControl {
    bytes32 public constant AUTOMATION_ROLE =
        keccak256("AUTOMATION_ROLE");

    uint256 internal constant GRACE_PERIOD = 6 hours;
    uint256 internal constant INTERVAL = 24 hours;

    address private s_chainlinkForwarder;
    uint256 private s_upkeepId;
   
    uint256 internal s_lastUpkeep;

    constructor(address initialAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(AUTOMATION_ROLE, initialAdmin);
    }

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function setChainlinkForwarder(
        address _chainlinkForwarder
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_chainlinkForwarder == address(0)) revert BaseAutomation__InvalidForwarderAddress();

        if (s_chainlinkForwarder != address(0)) {
            revert BaseAutomation__ChainlinkForwarderAddressAlreadySet();
        }
        s_chainlinkForwarder = _chainlinkForwarder;
    }

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function setUpkeepId(
        uint256 _upkeepId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_upkeepId == 0) revert BaseAutomation__InvalidUpkeepId();

        if (s_upkeepId != 0) {
            revert BaseAutomation__ChainlinkUpkeepIdAlreadySet();
        }
        s_upkeepId = _upkeepId;
    }

    /**
     * @notice Checks if upkeep is needed based on the interval and last upkeep time
     * @dev Inherited from IBaseAutomation. See interface for details.
     */ 
    function checkUpkeep(
        bytes calldata
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = block.timestamp >= (s_lastUpkeep + INTERVAL);
        return (upkeepNeeded, "");
    }

    /**
     * @notice Performs the upkeep with grace period logic
     * @dev Inherited from IBaseAutomation. See interface for details.
     * - During grace period: only Chainlink Automation can call
     * - After grace period: owner or Chainlink Automation can call
     */
    function performUpkeep(bytes calldata performData) external override onlyRole(AUTOMATION_ROLE) {
        (bool upkeepNeeded, ) = checkUpkeep(performData);
        if (!upkeepNeeded) {
            revert BaseAutomation__UpkeepNotNeeded();
        }

        bool withinGracePeriod = block.timestamp <
            (s_lastUpkeep + GRACE_PERIOD + INTERVAL);

        if (withinGracePeriod) {
            // During grace period: only Chainlink Automation can call
            if (msg.sender != address(s_chainlinkForwarder)) {
                revert BaseAutomation__OnlyChainlinkAutomation();
            }
        } else {
            // After grace period: owner or Chainlink Automation can call
            if (msg.sender != address(s_chainlinkForwarder)) {
                emit ManualUpkeepExecuted(msg.sender, block.timestamp);
            }
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

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function getChainlinkForwarder() external view returns (address) {
        return s_chainlinkForwarder;
    }

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function getGracePeriod() external pure returns (uint256) {
        return GRACE_PERIOD;
    } 

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function getUpkeepId() external view returns (uint256) {
        return s_upkeepId;
    }

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function getInterval() external pure returns (uint256) {
        return INTERVAL;
    }

    /// @dev Inherited from IBaseAutomation. See interface for details.
    function getLastUpkeep() external view returns (uint256) {
        return s_lastUpkeep;
    }
    
    /// @dev Inherited from IBaseAutomation. See interface for details.
    function getAllUpkeepInfo() external view returns (uint256 interval, uint256 gracePeriod, uint256 lastUpkeep) {
        return (INTERVAL, GRACE_PERIOD, s_lastUpkeep);
    }
}
