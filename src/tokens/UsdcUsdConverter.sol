//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "./TokenConstants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";


abstract contract UsdcUsdConverter {
    error UsdcUsdConverter__UsdcPriceFeedNotAvailable();
    error UsdcUsdConverter__UsdcPriceFeedRoundStale();
    error UsdcUsdConverter__UsdcPriceIsStale();

    IERC20 private immutable i_usdc;
    AggregatorV3Interface private immutable i_usdcPriceFeed;
    uint8 internal immutable i_usdcDecimals; // 6 for usdc
    uint8 internal immutable i_usdcPriceFeedDecimals; // 8 for chainlink price feed
    uint8 internal immutable i_decimalsStandard; // standard decimals for calculations

    constructor(address _usdc, address _usdcPriceFeed, uint8 _decimalsStandard) {
        i_usdc = IERC20(_usdc);
        i_usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeed);
        i_usdcDecimals = IERC20Metadata(_usdc).decimals();
        i_usdcPriceFeedDecimals = i_usdcPriceFeed.decimals();
        i_decimalsStandard = _decimalsStandard;
    }

    /**
        * @notice Converts a USDC amount into its USD value.
        * @dev Input USDC amount must use 6 decimals.
        *      Output USD amount uses 18 decimals.
        *      The price feed is expected to return a value with 8 decimals.
        * Formula:
        * usdAmount = (usdcAmount * price * usdDecimals) / (usdcDecimals * priceFeedDecimals)
        * @param usdcAmount The amount of USDC to convert (6 decimals).
        * @return usdAmount The equivalent USD value (18 decimals).
    */
    function _convertUsdcToUsd18(uint256 usdcAmount) internal view returns (uint256 usdAmount) {
        uint256 usdcPrice = _getLatestUsdcPrice();

        uint256 usdcDecimals = i_usdcDecimals; // 6 for USDC
        uint256 usdDecimals = i_decimalsStandard; // 18 for USD
        uint256 priceFeedDecimals = i_usdcPriceFeedDecimals; // 8 for price feed

        uint256 numerator = Math.mulDiv(
            usdcAmount,
            usdcPrice,
            usdcDecimals
        );

        usdAmount = Math.mulDiv(
            numerator,
            usdDecimals,
            priceFeedDecimals
        );
    }

    /**
    * @notice Converts a USD amount into its USDC equivalent.
    * @dev Input USD amount must use 18 decimals.
    *      Output USDC amount uses 6 decimals.
    *      The price feed is expected to return a value with 8 decimals.
    * Formula:
    * usdcAmount = (usdAmount * usdcDecimals * priceFeedDecimals) / (price * usdDecimals)
    * @param usdAmount The USD amount to convert (18 decimals).
    * @return usdcAmount The equivalent USDC amount (6 decimals).
    */
    function _convertUsd18ToUsdc(uint256 usdAmount) internal view returns (uint256 usdcAmount) {
        uint256 usdcPrice = _getLatestUsdcPrice();

        uint256 usdcDecimals = i_usdcDecimals; // 6 for USDC
        uint256 usdDecimals = i_decimalsStandard; // 18 for USD
        uint256 priceFeedDecimals = i_usdcPriceFeedDecimals; // 8 for price feed

        uint256 numerator = Math.mulDiv(
            usdAmount,
            usdcDecimals,
            usdDecimals
        );

        usdcAmount = Math.mulDiv(
            numerator,
            priceFeedDecimals,
            usdcPrice
        );
    }


    /**
     * @notice Converts a USD amount from 18 decimals (standard) to 8 decimals (price feed format).
     * @dev Pure decimal rescaling, no price feed involved.
     * Formula: usd8Amount = usd18Amount * priceFeedDecimals / usdDecimals
     * @param usd18Amount The USD amount (18 decimals).
     * @return usd8Amount The USD amount (8 decimals).
     */
    function _convertUsd18ToUsd8(uint256 usd18Amount) internal view returns (uint256 usd8Amount) {
        uint256 usdDecimals = i_decimalsStandard;
        uint256 priceFeedDecimals = i_usdcPriceFeedDecimals;

        usd8Amount = Math.mulDiv(usd18Amount, priceFeedDecimals, usdDecimals);
    }

    /**
     * @notice Converts a USD amount from 8 decimals (price feed format) to 18 decimals (standard).
     * @dev Pure decimal rescaling, no price feed involved.
     * Formula: usd18Amount = usd8Amount * usdDecimals / priceFeedDecimals
     * @param usd8Amount The USD amount (8 decimals).
     * @return usd18Amount The USD amount (18 decimals).
     */
    function _convertUsd8ToUsd18(uint256 usd8Amount) internal view returns (uint256 usd18Amount) {
        uint256 usdDecimals = i_decimalsStandard;
        uint256 priceFeedDecimals = i_usdcPriceFeedDecimals;

        usd18Amount = Math.mulDiv(usd8Amount, usdDecimals, priceFeedDecimals);
    }

    /**
     * @notice Converts a USDC amount into its USD value (8 decimals / price feed format).
     * @dev Input USDC amount must use 6 decimals.
     *      Output USD amount uses 8 decimals (price feed format).
     * Formula: usd8Amount = usdcAmount * price / usdcDecimals
     * @param usdcAmount The amount of USDC to convert (6 decimals).
     * @return usd8Amount The equivalent USD value (8 decimals).
     */
    function _convertUsdcToUsd8(uint256 usdcAmount) internal view returns (uint256 usd8Amount) {
        uint256 usdcPrice = _getLatestUsdcPrice();
        uint256 usdcDecimals = i_usdcDecimals;

        usd8Amount = Math.mulDiv(usdcAmount, usdcPrice, usdcDecimals);
    }

    /**
     * @notice Converts a USD amount (8 decimals / price feed format) into its USDC equivalent.
     * @dev Input USD amount must use 8 decimals.
     *      Output USDC amount uses 6 decimals.
     * Formula: usdcAmount = usd8Amount * usdcDecimals / price
     * @param usd8Amount The USD amount to convert (8 decimals).
     * @return usdcAmount The equivalent USDC amount (6 decimals).
     */
    function _convertUsd8ToUsdc(uint256 usd8Amount) internal view returns (uint256 usdcAmount) {
        uint256 usdcPrice = _getLatestUsdcPrice();
        uint256 usdcDecimals = i_usdcDecimals;

        usdcAmount = Math.mulDiv(usd8Amount, usdcDecimals, usdcPrice);
    }

    function _getLatestUsdcPrice() internal view returns (uint256) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = i_usdcPriceFeed.latestRoundData();

        if (answer <= 0) revert UsdcUsdConverter__UsdcPriceFeedNotAvailable();
        if (answeredInRound < roundId) revert UsdcUsdConverter__UsdcPriceFeedRoundStale();
        if (block.timestamp - updatedAt > C.MAX_USDC_DELAY) revert UsdcUsdConverter__UsdcPriceIsStale();
        
        return (uint256(answer));
    }
}