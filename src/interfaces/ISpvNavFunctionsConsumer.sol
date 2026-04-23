//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISpvNavFunctionsConsumer {
    // Errors
    error SpvNavFunctionsConsumer__UnexpectedRequestID(bytes32 requestId);
    error SpvNavFunctionsConsumer__NotAuthorized();
    error SpvNavFunctionsConsumer__InvalidSubscriptionId();
    error SpvNavFunctionsConsumer__ZeroAddress();
    error SpvNavFunctionsConsumer__IncompleteResponse(uint256 length);

    // Events
    event AuthorizedCallerSet(address indexed caller);
    event SubscriptionIdSet(uint64 indexed subscriptionId);
    event OracleUpdateFailed(bytes err);
    event Response(
        bytes32 indexed requestId,
        uint256 indexed timestampResponse,
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
    function getSource() external view returns (string memory);
    function getAuthorizedCaller() external view returns (address);
    function getSpvNavOracle() external view returns (address);
}
