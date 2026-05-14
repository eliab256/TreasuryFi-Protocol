//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {ITreasuryBondToken} from "../interfaces/ITreasuryBondToken.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {IBondAutomation} from "../interfaces/IBondAutomation.sol";
import {IReservesAutomation} from "../interfaces/IReservesAutomation.sol";
import {IBondFunctionsConsumer} from "../interfaces/IBondFunctionsConsumer.sol";
import {IReservesFunctionsConsumer} from "../interfaces/IReservesFunctionsConsumer.sol";
import {IUpdateRiskManagerAutomation} from "../interfaces/IUpdateRiskManagerAutomation.sol";
import {TokenConstants as C} from "../tokens/TokenConstants.sol";

contract DeployProtocol is Script {
    function run() external {
        vm.startBroadcast();
    }
}