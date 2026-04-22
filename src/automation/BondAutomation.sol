//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    AutomationCompatibleInterface
} from "@chainlink/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 */
contract BondAutomation is AutomationCompatibleInterface, Ownable {
    error BondAutomation__ChainlinkForwarderAddressAlreadySet();
    error BondAutomation__ChainlinkUpkeepIdAlreadySet();
    error BondAutomation__OnlyChainlinkAutomationOrOwner();
    error BondAutomation__OnlyChainlinkAutomation();
    error BondAutomation__UpkeepNotNeeded();

    event BondAutomation__ManualUpkeepExecuted(
        address indexed executor,
        uint256 indexed timestamp
    );

    uint256 internal constant GRACE_PERIOD = 6 hours; //@audit-info define a grace period

    /**
     * @dev Interface for the chainlink automation registry
     */
    address private s_chainlinkForwarder;

    /**
     * @dev Upkeep ID for Chainlink Automation
     */
    uint256 private s_upkeepId;

    address private s_bondOracle;
    address private s_functionsConsumer;

    uint256 internal s_interval;
    uint256 internal s_lastUpkeep;

    constructor(
        address _bondOracle,
        address _functionsConsumer,
        uint256 _interval
    ) Ownable(msg.sender) {
        s_bondOracle = _bondOracle;
        s_functionsConsumer = _functionsConsumer;
        s_interval = _interval;
    }

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
        upkeepNeeded = block.timestamp >= (s_lastUpkeep + s_interval);
        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        (bool upkeepNeeded, ) = checkUpkeep(performData);
        if (!upkeepNeeded) {
            revert BondAutomation__UpkeepNotNeeded();
        }

        bool withinGracePeriod = block.timestamp <
            (s_lastUpkeep + GRACE_PERIOD + s_interval);

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

        s_lastUpkeep = block.timestamp;

        // @audit-info implement logic to perform upkeep based on performData
    }
}
