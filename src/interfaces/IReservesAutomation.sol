//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseAutomation} from "./IBaseAutomation.sol";

interface IReservesAutomation {
    // --- Errors ---
    error ReservesAutomation__ZeroAddress();

    // --- Getters ---
    function getFunctionsConsumer() external view returns (address);

}
