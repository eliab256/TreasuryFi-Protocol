//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {DeployOracles} from "./DeployOracles.s.sol";
import {DeployTreasuryBondTokenAndTreasury} from "./DeployTreasuryBondTokenAndTreasury.s.sol";
import {DeployUpdateRiskManagerAutomation} from "./DeployUpdateRiskManagerAutomation.s.sol";
import {DeployIdentity} from "./DeployIdentity.s.sol";
import {IdentityRegistry} from "@t-rex/registry/implementation/IdentityRegistry.sol";
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
    // scripts decvlarations
    DeployIdentity deployIdentityScript;
    DeployOracles deployOraclesScript;
    DeployTreasuryBondTokenAndTreasury deployTreasuryAndTokenScript;
    DeployUpdateRiskManagerAutomation deployUpdateRiskManagerAutomationScript;

    // contracts declarations
    IdentityRegistry identityRegistry;
    TreasuryBondToken treasuryBondToken;
    Treasury treasury;
    BondOracle bondOracle;
    ReservesOracle reservesOracle;
    BondAutomation bondAutomation;
    ReservesAutomation reservesAutomation;
    BondFunctionsConsumer bondFunctionsConsumer;
    ReservesFunctionsConsumer reservesFunctionsConsumer;
    UpdateRiskManagerAutomation updateRiskManagerAutomation;

    function run() external returns(TreasuryBondToken, Treasury, BondOracle, 
        ReservesOracle, BondAutomation, ReservesAutomation, BondFunctionsConsumer, 
        ReservesFunctionsConsumer, UpdateRiskManagerAutomation, HelperConfig, 
        address deployer, uint256 upkeepId, address forwarder) { 

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        deployIdentityScript = new DeployIdentity();
        deployOraclesScript = new DeployOracles();
        deployTreasuryAndTokenScript = new DeployTreasuryBondTokenAndTreasury();
        deployUpdateRiskManagerAutomationScript = new DeployUpdateRiskManagerAutomation();
        deployer = config.deployer;

        vm.startBroadcast(deployer);

        // 1. Deploy identity registry and related contracts (claim topics registry,  claim issuer, 
        //    trusted issuers registry) and get the address of the deployed identity registry contract
        identityRegistry = deployIdentityScript.deployIdentity();

        // 2. Deploy oracles, automations, and functions consumers. 
        //    If not Anvil, also registers automations in Chainlink Automation registry and 
        //    sets forwarder addresses.
        (bondOracle,
        reservesOracle,
        bondFunctionsConsumer,
        reservesFunctionsConsumer,
        bondAutomation,
        reservesAutomation,
         , , , ) =  deployOraclesScript.deployOracles(helperConfig);

        // 3. Deploy Treasury and TreasuryBondToken, passing in the necessary constructor arguments
        treasury = deployTreasuryAndTokenScript.deployTreasury(config);
        treasuryBondToken = deployTreasuryAndTokenScript.deployToken(
            helperConfig, address(identityRegistry), address(bondAutomation), 
            address(reservesAutomation), address(reservesOracle), address(bondOracle), address(treasury));

        // 4. Set token contract address on treasury
        deployTreasuryAndTokenScript.setTokenContractOnTreasury(
            address(treasury), address(treasuryBondToken));

        // 5. Deploy UpdateRiskManagerAutomation
        (updateRiskManagerAutomation, , ) = 
            deployUpdateRiskManagerAutomationScript.deployUpdateRiskManagerAutomation(
            address(treasuryBondToken), address(reservesOracle), address(bondOracle), helperConfig);
        
        vm.stopBroadcast();
    }
}