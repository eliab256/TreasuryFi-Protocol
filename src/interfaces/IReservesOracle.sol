//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IReservesOracle {
    // Errors
    error ReservesOracle__ZeroAddress();
    error ReservesOracle__DataIsStale();
    error ReservesOracle__InvalidSlot();
    error ReservesOracle__IncompleteResponse(uint256 length);
    error ReservesOracle__InvalidSignature(address recovered);
    error ReservesOracle__BucketMismatchVsTotal();

    // Events


    event UsdValueUpdated(
        uint256 twoYearUsdValue,
        uint256 fiveYearUsdValue,
        uint256 tenYearUsdValue,
        uint256 thirtyYearUsdValue,
        uint256 cashUsdValue,
        uint256 totalUsdValue,
        uint256 timestamp
    );
    event UsdValueUpdateFailed(bytes err);

    // Actions (onlyRole UPDATER_ROLE)
    function updateUsdValues(
        uint256[4] memory usdValues,
        uint256 cashUsd,
        uint256 timestamp,
        bytes memory signature,
        bytes32 hash,
        bytes memory err
    ) external;

    // Getters
    function getReserveUsdValue(uint256 slot) external view returns (uint256);
    function getTotalUsdValue() external view returns (uint256);
    function getCashBufferUsdValue() external view returns (uint256);
    function isStale() external view returns (bool);
    function getLastUpdatedTimestamp() external view returns (uint256);
    function getFunctionsConsumer() external view returns (address);
    function getReservesSigner() external view returns (address);
    function getDecimals() external view returns (uint8);
}
