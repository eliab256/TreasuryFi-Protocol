//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ITreasuryBondToken} from "../../src/interfaces/ITreasuryBondToken.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {IBondOracle} from "../../src/interfaces/IBondOracle.sol";
import {IReservesOracle} from "../../src/interfaces/IReservesOracle.sol";
import {IBondAutomation} from "../../src/interfaces/IBondAutomation.sol";
import {IReservesAutomation} from "../../src/interfaces/IReservesAutomation.sol";
import {IBondFunctionsConsumer} from "../../src/interfaces/IBondFunctionsConsumer.sol";
import {IReservesFunctionsConsumer} from "../../src/interfaces/IReservesFunctionsConsumer.sol";
import {IUpdateRiskManagerAutomation} from "../../src/interfaces/IUpdateRiskManagerAutomation.sol";
import {DeployProtocol} from "../../script/DeployProtocol.s.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";

import {TokenConstants as C} from "../../src/tokens/TokenConstants.sol";

contract Base is Test {
    ITreasuryBondToken internal treasuryBondToken;
    ITreasury internal treasury;
    IBondOracle internal bondOracle;
    IReservesOracle internal reservesOracle;
    IBondAutomation internal bondAutomation;
    IReservesAutomation internal reservesAutomation;
    IBondFunctionsConsumer internal bondFunctionsConsumer;
    IReservesFunctionsConsumer internal reservesFunctionsConsumer;
    IUpdateRiskManagerAutomation internal updateRiskManagerAutomation;
    HelperConfig internal helperConfig;
    address internal deployer;
    uint256 internal upkeepId;
    address internal forwarder;

    function setUp() public {
        DeployProtocol deployProtocol = new DeployProtocol();
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
        ) = deployProtocol.run();
    }
}