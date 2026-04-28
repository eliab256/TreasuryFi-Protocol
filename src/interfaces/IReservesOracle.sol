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
        uint256 timestamp
    );
    event UsdValueUpdateFailed(bytes err);

    // Actions (onlyRole UPDATER_ROLE)
    function updateUsdValue(bytes memory response, bytes memory err) external;

    // Getters
    function getUsdValue(uint256 slot) external view returns (uint256);
    function isStale() external view returns (bool);
    function getLastUpdatedTimestamp() external view returns (uint256);
    function getFunctionsConsumer() external view returns (address);
    function getReservesSigner() external view returns (address);
    function getDecimals() external view returns (uint8);
}
