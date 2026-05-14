// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFunctionsConsumer {
    function handleOracleFulfillment(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external;
}

contract MockFunctionsRouter {
    error MockFunctionsRouter__InvalidRequestId();
    error MockFunctionsRouter__NoConsumerFound();

    struct RequestData {
        address consumer;
        bytes data;
        uint64 subscriptionId;
        uint32 gasLimit;
        bytes32 donId;
    }

    uint256 private s_nonce;

    mapping(bytes32 => RequestData) private s_requests;

    event RequestSent(
        bytes32 indexed requestId,
        address indexed consumer
    );

    event RequestFulfilled(
        bytes32 indexed requestId,
        bytes response,
        bytes err
    );

    /**
     * @dev Mimics Chainlink Functions router send request
     */
    function sendRequest(
        bytes calldata data,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donId
    ) external returns (bytes32 requestId) {
        requestId = keccak256(
            abi.encode(
                msg.sender,
                block.timestamp,
                s_nonce++
            )
        );

        s_requests[requestId] = RequestData({
            consumer: msg.sender,
            data: data,
            subscriptionId: subscriptionId,
            gasLimit: gasLimit,
            donId: donId
        });

        emit RequestSent(requestId, msg.sender);
    }

    /**
     * @dev Manual fulfillment used in tests.
     * You decide response + err manually.
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes calldata response,
        bytes calldata err
    ) external {
        RequestData memory request = s_requests[requestId];

        if (request.consumer == address(0)) {
            revert MockFunctionsRouter__NoConsumerFound();
        }

        IFunctionsConsumer(request.consumer)
            .handleOracleFulfillment(
                requestId,
                response,
                err
            );

        emit RequestFulfilled(
            requestId,
            response,
            err
        );
    }

    function getRequest(
        bytes32 requestId
    ) external view returns (RequestData memory) {
        if (s_requests[requestId].consumer == address(0)) {
            revert MockFunctionsRouter__InvalidRequestId();
        }

        return s_requests[requestId];
    }
}