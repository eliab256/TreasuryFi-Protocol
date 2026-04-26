//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IReservesOracle {
    // Errors
    error ReservesOracle__ZeroAddress();
    error ReservesOracle__DataIsStale();
    error ReservesOracle__InvalidSlot();
    error ReservesOracle__IncompleteResponse(uint256 length);
    error ReservesOracle__InvalidSignature(address recovered);

    // Events
    event NavUpdated(
        uint256 twoYearNav,
        uint256 fiveYearNav,
        uint256 tenYearNav,
        uint256 thirtyYearNav,
        uint256 timestamp
    );
    event NavUpdateFailed(bytes err);

    // Actions (onlyRole UPDATER_ROLE)
    function updateNav(bytes memory response, bytes memory err) external;

    // Getters
    function getNav(uint256 slot) external view returns (uint256);
    function isStale() external view returns (bool);
    function getLastUpdatedTimestamp() external view returns (uint256);
    function getFunctionsConsumer() external view returns (address);
    function getReservesSigner() external view returns (address);
    function getDecimals() external view returns (uint8);
}
