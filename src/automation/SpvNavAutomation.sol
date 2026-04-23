//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ISpvNavAutomation} from "../interfaces/ISpvNavAutomation.sol";
import {BaseAutomation} from "./BaseAutomation.sol";
import {
    ISpvNavFunctionsConsumer
} from "../interfaces/ISpvNavFunctionsConsumer.sol";

/**
 * @title SpvNavAutomation
 * @notice Chainlink Automation contract for triggering SPV NAV updates.
 * Inherits common upkeep logic from BaseAutomation.
 */
contract SpvNavAutomation is ISpvNavAutomation, BaseAutomation {
    address private s_functionsConsumer;

    constructor(
        address _functionsConsumer,
        address initialAdmin,
        uint256 _interval
    ) BaseAutomation(initialAdmin, _interval) {
        if (_functionsConsumer == address(0))
            revert SpvNavAutomation__ZeroAddress();
        s_functionsConsumer = _functionsConsumer;
    }

    /**
     * @notice Internal hook to trigger SPV NAV update request
     */
    function _triggerRequest() internal override {
        ISpvNavFunctionsConsumer(s_functionsConsumer).sendRequest();
    }

    // --- Getters ---
    function getFunctionsConsumer() external view returns (address) {
        return s_functionsConsumer;
    }
}
