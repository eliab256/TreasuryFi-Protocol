//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IReservesFunctionsConsumer {
    // Errors
    error ReservesFunctionsConsumer__UnexpectedRequestID(bytes32 requestId);
    error ReservesFunctionsConsumer__NotAuthorized();
    error ReservesFunctionsConsumer__InvalidSubscriptionId();
    error ReservesFunctionsConsumer__SubscriptionIdAlreadySet();
    error ReservesFunctionsConsumer__ZeroAddress();

    // Events
    event SubscriptionIdSet(uint64 indexed subscriptionId);
    event Response(
        bytes32 indexed requestId,
        uint256 indexed timestamp,
        bytes response,
        bytes err
    );

    // Setters 
    function setSubscriptionId(uint64 subscriptionId) external;

    // Actions
    function sendRequest() external returns (bytes32 requestId);

    // Getters
    function getLastRequestId() external view returns (bytes32);
    function getLastResponse() external view returns (bytes memory);
    function getLastError() external view returns (bytes memory);
    function getSubscriptionId() external view returns (uint64);
    function getGasLimit() external view returns (uint32);
    function getDonID() external view returns (bytes32);
    function getOracle() external view returns (address);
}
