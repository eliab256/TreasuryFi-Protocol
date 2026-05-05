// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";

contract ReservesFunctionsConsumer is FunctionsClient, AccessControl {
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;
    address internal immutable i_oracle;

    bytes32 internal s_lastRequestId;
    uint64 internal s_subscriptionId;

    constructor(
        address router,
        bytes32 donID,
        uint32 gasLimit,
        address oracle
    ) FunctionsClient(router) {
        i_donID = donID;
        i_gasLimit = gasLimit;
        i_oracle = oracle;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
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

    function setSubscriptionId(uint64 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_subscriptionId = id;
    }

    function sendRequest() external onlyRole(UPDATER_ROLE) returns (bytes32) {
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
        require(requestId == s_lastRequestId, "bad request");

        if (err.length > 0) return;

        (
            uint256[4] memory bond,
            uint256[4] memory cash,
            uint256 timestamp,
            bytes memory signature
        ) = abi.decode(response, (uint256[4], uint256[4], uint256, bytes));

        IReservesOracle(i_oracle).updateUsdValues(
            bond,
            cash,
            timestamp,
            signature,
            err
        );
    }

    function getLastRequestId() external view returns (bytes32) {
        return s_lastRequestId;
    }

    function getSubscriptionId() external view returns (uint64) {
        return s_subscriptionId;
    }

    function getGasLimit() external view returns (uint32) {
        return i_gasLimit;
    }

    function getDonID() external view returns (bytes32) {
        return i_donID;
    }

    function getOracle() external view returns (address) {
        return i_oracle;
    }
}
