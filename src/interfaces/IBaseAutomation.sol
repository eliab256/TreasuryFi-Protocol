//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    AutomationCompatibleInterface
} from "@chainlink/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IBaseAutomation is AutomationCompatibleInterface, IAccessControl {
    // --- Roles ---
    function AUTOMATION_ADMIN_ROLE() external view returns (bytes32);

    // --- Errors ---
    error BaseAutomation__ChainlinkForwarderAddressAlreadySet();
    error BaseAutomation__ChainlinkUpkeepIdAlreadySet();
    error BaseAutomation__OnlyChainlinkAutomationOrOwner();
    error BaseAutomation__OnlyChainlinkAutomation();
    error BaseAutomation__UpkeepNotNeeded();

    // --- Events ---
    event ManualUpkeepExecuted(
        address indexed executor,
        uint256 indexed timestamp
    );

    // --- Setters (onlyRole(AUTOMATION_ADMIN_ROLE)) ---
    function setChainlinkForwarder(address _chainlinkForwarder) external;
    function setUpkeepId(uint256 _upkeepId) external;

    // --- Automation (from AutomationCompatibleInterface) ---
    function checkUpkeep(
        bytes calldata checkData
    ) external view returns (bool upkeepNeeded, bytes memory performData);
    function performUpkeep(bytes calldata performData) external;

    // --- Getters ---
    function getChainlinkForwarder() external view returns (address);
    function getUpkeepId() external view returns (uint256);
    function getInterval() external view returns (uint256);
    function getLastUpkeep() external view returns (uint256);
}
