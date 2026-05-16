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

    /**
     * @notice Constructor for the BondAutomation contract.
     * @param _functionsConsumer The address of the BondFunctionsConsumer contract.
     * @param initialAdmin The initial admin address passed to the BaseAutomation constructor.
     */
    constructor(
        address _functionsConsumer,
        address initialAdmin
    ) BaseAutomation(initialAdmin) {
        if (_functionsConsumer == address(0))
            revert BondAutomation__ZeroAddress();
        s_functionsConsumer = _functionsConsumer;
    }

    /**
     * @notice Internal hook to trigger Bond yield update request
     * @dev Overrides the _triggerRequest function from BaseAutomation to call the sendRequest function on the BondFunctionsConsumer.
     */
    function _triggerRequest() internal override {
        IBondFunctionsConsumer(s_functionsConsumer).sendRequest();
    }

    // --- Getters ---
    /// @dev Inherited from IBondAutomation. See interface for details.
    function getFunctionsConsumer() external view returns (address) {
        return s_functionsConsumer;
    }
}

