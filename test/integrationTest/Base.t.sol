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
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFunctionsRouter} from "../mocks/MockFunctionsRouter.sol";
import {BondOracle} from "../../src/oracles/BondOracle.sol";
import {ReservesOracle} from "../../src/oracles/ReservesOracle.sol";
import {BondYieldsResponse, ReservesResponse} from "../../src/types.sol";
import {OracleDataExamples} from "./OracleDataExamples.sol";

import {TokenConstants as C} from "../../src/tokens/TokenConstants.sol";

contract Base is Test {
    HelperConfig internal helperConfig;
    ITreasuryBondToken internal treasuryBondToken;
    ITreasury internal treasury;
    IBondOracle internal bondOracle;
    IReservesOracle internal reservesOracle;
    IBondAutomation internal bondAutomation;
    IReservesAutomation internal reservesAutomation;
    IBondFunctionsConsumer internal bondFunctionsConsumer;
    IReservesFunctionsConsumer internal reservesFunctionsConsumer;
    IUpdateRiskManagerAutomation internal updateRiskManagerAutomation;

    // Mocks
    MockERC20 internal mockUsdc;
    MockERC20 internal mockLinkToken;
    MockV3Aggregator internal mockUsdcPriceFeed;
    MockFunctionsRouter internal mockFunctionsRouter;
    
    uint256 internal upkeepId;

    uint256 internal constant INVALID_SLOT = C.SLOT_30Y + 1;
    uint256 internal constant PENALTY_PERIOD_ENDED = C.PENALTY_PERIOD_30Y + 1 days;
    // Private key of ANVIL_SIGNER (account 9) — used to sign ReservesOracle updates in tests
    uint256 internal constant ANVIL_SIGNER_PRIVATE_KEY = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;

    //Test Partecipants
    address internal spvSigner;
    address internal deployer;
    address internal forwarder;
    address internal USER_1 = makeAddr("USER_1");
    address internal USER_2 = makeAddr("USER_2");
    address internal USER_3 = makeAddr("USER_3");

    uint256 public constant STARTING_ETH_BALANCE_TREASURYBOND_CONTRACT = 10 ether;
    uint256 public constant STARTING_ETH_BALANCE_TREASURY_CONTRACT = 10 ether;
    uint256 public constant STARTING_ETH_BALANCE_DEPLOYER = 10 ether;
    uint256 public constant STARTING_ETH_BALANCE_USER_1 = 10 ether;
    uint256 public constant STARTING_ETH_BALANCE_USER_2 = 10 ether;
    uint256 public constant STARTING_ETH_BALANCE_USER_3 = 10 ether;

    uint256 public constant STARTING_USDC_DEPLOYER_BALANCE = 100000 * 10 ** 6;
    uint256 public constant STARTING_USDC_BALANCE_USER_1 = 10000 * 10 ** 6;
    uint256 public constant STARTING_USDC_BALANCE_USER_2 = 10000 * 10 ** 6;
    uint256 public constant STARTING_USDC_BALANCE_USER_3 = 10000 * 10 ** 6;

    int256 public constant INITIAL_USD_USDC_PRICE = 1 * 10 ** 8;

    // Oracle data examples
    BondYieldsResponse internal regularYieldsCurve = OracleDataExamples.regularYieldsCurve();
    BondYieldsResponse internal invertedYieldsCurve = OracleDataExamples.invertedYieldsCurve();
    BondYieldsResponse internal yieldsDataBroken = OracleDataExamples.yieldsDataBroken();
    BondYieldsResponse internal yieldsDataStale = OracleDataExamples.yieldsDataStale();

    ReservesResponse internal reservesHealthy = OracleDataExamples.reservesHealthy();
    ReservesResponse internal reservesRiskInsolvency = OracleDataExamples.reservesRiskInsolvency();
    ReservesResponse internal reservesDataBroken = OracleDataExamples.reservesDataBroken();
    ReservesResponse internal reservesDataStale = OracleDataExamples.reservesDataStale();


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

        (mockUsdc, mockLinkToken, mockUsdcPriceFeed, mockFunctionsRouter) = helperConfig.getMocks();

        spvSigner = helperConfig.getActiveNetworkConfig().signer;

        vm.deal(address(treasuryBondToken), STARTING_ETH_BALANCE_TREASURYBOND_CONTRACT);
        vm.deal(address(treasury), STARTING_ETH_BALANCE_TREASURY_CONTRACT);
        vm.deal(deployer, STARTING_ETH_BALANCE_DEPLOYER);
        vm.deal(USER_1, STARTING_ETH_BALANCE_USER_1);
        vm.deal(USER_2, STARTING_ETH_BALANCE_USER_2);
        vm.deal(USER_3, STARTING_ETH_BALANCE_USER_3);

        mockUsdc.mint(deployer, STARTING_USDC_DEPLOYER_BALANCE);
        mockUsdc.mint(USER_1, STARTING_USDC_BALANCE_USER_1);
        mockUsdc.mint(USER_2, STARTING_USDC_BALANCE_USER_2);
        mockUsdc.mint(USER_3, STARTING_USDC_BALANCE_USER_3);

        mockUsdcPriceFeed.updateAnswer(INITIAL_USD_USDC_PRICE);
    }

    /**
     * @dev Refreshes all mock price feeds to block.timestamp.
     *      Required after vm.warp() because Index.getLatestPrice reverts with
     *      Index__PriceIsStale when updatedAt > MAX_DELAY (1 hour) in the past.
     */
    function _refreshPriceFeeds() internal {
        mockUsdcPriceFeed.updateAnswer(INITIAL_USD_USDC_PRICE);
    }

    /**
     * @dev Helper to manually push new yield data into BondOracle.
     *      Pranks as bondFunctionsConsumer which holds UPDATER_ROLE on BondOracle.
     * @param yields BondYieldsResponse with values in basis-points×100 (e.g. 45000 = 4.50%).
     */
    function _updateBondOracleYields(BondYieldsResponse memory yields) internal {
        uint256[] memory values = new uint256[](4);
        values[0] = yields.twoYearYield;
        values[1] = yields.fiveYearYield;
        values[2] = yields.tenYearYield;
        values[3] = yields.thirtyYearYield;
        vm.prank(address(bondFunctionsConsumer));
        BondOracle(address(bondOracle)).updateYields(values, yields.timestamp, "");
    }

    /**
     * @dev Helper to manually push new reserves data into ReservesOracle.
     *      Pranks as reservesFunctionsConsumer which holds UPDATER_ROLE on ReservesOracle.
     *      Signs the payload with ANVIL_SIGNER_PRIVATE_KEY (account 9 — matches ANVIL_SIGNER in CodeConstants).
     * @param reserves ReservesResponse with per-slot values in 8 decimals.
     *                 Aggregated fields (cashBufferUsdTotalValue, totalUsdBondsValue, totalUsdPortfolioValue)
     *                 are ignored — the oracle recalculates them from the per-slot arrays.
     */
    function _updateReservesOracleValues(ReservesResponse memory reserves) internal {
        uint256[4] memory bond;
        bond[0] = reserves.twoYearUsdBondsValue;
        bond[1] = reserves.fiveYearUsdBondsValue;
        bond[2] = reserves.tenYearUsdBondsValue;
        bond[3] = reserves.thirtyYearUsdBondsValue;

        uint256[4] memory cash;
        cash[0] = reserves.twoYearUsdCashValue;
        cash[1] = reserves.fiveYearUsdCashValue;
        cash[2] = reserves.tenYearUsdCashValue;
        cash[3] = reserves.thirtyYearUsdCashValue;

        bytes32 hash = keccak256(abi.encode(bond, cash, reserves.timestamp));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ANVIL_SIGNER_PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(address(reservesFunctionsConsumer));
        ReservesOracle(address(reservesOracle)).updateUsdValues(bond, cash, reserves.timestamp, signature, "");
    }
}