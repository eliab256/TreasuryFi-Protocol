//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {TreasuryBondToken} from "../src/tokens/TreasuryBondToken.sol";
import {Treasury} from "../src/tokens/Treasury.sol";
import {BondOracle} from "../src/oracles/BondOracle.sol";
import {ReservesOracle} from "../src/oracles/ReservesOracle.sol";
import {BondAutomation} from "../src/automation/BondAutomation.sol";
import {ReservesAutomation} from "../src/automation/ReservesAutomation.sol";
import {BondFunctionsConsumer} from "../src/oracles/BondFunctionsConsumer.sol";
import {ReservesFunctionsConsumer} from "../src/oracles/ReservesFunctionsConsumer.sol";
import {UpdateRiskManagerAutomation} from "../src/automation/UpdateRiskManagerAutomation.sol";
import {TokenConstants as C} from "../src/tokens/TokenConstants.sol";
import { AutomationRegistration } from './AutomationRegistration.sol';
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract DeployProtocol is Script {
    function run() external returns(TreasuryBondToken, Treasury, BondOracle, 
        ReservesOracle, BondAutomation, ReservesAutomation, BondFunctionsConsumer, 
        ReservesFunctionsConsumer, UpdateRiskManagerAutomation, HelperConfig, 
        address deployer, uint256 upkeepId, address forwarder) { 

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.activeNetworkConfig();

        deployer = config.deployer;

        vm.startBroadcast(deployer);

        console.log('======================= Contracts Deployment =================');
    }
}