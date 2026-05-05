//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IUpdateRiskManagerAutomation is AutomationCompatibleInterface, IAccessControl {
    // Errors
    error UpdateRiskManager__ZeroAddress();
    error UpdateRiskManager__OnlyChainlinkAutomation();
    error UpdateRiskManager__OnlyChainlinkAutomationOrOwner();
    error UpdateRiskManager__UpkeepNotNeeded();
    error UpdateRiskManager__ChainlinkForwarderAddressAlreadySet();
    error UpdateRiskManager__InvalidUpkeepId();
    error UpdateRiskManager__ChainlinkUpkeepIdAlreadySet();

    // Events
    event ManualUpkeepExecuted(address indexed caller, uint256 timestamp);

    // Setters
    function setChainlinkForwarder(address _chainlinkForwarder) external;
    function setUpkeepId(uint256 _upkeepId) external;

    // Getters
    function getChainlinkForwarder() external view returns (address);
    function getUpkeepId() external view returns (uint256);
}