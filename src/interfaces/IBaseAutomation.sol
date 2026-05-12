//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title IBaseAutomation
 * @notice Interface for the BaseAutomation contract, defining common functions and events for Chainlink Automation contracts.
 */
interface IBaseAutomation is AutomationCompatibleInterface, IAccessControl {

    // --- Errors ---
    error BaseAutomation__ChainlinkForwarderAddressAlreadySet();
    error BaseAutomation__InvalidForwarderAddress();
    error BaseAutomation__ChainlinkUpkeepIdAlreadySet();
    error BaseAutomation__InvalidUpkeepId();
    error BaseAutomation__OnlyChainlinkAutomationOrOwner();
    error BaseAutomation__OnlyChainlinkAutomation();
    error BaseAutomation__UpkeepNotNeeded();

    // --- Events ---
    event ManualUpkeepExecuted(
        address indexed executor,
        uint256 indexed timestamp
    );

    // --- Setters ---

    /**
     * @notice Sets the Chainlink Automation forwarder address
     * @dev Can only be set once by an admin
     * @param _chainlinkForwarder The address of the Chainlink Automation forwarder
     */
    function setChainlinkForwarder(address _chainlinkForwarder) external;

    /**
     * @notice Sets the upkeep ID
     * @dev Can only be set once by an admin
     * @param _upkeepId The ID of the upkeep
     */
    function setUpkeepId(uint256 _upkeepId) external;

    // --- Automation ---

    /// @dev Inherited from AutomationCompatibleInterface. See interface for details.
    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData);

    /// @dev Inherited from AutomationCompatibleInterface. See interface for details.
    function performUpkeep(bytes calldata performData) external;

    // --- Getters ---

    /**
     * @notice Returns the address of the Chainlink Automation forwarder
     * @return The address of the Chainlink Automation forwarder
     */
    function getChainlinkForwarder() external view returns (address);
    /**
     * @notice Returns the upkeep ID
     * @return The upkeep ID
     */
    function getUpkeepId() external view returns (uint256);

    /**
     * @notice Returns the interval between upkeeps
     * @return The interval between upkeeps
     */
    function getInterval() external view returns (uint256);
    
    /**
     * @notice Returns the timestamp of the last upkeep
     * @return The timestamp of the last upkeep
     */
    function getLastUpkeep() external view returns (uint256);
    
    /**
     * @notice Returns the grace period for manual upkeep
     * @return The grace period for manual upkeep
     */
    function getGracePeriod() external pure returns (uint256);
    
    /**
     * @notice Returns all upkeep information
     * @return interval The interval between upkeeps
     * @return gracePeriod The grace period for manual upkeep
     * @return lastUpkeep The timestamp of the last upkeep
     */
    function getAllUpkeepInfo() external view returns (uint256 interval, uint256 gracePeriod, uint256 lastUpkeep);
}
