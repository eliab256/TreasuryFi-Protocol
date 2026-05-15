//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17 <0.9.0;

abstract contract CodeConstants {
    // Chain IDs
    uint256 internal constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant POLYGON_AMOY_CHAIN_ID = 80001;
    uint256 internal constant ANVIL_CHAIN_ID = 31337;

    // T-ReX Identity Registry claim topics and schemes
    uint256 internal constant KYC_CLAIM_TOPIC = 1;
    uint256 internal constant AML_CLAIM_TOPIC = 2;

    uint256 internal constant ECDSA_SCHEME = 1;
    uint16 internal constant DEFAULT_COUNTRY = 380; // IT

    bytes internal constant DEFAULT_KYC_DATA = abi.encodePacked("KYC_APPROVED");

    // Chainlink Automation Registry addresses
    address public constant ETH_SEPOLIA_KEEPERS_REGISTRY = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;
    address public constant POLYGON_AMOY_KEEPERS_REGISTRY = 0x08a8eea76D2395807Ce7D1FC942382515469cCA1;

    //Chainlink Automation Registrar address
    address public constant ETH_SEPOLIA_KEEPERS_REGISTRAR = 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976;
    address public constant POLYGON_AMOY_KEEPERS_REGISTRAR = address(0); // @audit-issue definire indirizzo del registrar per Polygon Amoy, eventualmente tramite script di deploy o variabile d'ambiente;

    //LINK Token addresses
    address public constant ETH_SEPOLIA_LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address public constant POLYGON_AMOY_LINK_TOKEN = 0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904;

    //Gas Limits
    uint32 public constant ETH_SEPOLIA_GAS_LIMIT = 2_000_000;
    uint32 public constant POLYGON_AMOY_GAS_LIMIT = 2_000_000; // @audit-issue verificare valore appropriato
    uint32 public constant ANVIL_GAS_LIMIT = 2_000_000;

    //Chainlink Functions Router addresses
    address public constant ETH_SEPOLIA_FUNCIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    address public constant POLYGON_AMOY_FUNCIONS_ROUTER = 0xC22a79eBA640940ABB6dF0f7982cc119578E11De;

    //Chainlink DON IDs
    uint256 public constant ETH_SEPOLIA_DON_ID = 
     0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint256 public constant POLYGON_AMOY_DON_ID = 
        0x66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000;

    // USDC contract addresses
    address public constant ETH_SEPOLIA_USDC_CONTRACT = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant POLYGON_AMOY_USDC_CONTRACT = 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582;

    // USDC/USD price feed addresses
    address public constant ETH_SEPOLIA_USDC_PRICEFEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address public constant POLYGON_AMOY_USDC_PRICEFEED = 0x1b8739bB4CdF0089d07097A9Ae5Bd274b29C6F16;

    // Common parameters for every chain
    string internal constant BASE_TOKEN_NAME = "TreasuryFi Bond Token";
    string internal constant BASE_TOKEN_SYMBOL = "TBT";
    uint8 internal constant BASE_TOKEN_DECIMALS = 18;
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    uint256 public constant API_UPDATE_INTERVAL = 24 hours;
    uint256 public constant LINK_FUNDING_AMOUNT_FOR_EACH_UPKEEP = 5 * 10 ** 18; // 5 LINK

    // FeesCollector address
    address public constant ETH_SEPOLIA_FEES_COLLECTOR = address(0); // @audit-issue definire FeesCollector per Sepolia, eventualmente tramite script di deploy o variabile d'ambiente
    address public constant POLYGON_AMOY_FEES_COLLECTOR = address(0); // @audit-issue definire FeesCollector per Polygon Amoy

    //Signer addresses
    address public constant ETH_SEPOLIA_SIGNER = address(0); // @audit-issue definire signer per Sepolia, eventualmente tramite script di deploy o variabile d'ambiente
    address public constant POLYGON_AMOY_SIGNER = address(0);
    address public constant ANVIL_SIGNER = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720; // account 9 in Anvil default accounts

    // Deployer addresses
    address public constant ETH_SEPOLIA_DEPLOYER_ADDRESS = fromEnv("ETH_SEPOLIA_DEPLOYER_ADDRESS");
    address public constant POLYGON_AMOY_DEPLOYER_ADDRESS = fromEnv("POLYGON_AMOY_DEPLOYER_ADDRESS"); 
    address public constant ANVIL_DEPLOYER_ADDRESS = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // account 0 in Anvil default accounts

}
