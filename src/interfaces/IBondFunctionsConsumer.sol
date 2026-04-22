//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BondYieldsResponse} from "../types.sol";

interface IBondFunctionsConsumer {
    function getLastRequestId() external view returns (bytes32);
    function getLastResponse() external view returns (bytes memory);
    function getLastError() external view returns (bytes memory);
    function getBondYieldsResponse()
        external
        view
        returns (BondYieldsResponse memory);
    function getSubscriptionId() external view returns (uint64);
    function getGasLimit() external view returns (uint32);
    function getDonID() external view returns (bytes32);
    function getSource() external view returns (string memory);
    function sendRequest(
        uint64 subscriptionId,
        string[] calldata args
    ) external returns (bytes32 requestId);
}
