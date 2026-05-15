// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CodeConstants} from "./CodeConstants.sol";
import {Script} from "forge-std/Script.sol";
import {TreasuryBondTokenConstructorParams} from "../src/types.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockFunctionsRouter} from "../test/mocks/MockFunctionsRouter.sol";
import {IKeeperRegistryMaster} from "@chainlink/contracts/src/v0.8/interfaces/KeeperRegistryInterface.sol";

/**
 * @title HelperConfig
 * @notice Manages chain-specific configuration
 * @dev Returns appropriate config based on current chain
 */
contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig{
        address deployer;
        string name;
        string symbol;
        uint8 decimals;
        uint256 apiUpdateInterval;
        address usdcAddress;
        address usdcPriceFeedAddress;
        //address identityRegistry;
        // address bondAutomation;
        // address reservesAutomation;
        // address updateRiskManagerAutomation;
        // address reservesOracle;
        // address bondOracle;
        // address treasury;
        address feesCollector;
        address automationRegistry;
        address automationRegistrar;
        address linkToken; 
        address fundingAmountForEachUpkeep;
        address functionsRouter;
        uint256 donId;
        uint32 gasLimit;
        address signer;
    }

    NetworkConfig public activeNetworkConfig;
    MockV3Aggregator public mockUsdcPriceFeed;
    MockFunctionsRouter public mockFunctionsRouter;
    MockERC20 public mockUsdc;
    MockERC20 public mockLinkToken;
    address public anvilFeeCollector;
    address public anvilRegistryMock;
    address public anvilRegistrarMock;
   

    /**
     * @notice Initializes HelperConfig and sets active network configuration based on current chain
     * @dev Automatically detects chain ID and loads appropriate configuration
     * @dev Reverts with HelperConfig__InvalidChainId if chain is not supported
     */
    constructor() {
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getEthSepoliaConfig();
        } else if (block.chainid == POLYGON_AMOY_CHAIN_ID) {
            activeNetworkConfig = getPolygonAmoyConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /**
     * @notice Returns network configuration for a specific chain ID
     * @dev Allows retrieving configuration for chains other than the current one
     * @dev Useful for testing deployment on multiple chains
     * @param chainId The chain ID to get configuration for
     * @return NetworkConfig Configuration struct for the specified chain
     * @custom:throws HelperConfig__InvalidChainId if chainId is not supported
     */
    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == ETH_SEPOLIA_CHAIN_ID) {
            return getEthSepoliaConfig();
        } else if (chainId == POLYGON_AMOY_CHAIN_ID) {
            return getPolygonAmoyConfig();
        } else if (chainId == ANVIL_CHAIN_ID) {
            return getAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getEthSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            deployer: ETH_SEPOLIA_DEPLOYER_ADDRESS,
            name: BASE_TOKEN_NAME,
            symbol: BASE_TOKEN_SYMBOL,
            decimals: BASE_TOKEN_DECIMALS,
            apiUpdateInterval: API_UPDATE_INTERVAL,
            usdcAddress: ETH_SEPOLIA_USDC_CONTRACT,
            usdcPriceFeedAddress: ETH_SEPOLIA_USDC_PRICEFEED,
            feesCollector: ETH_SEPOLIA_FEES_COLLECTOR,
            automationRegistry: ETH_SEPOLIA_KEEPERS_REGISTRY,
            automationRegistrar: ETH_SEPOLIA_KEEPERS_REGISTRAR,
            linkToken: ETH_SEPOLIA_LINK_TOKEN,
            fundingAmountForEachUpkeep: LINK_FUNDING_AMOUNT_FOR_EACH_UPKEEP,
            functionsRouter: ETH_SEPOLIA_FUNCIONS_ROUTER,
            donId: ETH_SEPOLIA_DON_ID,
            gasLimit: ETH_SEPOLIA_GAS_LIMIT,
            signer: ETH_SEPOLIA_SIGNER
        });
    }


    function getPolygonAmoyConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            name: BASE_TOKEN_NAME,
            symbol: BASE_TOKEN_SYMBOL,
            decimals: BASE_TOKEN_DECIMALS,
            apiUpdateInterval: API_UPDATE_INTERVAL,
            usdcAddress: POLYGON_AMOY_USDC_CONTRACT,
            usdcPriceFeedAddress: POLYGON_AMOY_USDC_PRICEFEED,
            feesCollector: POLYGON_AMOY_FEES_COLLECTOR,
            automationRegistry: POLYGON_AMOY_KEEPERS_REGISTRY,
            automationRegistrar: POLYGON_AMOY_KEEPERS_REGISTRAR,
            linkToken: POLYGON_AMOY_LINK_TOKEN,
            fundingAmountForEachUpkeep: LINK_FUNDING_AMOUNT_FOR_EACH_UPKEEP,
            functionsRouter: POLYGON_AMOY_FUNCIONS_ROUTER,
            donId: POLYGON_AMOY_DON_ID,
            gasLimit: POLYGON_AMOY_GAS_LIMIT,
            signer: POLYGON_AMOY_SIGNER
        });
    }

    function getAnvilConfig() internal  returns (NetworkConfig memory) {
        if(address(mockUsdc) == address(0)) {
            mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        }
      
        if(address(mockUsdcPriceFeed) == address(0)) {
            mockUsdcPriceFeed = new MockV3Aggregator(
                PRICE_FEED_DECIMALS, 1 * 10 ** PRICE_FEED_DECIMALS); // 1USDC = 1USD
        }

        anvilFeeCollector = makeAddr("feeCollector");

        if(address(mockLinkToken) == address(0)) {
            mockLinkToken = new MockERC20("Mock LINK", "mLINK", 18);
        }

        if(address(mockFunctionsRouter) == address(0)) {
            mockFunctionsRouter = new MockFunctionsRouter();
        }

        anvilRegistryMock = makeAddr('registryMock');
        anvilRegistrarMock = makeAddr('registrarMock');
        
        return NetworkConfig({
            name: BASE_TOKEN_NAME,
            symbol: BASE_TOKEN_SYMBOL,
            decimals: BASE_TOKEN_DECIMALS,
            apiUpdateInterval: API_UPDATE_INTERVAL,
            usdcAddress: address(mockUsdc),
            usdcPriceFeedAddress: address(mockUsdcPriceFeed),
            feesCollector: anvilFeeCollector,
            automationRegistry: anvilRegistryMock,
            automationRegistrar: anvilRegistrarMock,
            linkToken: address(mockLinkToken),
            fundingAmountForEachUpkeep: LINK_FUNDING_AMOUNT_FOR_EACH_UPKEEP,
            functionsRouter: address(mockFunctionsRouter),
            donId: 0, // @audit-issue verificare mock gestisce don id
            gasLimit: ANVIL_GAS_LIMIT,
            signer: ANVIL_SIGNER
        });
    }

    function getMocks() public view returns (MockERC20, MockV3Aggregator, MockFunctionsRouter) {
        return (mockUsdc, mockUsdcPriceFeed, mockFunctionsRouter);
    }

    function getForwarderFromUpkeepId(uint256 _upkeepId) public view returns (address) {
        if (block.chainid != ANVIL_CHAIN_ID) {
            IKeeperRegistryMaster registry = IKeeperRegistryMaster(activeNetworkConfig.automationRegistry);
            return registry.getForwarder(_upkeepId);
        } else {
            return address(mockFunctionsRouter);
        }
    }

    /**
     * @notice Returns the Chainlink Automation Registrar address for current chain
     * @dev Returns address(0) for chains without Chainlink Automation support (like Anvil)
     * @return address Chainlink Automation Registrar address
     */
    function getAutomationRegistrar() public view returns (address) {
        if (block.chainid != ANVIL_CHAIN_ID) {
            return activeNetworkConfig.automationRegistrar;
        } else {
            return registrarMock;
        }
    }

    /**
     * @notice Returns the Chainlink Automation Registry address for current chain
     * @dev Returns address(0) for chains without Chainlink Automation support (like Anvil)
     * @return address Chainlink Automation Registry address
     */
    function getAutomationRegistry() public view returns (address) {
        if (block.chainid != ANVIL_CHAIN_ID) {
            return activeNetworkConfig.automationRegistry;
        } else {
            return registryMock;
        }
    }
}