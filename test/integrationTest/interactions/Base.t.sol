//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TreasuryBondToken} from "../../../src/tokens/TreasuryBondToken.sol";
import {Treasury} from "../../../src/tokens/Treasury.sol";
import {BondOracle} from "../../../src/oracles/BondOracle.sol";
import {ReservesOracle} from "../../../src/oracles/ReservesOracle.sol";
import {BondAutomation} from "../../../src/automation/BondAutomation.sol";
import {ReservesAutomation} from "../../../src/automation/ReservesAutomation.sol";
import {BondFunctionsConsumer} from "../../../src/oracles/BondFunctionsConsumer.sol";
import {ReservesFunctionsConsumer} from "../../../src/oracles/ReservesFunctionsConsumer.sol";
import {UpdateRiskManagerAutomation} from "../../../src/automation/UpdateRiskManagerAutomation.sol";
import {DeployProtocol} from "../../../script/DeployProtocol.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {MockFunctionsRouter} from "../../mocks/MockFunctionsRouter.sol";
import {BondYieldsResponse, ReservesResponse, SlotRiskParams} from "../../../src/types.sol";
import {OracleDataExamples} from "../../OracleDataExamples.sol";
import {TokenConstants as C} from "../../../src/tokens/TokenConstants.sol";

contract Base is Test {
    HelperConfig internal helperConfig;
    TreasuryBondToken internal treasuryBondToken;
    Treasury internal treasury;
    BondOracle internal bondOracle;
    ReservesOracle internal reservesOracle;
    BondAutomation internal bondAutomation;
    ReservesAutomation internal reservesAutomation;
    BondFunctionsConsumer internal bondFunctionsConsumer;
    ReservesFunctionsConsumer internal reservesFunctionsConsumer;
    UpdateRiskManagerAutomation internal updateRiskManagerAutomation;

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

    uint256 public constant STARTING_USDC_DEPLOYER_BALANCE = 10000000 * 10 ** 6;
    uint256 public constant STARTING_USDC_BALANCE_USER_1 = 10000 * 10 ** 6;
    uint256 public constant STARTING_USDC_BALANCE_USER_2 = 10000 * 10 ** 6;
    uint256 public constant STARTING_USDC_BALANCE_USER_3 = 10000 * 10 ** 6;

    int256 public constant INITIAL_USD_USDC_PRICE = 1 * 10 ** 8;

    // Oracle data examples
    BondYieldsResponse internal regularYieldsCurve = OracleDataExamples.regularYieldsCurve();
    BondYieldsResponse internal invertedYieldsCurve = OracleDataExamples.invertedYieldsCurve();
    BondYieldsResponse internal yieldsDataBroken = OracleDataExamples.yieldsDataBroken();
    BondYieldsResponse internal yieldsDataStale = OracleDataExamples.yieldsDataStale();

    ReservesResponse internal reservesHealthy = OracleDataExamples.normalReservesState();
    ReservesResponse internal reservesRiskInsolvency = OracleDataExamples.reservesRiskInsolvency();
    ReservesResponse internal reservesDataBroken = OracleDataExamples.reservesDataBroken();
    ReservesResponse internal reservesDataStale = OracleDataExamples.reservesDataStale();


    function setUp() public virtual {
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

        // Initialize slot risk params for all 4 slots.
        // reserveBuffer must be >= C.MAX_PERCENTAGE; redeemWindowDuration=0 means always open (V1 stub).
        SlotRiskParams memory defaultRiskParams = SlotRiskParams({
            maxDailyRedeem: type(uint128).max,
            redeemWindowOpen: 0,
            redeemWindowDuration: 0,
            reserveBuffer: uint32(C.MAX_PERCENTAGE)
        });
        vm.startPrank(deployer);
        treasuryBondToken.setSlotRiskParams(C.SLOT_2Y,  defaultRiskParams);
        treasuryBondToken.setSlotRiskParams(C.SLOT_5Y,  defaultRiskParams);
        treasuryBondToken.setSlotRiskParams(C.SLOT_10Y, defaultRiskParams);
        treasuryBondToken.setSlotRiskParams(C.SLOT_30Y, defaultRiskParams);
        vm.stopPrank();

        // Push initial valid oracle data so NAV calculations have a baseline.
        _updateBondOracleYields(regularYieldsCurve);
        _updateReservesOracleValues(reservesHealthy);

        // Propagate oracle data into the RiskManager's internal cache.
        // Deployer holds UPDATE_RISK_MANAGER_VALUES_ROLE (granted in deployToken()).
        vm.startPrank(deployer);
        treasuryBondToken.updateYieldsValues();
        treasuryBondToken.updateReserveValues();
        vm.stopPrank();

        // Max USDC allowance for all test users — Treasury is the actual transferFrom spender.
        vm.prank(USER_1);
        mockUsdc.approve(address(treasury), type(uint256).max);
        vm.prank(USER_2);
        mockUsdc.approve(address(treasury), type(uint256).max);
        vm.prank(USER_3);
        mockUsdc.approve(address(treasury), type(uint256).max);
    }

    /**
     * @dev Refreshes all data feeds (price feed, BondOracle, ReservesOracle) and RiskManager cache to block.timestamp.
     *      Required after vm.warp() to prevent staleness reverts:
     *      - UsdcUsdConverter: reverts if (block.timestamp - updatedAt) > MAX_USDC_DELAY (25 hours)
     *      - BondOracle/ReservesOracle: revert if (block.timestamp - lastTimestamp) > STALENESS_THRESHOLD (48 hours)
     *      Re-pushes the last known valid yields/reserves (from setUp) with updated block.timestamp and syncs RiskManager.
     */
    function _refreshAllDataFeeds() internal {
        mockUsdcPriceFeed.updateAnswer(INITIAL_USD_USDC_PRICE);
        
        // Re-push last known valid yields and reserves with updated timestamp
        BondYieldsResponse memory yields = regularYieldsCurve;
        yields.timestamp = block.timestamp;
        _updateBondOracleYields(yields);
        
        ReservesResponse memory reserves = reservesHealthy;
        reserves.timestamp = block.timestamp;
        _updateReservesOracleValues(reserves);
        
        // Sync RiskManager cache with refreshed oracle data
        vm.prank(deployer);
        treasuryBondToken.updateYieldsValues();
        vm.prank(deployer);
        treasuryBondToken.updateReserveValues();
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
        bondOracle.updateYields(values, yields.timestamp, "");
    }

    /**
     * @dev Updates a single yield slot in BondOracle, keeping all other slots at their current
     *      oracle-stored values. The resulting BondYieldsResponse passes all RiskManager validations:
     *      - unchanged slots have zero shock (same value)
     *      - the target slot uses the caller-supplied value (caller is responsible for staying
     *        within ±MAX_YIELD_SHOCK_BPS = 5% of the currently stored valid yield)
     * @param _slot   Slot id: C.SLOT_2Y (1), C.SLOT_5Y (2), C.SLOT_10Y (3), C.SLOT_30Y (4).
     * @param _newYield New yield value in basis-points×100 (e.g. 45_000 = 4.50%).
     */
    function _updateBondOracleSlotYield(uint256 _slot, uint256 _newYield) internal {
        BondYieldsResponse memory current = bondOracle.getAllYields();
        current.timestamp = block.timestamp;
        if (_slot == C.SLOT_2Y)  current.twoYearYield    = _newYield;
        else if (_slot == C.SLOT_5Y)  current.fiveYearYield   = _newYield;
        else if (_slot == C.SLOT_10Y) current.tenYearYield    = _newYield;
        else if (_slot == C.SLOT_30Y) current.thirtyYearYield = _newYield;
        _updateBondOracleYields(current);
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
        reservesOracle.updateUsdValues(bond, cash, reserves.timestamp, signature, "");
    }

    /**
     * @dev Helper to push broken yields data into oracle and trigger RiskManager validation.
     *      The corrupted 30Y yield value (×100 error) will cause the 30Y slot to be frozen.
     *      Useful for testing protocol behavior when oracle data is corrupted.
     *      Warps time forward by 1 second to ensure the new data is newer than the previous valid data.
     */
    function _updateYieldsDataBroken() internal {
        // Warp forward 1 second to ensure timestamp is newer than current s_lastValidYields.timestamp
        vm.warp(block.timestamp + 1);
        
        BondYieldsResponse memory broken = yieldsDataBroken;
        broken.timestamp = block.timestamp;
        
        // Push broken data to oracle
        _updateBondOracleYields(broken);
        
        // Trigger RiskManager validation to freeze the anomalous slot
        vm.prank(deployer);
        treasuryBondToken.updateYieldsValues();
    }

    /**
     * @dev Helper to push broken reserves data into oracle and trigger RiskManager validation.
     *      The corrupted 10Y bond value (×100 error) will cause the 10Y slot to be frozen.
     *      Useful for testing protocol behavior when oracle data is corrupted.
     *      Warps time forward by 1 second to ensure the new data is newer than the previous valid data.
     */
    function _updateReservesDataBroken() internal {
        // Warp forward 1 second to ensure timestamp is newer than current s_lastValidReserves.timestamp
        vm.warp(block.timestamp + 1);
        
        ReservesResponse memory broken = reservesDataBroken;
        broken.timestamp = block.timestamp;
        
        // Push broken data to oracle (internally pranks as reservesFunctionsConsumer)
        _updateReservesOracleValues(broken);
        
        // Trigger RiskManager validation to freeze the anomalous slot
        vm.prank(deployer);
        treasuryBondToken.updateReserveValues();
    }

 
}