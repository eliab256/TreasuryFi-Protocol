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

    /**
     * @notice Constructor for the ReservesAutomation contract.
     * @param _functionsConsumer The address of the ReservesFunctionsConsumer contract.
     * @param initialAdmin The initial admin address passed to the BaseAutomation constructor.
     */
    constructor(
        address _functionsConsumer,
        address initialAdmin
    ) BaseAutomation(initialAdmin) {
        if (_functionsConsumer == address(0))
            revert ReservesAutomation__ZeroAddress();
        s_functionsConsumer = _functionsConsumer;
    }

    /**
     * @notice Internal hook to trigger Reserves UPDATE when upkeep is performed.
     * @dev Overrides the _triggerRequest function in BaseAutomation to call the sendRequest function on the ReservesFunctionsConsumer contract.
     */
    function _triggerRequest() internal override {
        IReservesFunctionsConsumer(s_functionsConsumer).sendRequest();
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IReservesAutomation).interfaceId || super.supportsInterface(interfaceId);
    }

    // --- Getters ---

    /// @dev Inherited from IReservesAutomation. See interface for details.
    function getFunctionsConsumer() external view returns (address) {
        return s_functionsConsumer;
    }
}
