//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    IAutomationRegistryConsumer
} from "@chainlink/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 */
contract BondAutomation is IAutomationRegistryConsumer, Ownable {
    error BondAutomation__ChainlinkForwarderAddressAlreadySet();
    error BondAutomation__ChainlinkUpkeepIdAlreadySet();
    error BondAutomation__OnlyChainlinkAutomationOrOwner();
    error BondAutomation__OnlyChainlinkAutomation();
    error BondAutomation__UpkeepNotNeeded();

    event BondAutomation__ManualUpkeepExecuted(address indexed executor, uint256 indexed timestamp);

    uint256 internal constant GRACE_PERIOD = 6 hours; //@audit-info define a grace period

    /**
     * @dev Interface for the chainlink automation registry
     */
    address private s_chainlinkForwarder;

    /**
     * @dev Upkeep ID for Chainlink Automation
     */
    uint256 private s_upkeepId;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Sets the Chainlink Automation forwarder address
     * @dev Can only be set once by the owner
     * @param _chainlinkForwarder The address of the Chainlink Automation forwarder
     */
    function setChainlinkForwarder(
        address _chainlinkForwarder
    ) external onlyOwner {
        if (s_chainlinkForwarder != address(0)) {
            revert BondAutomation__ChainlinkForwarderAddressAlreadySet();
        }
        s_chainlinkForwarder = _chainlinkForwarder;
    }

    function setUpkeepId(uint256 _upkeepId) external onlyOwner {
        if (s_upkeepId != 0) {
            revert BondAutomation__ChainlinkUpkeepIdAlreadySet();
        }
        s_upkeepId = _upkeepId;
    }

    function checkUpkeep(
        bytes calldata /*checkData*/
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // @audit-info implement logic to check if upkeep is needed and prepare performData
        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        //bool withinGracePeriod = block.timestamp < (auctionEndTime + GRACE_PERIOD);

        if (withinGracePeriod) {
            // During grace period: only Chainlink Automation can call
            if (msg.sender != address(s_chainlinkForwarder)) {
                revert BondAutomation__OnlyChainlinkAutomation();
            }
        } else {
            // After grace period: only Chainlink Automation or owner can call
            if (
                msg.sender != address(s_chainlinkForwarder) &&
                msg.sender != owner()
            ) {
                revert BondAutomation__OnlyChainlinkAutomationOrOwner();
            }
            emit BondAutomation__ManualUpkeepExecuted(
                msg.sender,
                block.timestamp
            );
        }

        // @audit-info implement logic to perform upkeep based on performData
    }
}
