// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BondYieldsResponse, ReservesResponse} from "../../src/types.sol";

/**
 * @title OracleDataExamples
 * @notice Library of pre-built oracle response fixtures for integration tests.
 *
 * Decimal conventions (matching the protocol contracts):
 *   Yields  — basis-points × 100:  1% = 10_000  |  4.50% = 45_000
 *   Reserves — 8-decimal USD:       $1 = 1e8 = 100_000_000
 *                                   $1,000,000 = 100_000_000_000_000 = 1e14
 */
library OracleDataExamples {

    // ─────────────────────────────────────────────────────────────────────────
    // Bond Yield fixtures
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Normal upward-sloping yield curve  (2Y < 5Y < 10Y < 30Y).
     *         Represents a healthy economic environment with positive term premium.
     */
    function regularYieldsCurve() internal view returns (BondYieldsResponse memory) {
        return BondYieldsResponse({
            twoYearYield:    40_000,   // 4.00%
            fiveYearYield:   42_500,   // 4.25%
            tenYearYield:    45_000,   // 4.50%
            thirtyYearYield: 47_500,   // 4.75%
            timestamp:       block.timestamp
        });
    }

    /**
     * @notice Inverted yield curve  (2Y > 5Y > 10Y > 30Y).
     *         Short-term rates exceed long-term rates — classic recession signal.
     */
    function invertedYieldsCurve() internal view returns (BondYieldsResponse memory) {
        return BondYieldsResponse({
            twoYearYield:    55_000,   // 5.50%
            fiveYearYield:   52_500,   // 5.25%
            tenYearYield:    47_500,   // 4.75%
            thirtyYearYield: 42_500,   // 4.25%
            timestamp:       block.timestamp
        });
    }

    /**
     * @notice Yield data with a corrupted 30Y value: 2 extra decimal places
     *         (4_750_000 instead of 47_500), simulating a data-entry error.
     *         In basis-points×100 format this would read as 47_500% — clearly invalid.
     *         RiskManager validation should flag the 30Y slot as anomalous.
     */
    function yieldsDataBroken() internal view returns (BondYieldsResponse memory) {
        return BondYieldsResponse({
            twoYearYield:    40_000,       // 4.00%  — correct
            fiveYearYield:   42_500,       // 4.25%  — correct
            tenYearYield:    45_000,       // 4.50%  — correct
            thirtyYearYield: 4_750_000,    // !! should be 47_500  (×100 encoding error)
            timestamp:       block.timestamp
        });
    }

    /**
     * @notice Yield data with valid rates but an expired timestamp.
     *         Exceeds the 48-hour staleness threshold.
     *         BondOracle.getYield() / getAllYields() should revert with DataIsStale.
     */
    function yieldsDataStale() internal pure returns (BondYieldsResponse memory) {
        return BondYieldsResponse({
            twoYearYield:    40_000,
            fiveYearYield:   42_500,
            tenYearYield:    45_000,
            thirtyYearYield: 47_500,
            timestamp:       1   // Unix epoch — always beyond the 48h threshold
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reserves fixtures   (8-decimal USD:  $1 = 100_000_000 = 1e8)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Healthy, well-collateralised reserves.
     *         Cash buffer ≈ 20% of each slot — comfortable liquidity headroom.
     *
     *  Slot    Bonds ($)      Cash ($)
     *  2Y      2,000,000       400,000
     *  5Y      3,000,000       600,000
     *  10Y     3,000,000       600,000
     *  30Y     2,000,000       400,000
     *  ──────────────────────────────
     *  Total  10,000,000     2,000,000   →  portfolio $12,000,000
     */
    function normalReservesState() internal view returns (ReservesResponse memory) {
        return ReservesResponse({
            twoYearUsdBondsValue:      200_000_000_000_000,   // $2,000,000
            fiveYearUsdBondsValue:     300_000_000_000_000,   // $3,000,000
            tenYearUsdBondsValue:      300_000_000_000_000,   // $3,000,000
            thirtyYearUsdBondsValue:   200_000_000_000_000,   // $2,000,000
            twoYearUsdCashValue:        40_000_000_000_000,   // $400,000
            fiveYearUsdCashValue:       60_000_000_000_000,   // $600,000
            tenYearUsdCashValue:        60_000_000_000_000,   // $600,000
            thirtyYearUsdCashValue:     40_000_000_000_000,   // $400,000
            cashBufferUsdTotalValue:   200_000_000_000_000,   // $2,000,000
            totalUsdBondsValue:      1_000_000_000_000_000,   // $10,000,000
            totalUsdPortfolioValue:  1_200_000_000_000_000,   // $12,000,000
            timestamp:               block.timestamp
        });
    }

    /**
     * @notice Dangerously under-collateralised state: bonds near-empty, cash negligible.
     *         Total portfolio ≈ $4,200 — any redemption above this triggers insolvency.
     *
     *  Slot    Bonds ($)   Cash ($)
     *  2Y      1,000       50
     *  5Y      1,000       50
     *  10Y     1,000       50
     *  30Y     1,000       50
     *  ─────────────────────────
     *  Total   4,000       200   →  portfolio $4,200
     */
    function reservesRiskInsolvency() internal view returns (ReservesResponse memory) {
        return ReservesResponse({
            twoYearUsdBondsValue:    100_000_000_000,   // $1,000
            fiveYearUsdBondsValue:   100_000_000_000,   // $1,000
            tenYearUsdBondsValue:    100_000_000_000,   // $1,000
            thirtyYearUsdBondsValue: 100_000_000_000,   // $1,000
            twoYearUsdCashValue:       5_000_000_000,   // $50
            fiveYearUsdCashValue:      5_000_000_000,   // $50
            tenYearUsdCashValue:       5_000_000_000,   // $50
            thirtyYearUsdCashValue:    5_000_000_000,   // $50
            cashBufferUsdTotalValue:  20_000_000_000,   // $200
            totalUsdBondsValue:      400_000_000_000,   // $4,000
            totalUsdPortfolioValue:  420_000_000_000,   // $4,200
            timestamp:               block.timestamp
        });
    }

    /**
     * @notice Reserves with a corrupted 10Y bond bucket: 2 extra decimal places
     *         (30_000_000_000_000_000 instead of 300_000_000_000_000),
     *         simulating an encoding or transmission error (×100 the correct value).
     *         $300,000,000 reported instead of $3,000,000 for the 10Y slot.
     *         RiskManager validation should detect the anomalous delta and freeze that slot.
     */
    function reservesDataBroken() internal view returns (ReservesResponse memory) {
        return ReservesResponse({
            twoYearUsdBondsValue:         200_000_000_000_000,   // $2,000,000  — correct
            fiveYearUsdBondsValue:         300_000_000_000_000,   // $3,000,000  — correct
            tenYearUsdBondsValue:    30_000_000_000_000_000,      // !! $300,000,000 (×100 error, should be $3,000,000)
            thirtyYearUsdBondsValue:       200_000_000_000_000,   // $2,000,000  — correct
            twoYearUsdCashValue:            40_000_000_000_000,   // $400,000
            fiveYearUsdCashValue:           60_000_000_000_000,   // $600,000
            tenYearUsdCashValue:            60_000_000_000_000,   // $600,000
            thirtyYearUsdCashValue:         40_000_000_000_000,   // $400,000
            cashBufferUsdTotalValue:       200_000_000_000_000,   // $2,000,000  (correct slots only)
            totalUsdBondsValue:     30_700_000_000_000_000,       // inflated by corrupted 10Y
            totalUsdPortfolioValue: 30_900_000_000_000_000,       // inflated by corrupted 10Y
            timestamp:                      block.timestamp
        });
    }

    /**
     * @notice Valid reserve values with an expired timestamp.
     *         Exceeds the 48-hour staleness threshold.
     *         ReservesOracle.getAllReserves() should revert with DataIsStale.
     */
    function reservesDataStale() internal pure returns (ReservesResponse memory) {
        return ReservesResponse({
            twoYearUsdBondsValue:    200_000_000_000_000,
            fiveYearUsdBondsValue:   300_000_000_000_000,
            tenYearUsdBondsValue:    300_000_000_000_000,
            thirtyYearUsdBondsValue: 200_000_000_000_000,
            twoYearUsdCashValue:      40_000_000_000_000,
            fiveYearUsdCashValue:     60_000_000_000_000,
            tenYearUsdCashValue:      60_000_000_000_000,
            thirtyYearUsdCashValue:   40_000_000_000_000,
            cashBufferUsdTotalValue: 200_000_000_000_000,
            totalUsdBondsValue:    1_000_000_000_000_000,
            totalUsdPortfolioValue:1_200_000_000_000_000,
            timestamp:             1   // Unix epoch — always beyond the 48h threshold
        });
    }
}
