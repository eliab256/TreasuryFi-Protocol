//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {ReservesResponse} from "../types.sol";

interface IReservesOracle {
    // Errors
    error ReservesOracle__ZeroAddress();
    error ReservesOracle__DataIsStale();
    error ReservesOracle__InvalidSignature(address recovered);

    // Events
    event UsdValueUpdated(
        uint256 twoYearUsdValue,
        uint256 fiveYearUsdValue,
        uint256 tenYearUsdValue,
        uint256 thirtyYearUsdValue,
        uint256 totalUsdValue,
        uint256 timestamp
    );
    event UsdValueUpdateFailed(bytes err);

    // Actions (onlyRole UPDATER_ROLE)
    function updateUsdValues(
        uint256[4] memory bond,
        uint256[4] memory cash,
        uint256 timestamp,
        bytes memory signature,
        bytes memory err
    ) external;

    // Getters
    function getAllReserves() external view returns (ReservesResponse memory);
    function getTotalUsdValue() external view returns (uint256);
    function isStale() external view returns (bool);
    function getLastUpdatedTimestamp() external view returns (uint256);
}
