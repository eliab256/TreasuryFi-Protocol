//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUsdcUsdConverter {

    // --- Errors ---
    error UsdcUsdConverter__UsdcPriceFeedNotAvailable();
    error UsdcUsdConverter__UsdcPriceFeedRoundStale();
    error UsdcUsdConverter__UsdcPriceIsStale();

    // --- Functions ---
    function getUsdc() external view returns (address);
    function getUsdcPriceFeed() external view returns (address);
    function getUsdcDecimals() external view returns (uint8);
    function getUsdcPriceFeedDecimals() external view returns (uint8);
}