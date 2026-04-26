//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBondAutomation} from "../interfaces/IBondAutomation.sol";
import {BaseAutomation} from "./BaseAutomation.sol";
import {IBondFunctionsConsumer} from "../interfaces/IBondFunctionsConsumer.sol";

/**
 * @title BondAutomation
 * @notice Chainlink Automation contract for triggering Bond yield updates.
 * Inherits common upkeep logic from BaseAutomation.
 */
contract BondAutomation is IBondAutomation, BaseAutomation {
    address private s_functionsConsumer;

    constructor(
        address _functionsConsumer,
        address initialAdmin,
        uint256 _interval
    ) BaseAutomation(initialAdmin, _interval) {
        if (_functionsConsumer == address(0))
            revert BondAutomation__ZeroAddress();
        s_functionsConsumer = _functionsConsumer;
    }

    /**
     * @notice Internal hook to trigger Bond yield update request
     */
    function _triggerRequest() internal override {
        IBondFunctionsConsumer(s_functionsConsumer).sendRequest();
    }

    // --- Getters ---
    function getFunctionsConsumer() external view returns (address) {
        return s_functionsConsumer;
    }
}

// Errors (defined for interface compatibility)
error BondAutomation__ZeroAddress();
