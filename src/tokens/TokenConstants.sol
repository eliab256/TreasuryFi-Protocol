//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TokenConstants {
    uint256 internal constant SLOT_2Y  = 1;
    uint256 internal constant SLOT_5Y  = 2;
    uint256 internal constant SLOT_10Y = 3;
    uint256 internal constant SLOT_30Y = 4;

    uint256 internal constant PENALTY_PERIOD_2Y = 30 days;
    uint256 internal constant PENALTY_PERIOD_5Y = 60 days;
    uint256 internal constant PENALTY_PERIOD_10Y = 90 days;
    uint256 internal constant PENALTY_PERIOD_30Y = 180 days;

    uint256 internal constant PERCENTAGE_PRECISION = 10000;
    uint256 internal constant MAX_PERCENTAGE = 100 * PERCENTAGE_PRECISION; // 100% in percentage precision



    /**
     * @dev The maximum delay for USDC price feed updates, in seconds.
     * @dev USDC pricefeed can be updated less frequently than the assets in the index, so we allow a longer delay for it.
     */
    uint256 public constant MAX_USDC_DELAY = 25 hours;
}