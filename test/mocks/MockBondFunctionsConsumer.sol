// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockBondFunctionsConsumer {
    uint256 public sendRequestCallCount;

    function sendRequest() external returns (bytes32) {
        sendRequestCallCount++;
        return bytes32(sendRequestCallCount);
    }
}
