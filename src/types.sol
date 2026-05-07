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
 * @notice Stores position-specific data for each tokenId, captured at mint time.
 *
 * @param entryYield     The Treasury yield for this slot at mint time, in basis points x 100 (e.g. 45000 = 4.50%).
 *                       Used as y_entry in the NAV formula: NAV = par × [1 - D_mod × (y_current - y_entry)].
 *                       Sourced from BondOracle at mint time.
 *
 * @param entryNAV       The NAV per unit at mint time, used to calculate how many units the user received
 *                       for their USDC deposit: valueToMint = (usdcNet * PAR) / entryNAV.
 *                       Stored to allow exact payout reconstruction and audit trail.
 *
 * @param mintTimestamp  The UNIX timestamp when the position was opened.
 *                       Used to:
 *                       - enforce the slot lock period (mint + lockPeriod > block.timestamp → early redeem fee)
 *                       - calculate elapsed time for yield accrual in claimYield()
 */
struct PositionData {
    uint256 entryYield;      // basis points x 100, e.g. 45000 = 4.50%
    uint256 entryNAV;        // NAV per unit at mint, same decimals as PAR_VALUE
    uint256 mintTimestamp;   // block.timestamp at mint
    uint256 lastClaimTimestamp; // block.timestamp of the last yield claim, used to calculate claimable yield since last claim
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
    address treasury;
}
