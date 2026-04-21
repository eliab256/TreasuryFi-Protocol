//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    FunctionsClient
} from "@chainlink/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {
    ConfirmedOwner
} from "@chainlink/src/v0.8/shared/access/ConfirmedOwner.sol";
import {
    FunctionsRequest
} from "@chainlink/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol";
contract BondOracle is ConfirmedOwner, FunctionsClient {
    constructor(
        address _functionsRouter
    ) ConfirmedOwner(msg.sender) FunctionsClient(_functionsRouter) {}
}
