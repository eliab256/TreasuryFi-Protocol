//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBondAutomation {
    // --- Errors ---
    error BondAutomation__ChainlinkForwarderAddressAlreadySet();
    error BondAutomation__ChainlinkUpkeepIdAlreadySet();
    error BondAutomation__OnlyChainlinkAutomationOrOwner();
    error BondAutomation__OnlyChainlinkAutomation();
    error BondAutomation__UpkeepNotNeeded();

    // --- Events ---
    event BondAutomation__ManualUpkeepExecuted(
        address indexed executor,
        uint256 indexed timestamp
    );

    // --- Setters ---
    function setChainlinkForwarder(address _chainlinkForwarder) external;
  
}
