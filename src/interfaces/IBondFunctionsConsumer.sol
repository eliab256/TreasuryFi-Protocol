//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBondFunctionsConsumer {
    // Errors
    error BondFunctionsConsumer__UnexpectedRequestID(bytes32 requestId);
    error BondFunctionsConsumer__NotAuthorized();
    error BondFunctionsConsumer__InvalidSubscriptionId();
    error BondFunctionsConsumer__ZeroAddress();
    error BondFunctionsConsumer__IncompleteResponse(uint256 length);

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
    function setAuthorizedCaller(address caller) external;
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
    function getSource() external pure returns (string memory);
    function getAuthorizedCaller() external view returns (address);
    function getBondOracle() external view returns (address);
}
