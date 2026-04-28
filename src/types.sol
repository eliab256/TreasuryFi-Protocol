//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct BondYieldsResponse {
    uint64 twoYearYield;
    uint64 fiveYearYield;
    uint64 tenYearYield;
    uint64 thirtyYearYield;
    uint256 timestamp;
}

struct ReservesResponse {
    uint256 twoYearUsdValue;
    uint256 fiveYearUsdValue;
    uint256 tenYearUsdValue;
    uint256 thirtyYearUsdValue;
    uint256 cashBufferUsdValue;
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
