//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct BondYieldsResponse {
    uint256 twoYearYield; // 1% = 10000, 4.5% = 45000 (basis points x 100)
    uint256 fiveYearYield;
    uint256 tenYearYield;
    uint256 thirtyYearYield;
    uint256 timestamp;
}

struct ReservesResponse {
    // Bond buckets mark-to-market of bond for each slot (8 decimals)
    uint256 twoYearUsdBondsValue;
    uint256 fiveYearUsdBondsValue;
    uint256 tenYearUsdBondsValue;
    uint256 thirtyYearUsdBondsValue;
    // Cash buckets mark-to-market of cash for each slot (8 decimals)
    uint256 twoYearUsdCashValue;
    uint256 fiveYearUsdCashValue;
    uint256 tenYearUsdCashValue;
    uint256 thirtyYearUsdCashValue;
    // Aggregated values
    uint256 cashBufferUsdTotalValue;  // sum of the 4 cash buckets (8 decimals)
    uint256 totalUsdBondsValue;       // sum of the 4 bond buckets only (8 decimals)
    uint256 totalUsdPortfolioValue;   // totalUsdBondsValue + cashBufferUsdTotalValue (8 decimals)
    // Timestamp of the last update, used to determine data staleness
    uint256 timestamp;
}

/**
 * @notice Stores position-specific data for each tokenId, captured at mint time.
 *
 * @param entryYield         The Treasury yield for this slot at mint time, in basis points x 100 (e.g. 45000 = 4.50%).
 *                           Used as y_entry in the NAV formula: NAV = par × [1 - D_mod × (y_current - y_entry)].
 *                           Sourced from BondOracle at mint time.
 *
 * @param entryNAV           The NAV per unit at mint time, used to calculate how many units the user received
 *                           for their USDC deposit: valueToMint = (usdcNet * PAR) / entryNAV.
 *                           Stored to allow exact payout reconstruction and audit trail.
 *
 * @param mintTimestamp      The UNIX timestamp when the position was opened.
 *                           Used to:
 *                           - enforce the slot lock period (mint + lockPeriod > block.timestamp → early redeem fee)
 *                           - calculate elapsed time for yield accrual in claimYield()
 *
 * @param lastClaimTimestamp The UNIX timestamp of the last yield claim, used to calculate claimable yield since last claim.
 *                           Used to ensure that yield is only claimable once per claim period and to calculate the correct
 *                           amount of yield to transfer to the user on each claim.
 */
struct PositionData {
    uint256 entryYield;      // basis points x 100, e.g. 45000 = 4.50%
    uint256 entryNAV;        // NAV per unit at mint, same decimals as PAR_VALUE
    uint256 mintTimestamp;   // block.timestamp at mint
    uint256 lastClaimTimestamp; // block.timestamp of the last yield claim, used to calculate claimable yield since last claim
}

/**
 * @notice Stores risk parameters for each slot, which can be updated by the RiskManager.
 *
 * @param reserveBuffer           The percentage of overcollateralization required for the slot, expressed as a percentage 
 *                                with base 100 (e.g. 110 means 110% collateralization). This parameter is used to calculate the 
 *                                required collateralization for positions in this slot and to trigger liquidations if the 
 *                                collateralization falls below this threshold.
 *
 * @param maxDailyRedeem          The maximum volume of USDC that can be redeemed from this slot in a single day. 
 *                                This parameter is used to limit the amount of liquidity that can be withdrawn from the
 *                                slot on a daily basis, helping to manage liquidity risk and prevent large sudden outflows.
 *
 * @param redeemWindowOpen        The time (in seconds from the start of the week, e.g. 0 for Sunday midnight UTC) when the 
 *                                redeem window opens. This parameter is used to define specific time windows during which 
 *                                redemptions are allowed, helping to manage liquidity and operational risk.
 *
 * @param redeemWindowDuration    The duration (in seconds) of the redeem window. This parameter, together with redeemWindowOpen, 
 *                                defines the time periods during which users can redeem their positions, allowing the protocol 
 *                                to manage liquidity and operational risk more effectively.      
 */
struct SlotRiskParams {
    uint256 reserveBuffer;        // % overcollateral (es. 110 = 110%), base 100
    uint256 maxDailyRedeem;       // cap volume redeem giornaliero per slot
    uint256 redeemWindowOpen;     // secondi dall'inizio settimana (V1 stub = 0)
    uint256 redeemWindowDuration; // durata finestra in secondi (V1 stub = 0)
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
