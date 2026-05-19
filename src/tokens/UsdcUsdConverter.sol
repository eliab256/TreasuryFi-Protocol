//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "./TokenConstants.sol";
import {IUsdcUsdConverter} from "../interfaces/IUsdcUsdConverter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract UsdcUsdConverter is IUsdcUsdConverter {

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

        uint256 numerator = Math.mulDiv(
            usdcAmount,
            usdcPrice,
            10 ** i_usdcDecimals
        );

        usdAmount = Math.mulDiv(
            numerator,
            10 ** i_decimalsStandard,
            10 ** i_usdcPriceFeedDecimals
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
            10 ** usdcDecimals,
            10 ** usdDecimals
        );

        usdcAmount = Math.mulDiv(
            numerator,
            10 ** priceFeedDecimals,
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

        usd8Amount = Math.mulDiv(usd18Amount, 10 ** priceFeedDecimals, 10 ** usdDecimals);
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

        usd18Amount = Math.mulDiv(usd8Amount, 10 ** usdDecimals, 10 ** priceFeedDecimals);
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

        usd8Amount = Math.mulDiv(usdcAmount, usdcPrice, 10 ** i_usdcDecimals);
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

        usdcAmount = Math.mulDiv(usd8Amount, 10 ** usdcDecimals, usdcPrice);
    }

    /**
     * @notice Converts multiple USD (18 decimals) amounts to USDC with a single price feed call.
     * @dev Recommended for internal use: passes arrays by memory pointer, no abi.encode/decode overhead.
     *      Calls the price feed exactly once regardless of array length.
     * @param _usdAmounts Array of USD amounts to convert (18 decimals each).
     * @return usdcAmounts Array of equivalent USDC amounts (6 decimals each), same length as input.
     */
    function _convertMultipleUsd18ToUsdcArray(
        uint256[] memory _usdAmounts
    ) internal view returns (uint256[] memory usdcAmounts) {
        uint256 usdcPrice = _getLatestUsdcPrice();
        uint256 len = _usdAmounts.length;
        usdcAmounts = new uint256[](len);

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                uint256 numerator = Math.mulDiv(_usdAmounts[i], 10 ** i_usdcDecimals, 10 ** i_decimalsStandard);
                usdcAmounts[i] = Math.mulDiv(numerator, 10 ** i_usdcPriceFeedDecimals, usdcPrice);
            }
        }
    }

    /**
     * @notice Converts multiple USDC amounts to USD (18 decimals) with a single price feed call.
     * @dev Uses bytes encoding as requested. For internal-only usage prefer
     *      _convertMultipleUsdcToUsd18Array which avoids the abi.encode/decode overhead.
     *      Input bytes must be abi-encoded as a packed sequence of _numberOfConversion uint256 values
     *      (i.e. the raw word-by-word layout written directly, no dynamic-array length prefix).
     *      Output bytes is abi.encode(uint256[]) and must be decoded by the caller accordingly.
     * @param _numberOfConversion Number of values packed in _valuesToConvert.
     * @param _valuesToConvert Packed USDC amounts — each slot is 32 bytes, no length prefix.
     * @return convertedValues abi.encode(uint256[]) of USD18 amounts.
     */
    function _convertMultipleUsdcToUsd18(
        uint256 _numberOfConversion,
        bytes memory _valuesToConvert
    ) internal view returns (bytes memory convertedValues) {
        uint256 usdcPrice = _getLatestUsdcPrice();

        uint256[] memory results = new uint256[](_numberOfConversion);

        unchecked {
            for (uint256 i = 0; i < _numberOfConversion; i++) {
                uint256 usdcAmount;
                assembly ("memory-safe") {
                    // _valuesToConvert starts with a 32-byte length field (bytes memory layout).
                    // Skip it with add(..., 0x20), then read the i-th 32-byte slot.
                    usdcAmount := mload(add(add(_valuesToConvert, 0x20), mul(i, 0x20)))
                }
                uint256 numerator = Math.mulDiv(usdcAmount, usdcPrice, 10 ** i_usdcDecimals);
                results[i] = Math.mulDiv(numerator, 10 ** i_decimalsStandard, 10 ** i_usdcPriceFeedDecimals);
            }
        }

        convertedValues = abi.encode(results);
    }

    /**
     * @notice Gas-efficient alternative to _convertMultipleUsdcToUsd18.
     * @dev Recommended for internal use: passes arrays by memory pointer, no abi.encode/decode overhead.
     *      Calls the price feed exactly once regardless of array length.
     * @param _usdcAmounts Array of USDC amounts to convert (6 decimals each).
     * @return usdAmounts Array of equivalent USD values (18 decimals each), same length as input.
     */
    function _convertMultipleUsdcToUsd18Array(
        uint256[] memory _usdcAmounts
    ) internal view returns (uint256[] memory usdAmounts) {
        uint256 usdcPrice = _getLatestUsdcPrice();
        uint256 len = _usdcAmounts.length;
        usdAmounts = new uint256[](len);

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                uint256 numerator = Math.mulDiv(_usdcAmounts[i], usdcPrice, 10 ** i_usdcDecimals);
                usdAmounts[i] = Math.mulDiv(numerator, 10 ** i_decimalsStandard, 10 ** i_usdcPriceFeedDecimals);
            }
        }
    }

    /**
     * @notice Retrieves the latest USDC price from the price feed.
     * @dev Reverts if the price feed returns a non-positive value, if the round is stale, or if the price is outdated.
     * @return The latest USDC price.
     */
    function _getLatestUsdcPrice() private view returns (uint256) {
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

    function _getUsdc() internal view returns (address) {
        return address(i_usdc);
    }

    function _getUsdUsdcPriceFeed() internal view returns (address) {
        return address(i_usdcPriceFeed);
    }
}