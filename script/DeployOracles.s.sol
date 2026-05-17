//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.sol";
import { AutomationRegistration } from './AutomationRegistration.sol';
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IFunctionsSubscriptions} from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/interfaces/IFunctionsSubscriptions.sol";
import {BondOracle} from "../src/oracles/BondOracle.sol";
import {ReservesOracle} from "../src/oracles/ReservesOracle.sol";
import {BondAutomation} from "../src/automation/BondAutomation.sol";
import {ReservesAutomation} from "../src/automation/ReservesAutomation.sol";
import {BondFunctionsConsumer} from "../src/oracles/BondFunctionsConsumer.sol";
import {ReservesFunctionsConsumer} from "../src/oracles/ReservesFunctionsConsumer.sol";


contract DeployOracles is Script {
    error InsufficientLinkBalance(uint256 required, uint256 actual);

    bool isNotAnvil = block.chainid != 31337;

    function run() external returns (BondOracle, ReservesOracle, BondFunctionsConsumer, 
        ReservesFunctionsConsumer, BondAutomation, ReservesAutomation, uint256, uint256, address, address) { 

        HelperConfig helperConfig = new HelperConfig();

        console.log('======================= Oracles Deployment =================');

        (BondOracle bondOracle,
        ReservesOracle reservesOracle,
        BondFunctionsConsumer bondFunctionsConsumer,
        ReservesFunctionsConsumer reservesFunctionsConsumer,
        BondAutomation bondAutomation,
        ReservesAutomation reservesAutomation,
        uint256 bondUpkeepId,
        uint256 reservesUpkeepId,
        address bondForwarder,
        address reservesForwarder) = deployOracles(helperConfig);

        return (
            bondOracle,
            reservesOracle,
            bondFunctionsConsumer,
            reservesFunctionsConsumer,
            bondAutomation,
            reservesAutomation,
            reservesUpkeepId,
            bondUpkeepId,
            reservesForwarder,
            bondForwarder
        );
    }

    function deployOracles(HelperConfig helperConfig) public 
        returns(BondOracle, ReservesOracle, BondFunctionsConsumer, ReservesFunctionsConsumer, BondAutomation, ReservesAutomation,
        uint256 reservesUpkeepId, uint256 bondUpkeepId, address reservesForwarder, address bondForwarder) {
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
    
            console.log('======================= Oracles Deployment =================');
        console.log('======================= Oracles Stacks Contracts Deployment =================');
        // deploy BondOracle and reservesOracle
        vm.broadcast(config.deployer);
        BondOracle bondOracle = new BondOracle(config.deployer);
        vm.broadcast(config.deployer);
        ReservesOracle reservesOracle = new ReservesOracle(config.signer, config.deployer);

        console.log("BondOracle deployed at:", address(bondOracle));
        console.log("ReservesOracle deployed at:", address(reservesOracle));

        // deploy functions consumers
        vm.broadcast(config.deployer);
        BondFunctionsConsumer bondFunctionsConsumer = new BondFunctionsConsumer(config.functionsRouter, config.donId, config.gasLimit, address(bondOracle), config.deployer);
        vm.broadcast(config.deployer);
        ReservesFunctionsConsumer reservesFunctionsConsumer = new ReservesFunctionsConsumer(config.functionsRouter, config.donId, config.gasLimit, address(reservesOracle), config.deployer);

        console.log("BondFunctionsConsumer deployed at:", address(bondFunctionsConsumer));
        console.log("ReservesFunctionsConsumer deployed at:", address(reservesFunctionsConsumer));

        // set function consumers in oracles
        // vm.broadcast sets msg.sender == config.deployer in forge tests (like prank)
        // and records each call as a separate transaction in forge script (for production).
        vm.broadcast(config.deployer);
        bondOracle.setFunctionsConsumer(address(bondFunctionsConsumer));
        vm.broadcast(config.deployer);
        reservesOracle.setFunctionsConsumer(address(reservesFunctionsConsumer));

        console.log("Set FunctionsConsumer in BondOracle asdress:", address(bondFunctionsConsumer));
        console.log("Set FunctionsConsumer in ReservesOracle asdress:", address(reservesFunctionsConsumer));

        // deploy automation — config.deployer is DEFAULT_ADMIN_ROLE holder
        vm.broadcast(config.deployer);
        BondAutomation bondAutomation = new BondAutomation(address(bondFunctionsConsumer), config.deployer);
        vm.broadcast(config.deployer);
        ReservesAutomation reservesAutomation = new ReservesAutomation(address(reservesFunctionsConsumer), config.deployer);

        console.log("BondAutomation deployed at:", address(bondAutomation));
        console.log("ReservesAutomation deployed at:", address(reservesAutomation));

        // grant automation contracts permission to call functions consumers
        vm.broadcast(config.deployer);
        bondFunctionsConsumer.setAutomationContract(address(bondAutomation));
        vm.broadcast(config.deployer);
        reservesFunctionsConsumer.setAutomationContract(address(reservesAutomation));

        console.log('==============================================================');
        console.log('');

        console.log('======================== Automation Contracts Settings ==================');

        // if not Anvil, register automations contracts in the chainlink automation registry
        if(isNotAnvil){
            bondUpkeepId = registerAutomation( address(bondAutomation),"Bond Automation", config);
            reservesUpkeepId = registerAutomation(address(reservesAutomation), "Reserves Automation", config);
        }

        // setUpkeepID on automation contracts (skip on Anvil where upkeepId is 0)
        if (bondUpkeepId != 0) {
            vm.broadcast(config.deployer);
            bondAutomation.setUpkeepId(bondUpkeepId);
        }
        if (reservesUpkeepId != 0) {
            vm.broadcast(config.deployer);
            reservesAutomation.setUpkeepId(reservesUpkeepId);
        }
        
        console.log("ReservesAutomation registered with upkeep ID:", reservesUpkeepId);
        console.log("Upkeep ID:", reservesAutomation.getUpkeepId());
        console.log("BondAutomation registered with upkeep ID:", bondUpkeepId);
        console.log("Upkeep ID:", bondAutomation.getUpkeepId());

        // Get forwarder from config and set in automation contracts
        address bondForwarder = helperConfig.getForwarderFromUpkeepId(bondUpkeepId);
        address reservesForwarder = helperConfig.getForwarderFromUpkeepId(reservesUpkeepId);
        
        vm.broadcast(config.deployer);
        bondAutomation.setChainlinkForwarder(bondForwarder);
        vm.broadcast(config.deployer);
        reservesAutomation.setChainlinkForwarder(reservesForwarder);

        if(reservesForwarder == address(0) || bondForwarder == address(0)) {
            console.log("Warning: Forwarder address is zero. This may cause issues with automation execution.");
        } else {
            console.log("ReservesAutomation forwarder set to:", reservesForwarder);
            console.log("BondAutomation forwarder set to:", bondForwarder);
        }

        console.log('==============================================================');
        console.log('');

        return(
            bondOracle,
            reservesOracle,
            bondFunctionsConsumer,
            reservesFunctionsConsumer,
            bondAutomation,
            reservesAutomation,
            bondUpkeepId,
            reservesUpkeepId,
            bondForwarder,
            reservesForwarder
        );
    }
 
    /**
     * @notice Register upkeep on Chainlink Automation
     * @dev Handles the entire registration process
     * @dev It use the activeNetworkConfig parameters
     * @param _upkeepContract Address of the contract to automate
     * @param _name Name of the upkeep
     * @return upkeepId ID of the registered upkeep
     */
    function registerAutomation(
        address _upkeepContract,
        string memory _name,
        HelperConfig.NetworkConfig memory _config
    ) public returns (uint256 upkeepId) {
        console.log('');
        console.log('==================== Registering Chainlink Automation ====================');
        console.log('Registering Chainlink Automation...');
        console.log('Upkeep Contract:', _upkeepContract);
        console.log('Admin:', _config.deployer);
        console.log(
            'Admin Link Balance: ',
            LinkTokenInterface(_config.linkToken).balanceOf(_config.deployer) / 1e18,
            ' LINK'
        );
        console.log('Funding Amount:', _config.fundingAmountForEachUpkeep / 1e18, 'LINK');

        // 1. Deploy AutomationRegistration helper
        vm.broadcast(_config.deployer);
        AutomationRegistration registration = new AutomationRegistration(
            _config.linkToken,
            _config.automationRegistrar
        );
        console.log('AutomationRegistration deployed at:', address(registration));

        // 2. Check LINK balance
        LinkTokenInterface link = LinkTokenInterface(_config.linkToken);
        uint256 linkBalance = link.balanceOf(_config.deployer);

        console.log('Link balance of admin:', linkBalance / 1e18, 'LINK');
        console.log('Required funding amount:', _config.fundingAmountForEachUpkeep / 1e18, 'LINK');
        if (linkBalance < _config.fundingAmountForEachUpkeep) {
            revert InsufficientLinkBalance(_config.fundingAmountForEachUpkeep, linkBalance);
        }

        // 3. Transfer LINK to the registration contract
        vm.broadcast(_config.deployer);
        link.approve(address(registration), _config.fundingAmountForEachUpkeep);
        console.log('Transferred', _config.fundingAmountForEachUpkeep / 1e18, 'LINK to registration contract');
        console.log('==========================================================================');
        console.log('');

        // 4. Register the upkeep
        vm.broadcast(_config.deployer);
        upkeepId = registration.registerAndFundUpkeep(
            _upkeepContract,
            _name,
            _config.gasLimit,
            _config.deployer,
            _config.fundingAmountForEachUpkeep
        );

        return upkeepId;
    }
}