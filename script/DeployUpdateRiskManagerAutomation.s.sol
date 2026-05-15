//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.sol";
import { AutomationRegistration } from './AutomationRegistration.sol';
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IFunctionsSubscriptions} from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/interfaces/IFunctionsSubscriptions.sol";
import {UpdateRiskManagerAutomation} from "../src/automation/UpdateRiskManagerAutomation.sol";
import {DeployOracles} from "./DeployOracles.s.sol";

contract DeployUpdateRiskManagerAutomation is Script {
    bool isNotAnvil = block.chainid != 31337;
    DeployOracles deployOraclesScript = new DeployOracles();

    function run(address _tokenContract, 
        address _reserveOracleContract, 
        address _bondOracleContract) external 
        returns (UpdateRiskManagerAutomation updateRiskManagerAutomation, HelperConfig helperConfig, uint256 upkeepId, address forwarder) { 

        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast(config.deployer);

        ( updateRiskManagerAutomation,  upkeepId,  forwarder) = 
            deployUpdateRiskManagerAutomation(_tokenContract, _reserveOracleContract, _bondOracleContract, helperConfig);

        vm.stopBroadcast();

        return (updateRiskManagerAutomation, helperConfig, upkeepId, forwarder);
    }

    function deployUpdateRiskManagerAutomation(address _tokenContract, 
        address _reserveOracleContract, 
        address _bondOracleContract,
        HelperConfig helperConfig) public returns (UpdateRiskManagerAutomation, uint256 upkeepId, address forwarder) {
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        
        console.log('======================= UpdateRiskManagerAutomation Deployment =================');

        // 1. Deploy UpdateRiskManagerAutomation contract
        UpdateRiskManagerAutomation updateRiskManagerAutomation = 
                new UpdateRiskManagerAutomation( _tokenContract, _reserveOracleContract, _bondOracleContract);

        console.log("UpdateRiskManagerAutomation deployed at:", address(updateRiskManagerAutomation));
        
        // 2. If not Anvil, register the automation in Chainlink Automation registry and set upkeep ID on the contract
        upkeepId;
        if(isNotAnvil) {
            upkeepId = deployOraclesScript.registerAutomation(
                address(updateRiskManagerAutomation), 
                "UpdateRiskManagerAutomation", config);
        }  
        updateRiskManagerAutomation.setUpkeepId(upkeepId);
        console.log("UpdateRiskManagerAutomation registered with upkeepID:", upkeepId);
        console.log("Upkeep ID:", updateRiskManagerAutomation.getUpkeepId());

        // 3. If not Anvil, set forwarder address on the contract
        forwarder = helperConfig.getForwarderFromUpkeepId(upkeepId);

        updateRiskManagerAutomation.setChainlinkForwarder(forwarder);

        if(forwarder != address(0)) {
            console.log("Forwarder set on UpdateRiskManagerAutomation:", forwarder);
        } else {
            console.log("Warning: Forwarder address is zero. This may cause issues with automation execution.");
        }

        console.log('==============================================================');
        console.log('');
         
        return (updateRiskManagerAutomation, upkeepId, forwarder);
    }
 
}