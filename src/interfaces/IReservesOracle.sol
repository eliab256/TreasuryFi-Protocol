//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {ReservesResponse} from "../types.sol";

interface IReservesOracle {
    // Errors
    error ReservesOracle__ZeroAddress();
    error ReservesOracle__DataIsStale();
    error ReservesOracle__InvalidSignature(address recovered);
    error ReservesOracle__ConsumerAlreadySet();

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
    event ConsumerSet(address indexed consumer);

    // Actions 

    /**
     * @notice Updates the USD values for bonds and cash.
     * @param bond An array containing the USD values of bonds.
     * @param cash An array containing the USD values of cash buffers.
     * @param timestamp The timestamp of when the data was fetched.
     * @param signature The signature of the data.
     * @param err The error message if the update failed.
     */
    function updateUsdValues(
        uint256[4] memory bond,
        uint256[4] memory cash,
        uint256 timestamp,
        bytes memory signature,
        bytes memory err
    ) external;

    // Getters

    /**
     * @notice Gets the USD values for all reserves and liquidity buffers for each slot.
     * @return A ReservesResponse struct containing the USD values and timestamp.
     */
    function getAllReserves() external view returns (ReservesResponse memory);

    /**
     * @notice Gets the total USD value of the portfolio.
     * @return The total USD value.
     */
    function getTotalUsdValue() external view returns (uint256);

    /**
     * @notice Checks if the reserve data is stale.
     * @return True if the data is stale, false otherwise.
    */
    function isStale() external view returns (bool);
    
    /**
     * @notice Gets the timestamp of the last update.
     * @return The timestamp of the last update.
     */
    function getLastUpdatedTimestamp() external view returns (uint256);

    /**
     * @notice Sets the FunctionsConsumer contract address (one-shot, post-deploy).
     * @dev Can only be called once by DEFAULT_ADMIN_ROLE.
     * @param _consumer The address of the ReservesFunctionsConsumer contract.
     */
    function setFunctionsConsumer(address _consumer) external;

    /**
     * @notice Returns the address of the FunctionsConsumer contract authorized to update reserves.
     * @return The address of the FunctionsConsumer contract.
     */
    function getFunctionsConsumer() external view returns (address);
}
