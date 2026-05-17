//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployProtocol} from "../../../script/DeployProtocol.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.sol";
import {TreasuryBondToken} from "../../../src/tokens/TreasuryBondToken.sol";
import {Treasury} from "../../../src/tokens/Treasury.sol";
import {BondOracle} from "../../../src/oracles/BondOracle.sol";
import {ReservesOracle} from "../../../src/oracles/ReservesOracle.sol";
import {BondAutomation} from "../../../src/automation/BondAutomation.sol";
import {ReservesAutomation} from "../../../src/automation/ReservesAutomation.sol";
import {BondFunctionsConsumer} from "../../../src/oracles/BondFunctionsConsumer.sol";
import {ReservesFunctionsConsumer} from "../../../src/oracles/ReservesFunctionsConsumer.sol";
import {UpdateRiskManagerAutomation} from "../../../src/automation/UpdateRiskManagerAutomation.sol";
import {IdentityRegistry} from "@t-rex/registry/implementation/IdentityRegistry.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TokenConstants as C} from "../../../src/tokens/TokenConstants.sol";

contract TestDeployProtocol is Test {
    DeployProtocol deployProtocolScript;
    HelperConfig helperConfig;
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
    address deployer;
    uint256 upkeepId;
    address forwarder;

    function setUp() public {
        deployProtocolScript = new DeployProtocol();

        (
            treasuryBondToken, 
            treasury, 
            bondOracle, 
            reservesOracle, 
            bondAutomation, 
            reservesAutomation, 
            bondFunctionsConsumer, 
            reservesFunctionsConsumer, 
            updateRiskManagerAutomation,
            helperConfig,
            deployer,
            upkeepId,
            forwarder
        ) = deployProtocolScript.run();
    }

    function test_DeployProtocolDeployContracts() public {
        assert(address(treasuryBondToken) != address(0));
        assert(address(treasury) != address(0));
        assert(address(bondOracle) != address(0));
        assert(address(reservesOracle) != address(0));
        assert(address(bondAutomation) != address(0));
        assert(address(reservesAutomation) != address(0));
        assert(address(bondFunctionsConsumer) != address(0));
        assert(address(reservesFunctionsConsumer) != address(0));
        assert(address(updateRiskManagerAutomation) != address(0));
    }

    function test_TreasuryBondTokenConstructorSettings() public {
        // Check constructor settings
        assert(treasuryBondToken.hasRole(treasuryBondToken.OWNER_ROLE(), deployer));
        assert(treasuryBondToken.hasRole(treasuryBondToken.UPDATE_RISK_MANAGER_VALUES_ROLE(), deployer));
        assert(treasuryBondToken.hasRole(treasuryBondToken.AUTOMATION_TRIGGERER_ROLE(), deployer)); 
        assert(treasuryBondToken.hasRole(treasuryBondToken.UPDATE_RISK_MANAGER_VALUES_ROLE(), deployer)); 
        // assert(treasuryBondToken.hasRole(treasuryBondToken.FEES_MANAGER_ROLE(),
        //      helperConfig.getActiveNetworkConfig().feesCollector));
    }

    function test_ERC3643AndERC3525ConstructorSettings() public {
         assert(treasuryBondToken.hasRole(treasuryBondToken.DEFAULT_ADMIN_ROLE(), deployer));
        assert(treasuryBondToken.hasRole(treasuryBondToken.PAUSER_ROLE(), deployer));
        assert(treasuryBondToken.hasRole(treasuryBondToken.FREEZER_ROLE(), deployer));
        assert(treasuryBondToken.hasRole(treasuryBondToken.RECOVERY_ROLE(), deployer));
        assert(treasuryBondToken.onchainID() == address(treasuryBondToken));
        //assert(treasuryBondToken.identityRegistry() == identityRegistry);
        //assert(address(treasuryBondToken.compliance()) != address(0)); // @audit-issue sistemare compliance cotnract

        assert(treasuryBondToken.valueDecimals() == 18);
        assertEq(treasuryBondToken.name(), "TreasuryFi Bond Token");
        assertEq(treasuryBondToken.symbol(), "TBT");
    }

    function test_RiskManagerConstructorSettings() public {
        assertEq(treasuryBondToken.getBondAutomation(), address(bondAutomation));
        assertEq(treasuryBondToken.getReservesAutomation(), address(reservesAutomation));
        assertEq(treasuryBondToken.getBondOracle(), address(bondOracle));
        assertEq(treasuryBondToken.getReservesOracle(), address(reservesOracle));
        assertEq(treasuryBondToken.getTreasury(), address(treasury));
        assertEq(treasuryBondToken.getInterval(), bondAutomation.getInterval());
        assertEq(treasuryBondToken.getGracePeriod(), bondAutomation.getGracePeriod());
    }

    function test_UsdUsdcConverterConstructorSettings() public {
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        assertEq(treasuryBondToken.getUsdc(), config.usdcAddress);
        assertEq(treasuryBondToken.getUsdcPriceFeed(), config.usdcPriceFeedAddress);
        assertEq(treasuryBondToken.getUsdcDecimals(), 6);
        assertEq(treasuryBondToken.getUsdcPriceFeedDecimals(), 8);
    }

    function test_bondAutomationConstructorSettings() public {
        assertEq(bondAutomation.getFunctionsConsumer(), address(bondFunctionsConsumer));
        assertEq(bondAutomation.hasRole(bondAutomation.DEFAULT_ADMIN_ROLE(), deployer), true);
        assertEq(bondAutomation.hasRole(bondAutomation.AUTOMATION_ROLE(), deployer), true);
        assertEq(bondAutomation.getUpkeepId(), upkeepId);
        //assertEq(bondAutomation.getChainlinkForwarder(), forwarder);
    }

    function test_ReservesAutomationConstructorSettings() public {
        assertEq(reservesAutomation.getFunctionsConsumer(), address(reservesFunctionsConsumer));
        assertEq(reservesAutomation.hasRole(reservesAutomation.DEFAULT_ADMIN_ROLE(), deployer), true);
        assertEq(reservesAutomation.hasRole(reservesAutomation.AUTOMATION_ROLE(), deployer), true);
        assertEq(reservesAutomation.getUpkeepId(), upkeepId);
        //assertEq(reservesAutomation.getChainlinkForwarder(), forwarder);
    }

    function test_UpdateRiskManagerAutomationConstructorSettings() public {
        assertEq(updateRiskManagerAutomation.hasRole(updateRiskManagerAutomation.DEFAULT_ADMIN_ROLE(), deployer), true);
        assertEq(updateRiskManagerAutomation.hasRole(
            updateRiskManagerAutomation.AUTOMATION_ROLE(), address(treasuryBondToken)), true);
        assertEq(updateRiskManagerAutomation.getTokenContract(), address(treasuryBondToken));
        assertEq(updateRiskManagerAutomation.getReservesOracle(), address(reservesOracle));
        assertEq(updateRiskManagerAutomation.getBondOracle(), address(bondOracle));
        assertEq(updateRiskManagerAutomation.getUpkeepId(), upkeepId);
        //assertEq(updateRiskManagerAutomation.getChainlinkForwarder(), forwarder);
    }

}