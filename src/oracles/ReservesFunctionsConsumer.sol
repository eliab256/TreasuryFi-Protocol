// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {IReservesFunctionsConsumer} from "../interfaces/IReservesFunctionsConsumer.sol";

contract ReservesFunctionsConsumer is IReservesFunctionsConsumer, FunctionsClient, AccessControl {

    
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public constant AUTOMATION_ROLE = keccak256("AUTOMATION_ROLE");

    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;
    address internal immutable i_oracle;

    bytes32 internal s_lastRequestId;
    bytes internal s_lastResponse;
    bytes internal s_lastError;
    uint64 internal s_subscriptionId;

    constructor(
        address router,
        bytes32 donID,
        uint32 gasLimit,
        address oracle,
        address automationContract
    ) FunctionsClient(router) {
        if (oracle == address(0) || automationContract == address(0)) revert ReservesFunctionsConsumer__ZeroAddress();
        i_donID = donID;
        i_gasLimit = gasLimit;
        i_oracle = oracle;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AUTOMATION_ROLE, automationContract);
    }

    // ----------------------------
    // JS SOURCE (NORMALIZATION LAYER)
    // ----------------------------
    string internal constant source =
        'const url="https://your-spv.vercel.app/api/usdValues";'
        "const r=await Functions.makeHttpRequest({url});"
        "if(r.error)throw Error('SPV fail');"
        "const d=r.data.data;"
        "const sig=r.data.signature;"
        "function c(v){const p=v.split('.');return BigInt(p[0]+((p[1]||'00')+'00').slice(0,2));}"
        "const bond=["
        "c(d.usdValue_by_bucket['2Y']),"
        "c(d.usdValue_by_bucket['5Y']),"
        "c(d.usdValue_by_bucket['10Y']),"
        "c(d.usdValue_by_bucket['30Y'])"
        "];"
        "const cash=["
        "c(d.cash_usd_by_bucket['2Y']),"
        "c(d.cash_usd_by_bucket['5Y']),"
        "c(d.cash_usd_by_bucket['10Y']),"
        "c(d.cash_usd_by_bucket['30Y'])"
        "];"
        "return Functions.encodeAbi(['uint256[4]','uint256[4]','uint256','bytes'],[bond,cash,d.timestamp,sig]);";

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function setSubscriptionId(uint64 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id == 0) revert ReservesFunctionsConsumer__InvalidSubscriptionId();
        if (s_subscriptionId != 0) revert ReservesFunctionsConsumer__SubscriptionIdAlreadySet();
        s_subscriptionId = id;
        emit SubscriptionIdSet(id);
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function sendRequest() external onlyRole(AUTOMATION_ROLE) returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);

        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            s_subscriptionId,
            i_gasLimit,
            i_donID
        );

        return s_lastRequestId;
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        // 1. Validate the request ID, if doesn't match the last request ID, revert with an error
        if (requestId != s_lastRequestId) revert ReservesFunctionsConsumer__UnexpectedRequestID(requestId);

        s_lastResponse = response;
        s_lastError = err;

        uint256 timestamp;

        // 2. If there is no error, decode the response and update the oracle with the new values
        if (err.length == 0) {
            (
                uint256[4] memory bond,
                uint256[4] memory cash,
                uint256 ts,
                bytes memory signature
            ) = abi.decode(response, (uint256[4], uint256[4], uint256, bytes));

            // 3. Validate the response format, if the bond or cash arrays don't have exactly 4 elements, 
            //    revert with an error
            if (bond.length != 4 || cash.length != 4) revert ReservesFunctionsConsumer__InvalidArrayLength();

            timestamp = ts;

            // 4. Try to call the oracle's update function with the new values, 
            //    if it reverts, catch the error and continue without reverting
            try IReservesOracle(i_oracle).updateUsdValues(
                bond,
                cash,
                ts,
                signature,
                err
            ) {}
            catch (bytes memory oracleErr) {
                emit OracleUpdateFailed(requestId, oracleErr);
            }
        }

        emit Response(requestId, timestamp, response, err);
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getLastRequestId() external view returns (bytes32) {
        return s_lastRequestId;
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getLastResponse() external view returns (bytes memory) {
        return s_lastResponse;
    }
    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getLastError() external view returns (bytes memory) {
        return s_lastError;
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getSubscriptionId() external view returns (uint64) {
        return s_subscriptionId;
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getGasLimit() external view returns (uint32) {
        return i_gasLimit;
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getDonID() external view returns (bytes32) {
        return i_donID;
    }

    /// @dev Inherited from IReservesFunctionsConsumer. See interface for details.
    function getOracle() external view returns (address) {
        return i_oracle;
    }
}
