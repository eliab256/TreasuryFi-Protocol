//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IReservesFunctionsConsumer {
    // Errors
    error ReservesFunctionsConsumer__UnexpectedRequestID(bytes32 requestId);
    error ReservesFunctionsConsumer__NotAuthorized();
    error ReservesFunctionsConsumer__InvalidSubscriptionId();
    error ReservesFunctionsConsumer__SubscriptionIdAlreadySet();
    error ReservesFunctionsConsumer__ZeroAddress();
    error ReservesFunctionsConsumer__InvalidArrayLength();

    // Events
    event SubscriptionIdSet(uint64 indexed subscriptionId);
    event Response(
        bytes32 indexed requestId,
        uint256 indexed timestamp,
        bytes response,
        bytes err
    );

    // Setters 

    /**
     * @notice Sets the subscription ID for the Chainlink Functions request.
     * @param subscriptionId The subscription ID to set.
     */
    function setSubscriptionId(uint64 subscriptionId) external;

    // Actions

    /**
     * @notice Sends a request to the Chainlink Functions oracle.
     * @return requestId The ID of the request.
     */
    function sendRequest() external returns (bytes32 requestId);

    // Getters

    /**
     * @notice Gets the last request ID.
     * @return The last request ID.
     */
    function getLastRequestId() external view returns (bytes32);

    /**
     * @notice Gets the last response from the Chainlink Functions oracle.
     * @return The last response.
     */
    function getLastResponse() external view returns (bytes memory);

    /**
     * @notice Gets the last error from the Chainlink Functions oracle.
     * @return The last error.
     */
    function getLastError() external view returns (bytes memory);

    /**
     * @notice Gets the subscription ID for the Chainlink Functions request.
     * @return The subscription ID.
     */
    function getSubscriptionId() external view returns (uint64);

    /**
     * @notice Gets the gas limit set for the Chainlink Functions request.
     * @dev This is the maximum amount of gas that the request is allowed to consume when being fulfilled by the oracle.
     * @dev Sets on constructor
     * @return The gas limit.
     */
    function getGasLimit() external view returns (uint32);

    /**
     * @notice Gets the DON ID for the Chainlink Functions request.
     * @dev Sets on constructor
     * @return The DON ID.
     */
    function getDonID() external view returns (bytes32);

    /**
     * @notice Gets the address of the Bond Oracle that this consumer interacts with.
     * @dev Sets on constructor
     * @return The address of the Bond Oracle.
     */
    function getOracle() external view returns (address);
}
