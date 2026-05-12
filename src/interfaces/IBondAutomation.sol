//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseAutomation} from "./IBaseAutomation.sol";

interface IBondAutomation is IBaseAutomation {
    // --- Errors ---
    error BondAutomation__ZeroAddress();

    // --- Getters ---

    /**
     * @notice Returns the address of the Functions consumer
     * @return The address of the Functions consumer
     */
    function getFunctionsConsumer() external view returns (address);
}