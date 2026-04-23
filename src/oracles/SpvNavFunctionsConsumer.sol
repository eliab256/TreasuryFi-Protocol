//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    ISpvNavFunctionsConsumer
} from "../interfaces/ISpvNavFunctionsConsumer.sol";
import {ISpvNavOracle} from "../interfaces/ISpvNavOracle.sol";
import {
    FunctionsClient
} from "@chainlink/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {
    FunctionsRequest
} from "@chainlink/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SpvNavFunctionsConsumer is
    ISpvNavFunctionsConsumer,
    FunctionsClient,
    AccessControl
{
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;
    address internal immutable i_spvNavOracle;

    bytes32 internal s_lastRequestId;
    bytes internal s_lastResponse;
    bytes internal s_lastError;
    uint64 internal s_subscriptionId;
    address internal s_authorizedCaller;

    // @audit-issue modificare l'url con quello definitivo del server SPV
    string internal constant source =
        'const url = "https://your-spv.vercel.app/api/nav";'
        "const response = await Functions.makeHttpRequest({ url });"
        "const decimals = 8;"
        "if (response.error) {"
        '  throw Error("SPV fetch failed");'
        "}"
        "const data = response.data.data;"
        "const signature = response.data.signature;"
        "const encoded = Functions.encodeString(JSON.stringify(data));"
        "const hash = Functions.keccak256(encoded);"
        "return Functions.encodeAbi("
        '  ["uint256[4]", "uint256", "bytes", "bytes32"],'
        "  ["
        "    ["
        '              Math.round(data.nav_by_bucket["2Y"]  * 10 ** decimals),'
        '              Math.round(data.nav_by_bucket["5Y"]  * 10 ** decimals),'
        '              Math.round(data.nav_by_bucket["10Y"] * 10 ** decimals),'
        '              Math.round(data.nav_by_bucket["30Y"] * 10 ** decimals),'
        "    ],"
        "    data.timestamp,"
        "    signature,"
        "    hash"
        "  ]"
        ");";

    constructor(
        address _router,
        bytes32 _donID,
        uint32 _gasLimit,
        address _spvNavOracle
    ) FunctionsClient(_router)  {
        if (_spvNavOracle == address(0))
            revert SpvNavFunctionsConsumer__ZeroAddress();
        i_donID = _donID;
        i_gasLimit = _gasLimit;
        i_spvNavOracle = _spvNavOracle;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
    }

    function setSubscriptionId(uint64 _subscriptionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_subscriptionId = _subscriptionId;
        emit SubscriptionIdSet(_subscriptionId);
    }

    function sendRequest() external onlyRole(UPDATER_ROLE) returns (bytes32 requestId) {
        if (s_subscriptionId == 0)
            revert SpvNavFunctionsConsumer__InvalidSubscriptionId();

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
        if (s_lastRequestId != requestId)
            revert SpvNavFunctionsConsumer__UnexpectedRequestID(requestId);

        s_lastResponse = response;
        s_lastError = err;

        uint256 timestampResponse = 0;

        if (err.length == 0 && response.length > 0) {
            (uint256[4] memory navs, uint256 ts, , ) = abi.decode(
                response,
                (uint256[4], uint256, bytes, bytes32)
            );
            if (navs.length < 4)
                revert SpvNavFunctionsConsumer__IncompleteResponse(navs.length);
            timestampResponse = ts;
        }

        try ISpvNavOracle(i_spvNavOracle).updateNav(response, err) {
            // success
        } catch (bytes memory oracleErr) {
            emit OracleUpdateFailed(oracleErr);
        }
        emit Response(requestId, timestampResponse, response, err);
    }

    // --- Getters ---
    function getLastRequestId() external view returns (bytes32) {
        return s_lastRequestId;
    }
    function getLastResponse() external view returns (bytes memory) {
        return s_lastResponse;
    }
    function getLastError() external view returns (bytes memory) {
        return s_lastError;
    }
    function getSubscriptionId() external view returns (uint64) {
        return s_subscriptionId;
    }
    function getAuthorizedCaller() external view returns (address) {
        return s_authorizedCaller;
    }
    function getGasLimit() external view returns (uint32) {
        return i_gasLimit;
    }
    function getDonID() external view returns (bytes32) {
        return i_donID;
    }
    function getSource() external pure returns (string memory) {
        return source;
    }
    function getSpvNavOracle() external view returns (address) {
        return i_spvNavOracle;
    }
}
