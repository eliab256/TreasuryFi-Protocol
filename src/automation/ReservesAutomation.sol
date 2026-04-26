//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IReservesAutomation} from "../interfaces/IReservesAutomation.sol";
import {BaseAutomation} from "./BaseAutomation.sol";
import {
    IReservesFunctionsConsumer
} from "../interfaces/IReservesFunctionsConsumer.sol";

/**
 * @title ReservesAutomation
 * @notice Chainlink Automation contract for triggering Reserves NAV updates.
 * Inherits common upkeep logic from BaseAutomation.
 */
contract ReservesAutomation is IReservesAutomation, BaseAutomation {
    
    address private s_functionsConsumer;

    constructor(
        address _functionsConsumer,
        address initialAdmin,
        uint256 _interval
    ) BaseAutomation(initialAdmin, _interval) {
        if (_functionsConsumer == address(0))
            revert ReservesAutomation__ZeroAddress();
        s_functionsConsumer = _functionsConsumer;
    }

    /**
     * @notice Internal hook to trigger Reserves NAV update request
     */
    function _triggerRequest() internal override {
        IReservesFunctionsConsumer(s_functionsConsumer).sendRequest();
    }

    // --- Getters ---
    function getFunctionsConsumer() external view returns (address) {
        return s_functionsConsumer;
    }
}
