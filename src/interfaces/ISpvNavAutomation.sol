//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBaseAutomation} from "./IBaseAutomation.sol";

interface ISpvNavAutomation {
    // --- Errors ---
    error SpvNavAutomation__ZeroAddress();

    // --- Getters ---
    function getFunctionsConsumer() external view returns (address);
}
