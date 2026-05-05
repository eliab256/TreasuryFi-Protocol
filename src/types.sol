//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct BondYieldsResponse {
    uint256 twoYearYield;
    uint256 fiveYearYield;
    uint256 tenYearYield;
    uint256 thirtyYearYield;
    uint256 timestamp;
}

struct ReservesResponse {
    // Bond buckets — mark-to-market of bond for each slot (8 decimals)
    uint256 twoYearUsdBondsValue;
    uint256 fiveYearUsdBondsValue;
    uint256 tenYearUsdBondsValue;
    uint256 thirtyYearUsdBondsValue;
    // Cash buckets — available liquidity per slot (8 decimals)
    uint256 twoYearUsdCashValue;
    uint256 fiveYearUsdCashValue;
    uint256 tenYearUsdCashValue;
    uint256 thirtyYearUsdCashValue;
    // Aggregated values
    uint256 cashBufferUsdTotalValue; // sum of the 4 cash buckets (8 decimals)
    uint256 totalUsdBondsValue;      // sum of the 4 bond buckets (8 decimals)
    uint256 timestamp;
}

/**
    * @notice Struct to store position-specific data for each tokenId
    * - interestRate: The fixed interest rate for the position (scaled by 1e8)
    * - positionMintTimestamp: The UNIX timestamp when the position was minted 
    * - maturityTimestamp: The UNIX timestamp when the position matures
*/ 
struct PositionData {
    uint256 interestRate;
    uint256 positionMintTimestamp;
    uint256 maturityTimestamp;
}

struct TreasuryBondTokenConstructorParams {
    string name;
    string symbol;
    uint8 decimalsStandard;
    address usdcAddress;
    address usdcPriceFeedAddress;
    address identityRegistry;
    address bondAutomation;
    address reservesAutomation;
    address updateRiskManagerAutomation;
    address reservesOracle;
    address bondOracle;
    address feesCollector;
}
