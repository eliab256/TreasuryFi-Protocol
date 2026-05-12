//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TokenConstants {

    /// @dev Slot identifiers for the different bond maturities
    uint256 internal constant SLOT_2Y  = 1;
    uint256 internal constant SLOT_5Y  = 2;
    uint256 internal constant SLOT_10Y = 3;
    uint256 internal constant SLOT_30Y = 4;

    /**
    * @notice Returns the modified duration used to estimate bond price sensitivity to changes in yield.
    * @dev Modified duration measures how much a bond's price changes when its yield changes.
    * Financial interpretation:
    * - If yield increases by 1%, bond price decreases by approximately D_mod%
    * - If yield decreases by 1%, bond price increases by approximately D_mod%
    *
    * Exact formula for fixed-rate bonds:
    * D_mod = D_mac / (1 + y / n)
    * Where:
    * - D_mac = Macaulay Duration (weighted average maturity of cash flows)
    * - y     = annual yield
    * - n     = number of coupon payments per year
    *
    * Since this protocol groups bonds into fixed maturity buckets (2Y, 5Y, 10Y, 30Y), modified duration is approximated as 
    * a constant value per slot rather than being recalculated for every individual bond.
    * This approximation is used to estimate NAV changes caused by yield curve movements.
    */
    uint256 internal constant D_MOD_2Y = 19 * PERCENTAGE_PRECISION / 10;   // 1.9
    uint256 internal constant D_MOD_5Y = 45 * PERCENTAGE_PRECISION / 10;   // 4.5
    uint256 internal constant D_MOD_10Y = 85 * PERCENTAGE_PRECISION / 10;  // 8.5
    uint256 internal constant D_MOD_30Y = 18 * PERCENTAGE_PRECISION; // 18

    /// @dev Lock period during which early redemption fee applies, per slot
    uint256 internal constant PENALTY_PERIOD_2Y = 30 days;
    uint256 internal constant PENALTY_PERIOD_5Y = 60 days;
    uint256 internal constant PENALTY_PERIOD_10Y = 90 days;
    uint256 internal constant PENALTY_PERIOD_30Y = 180 days;

    /// @dev The minimum time between yield claims, during which yield can only be claimed once and is not compounded.
    uint256 internal constant LOCK_PERIOD_CLAIM_YIELD = 30 days;

    uint256 internal constant PERCENTAGE_PRECISION = 10000;
    uint256 internal constant MAX_PERCENTAGE = 100 * PERCENTAGE_PRECISION; // 100% in percentage precision

    /**
     * @dev The maximum delay for USDC price feed updates, in seconds.
     * @dev USDC pricefeed can be updated less frequently than the assets in the index, so we allow a longer delay for it.
     */
    uint256 public constant MAX_USDC_DELAY = 25 hours;
}