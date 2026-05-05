//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBondFunctionsConsumer} from "../interfaces/IBondFunctionsConsumer.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract BondFunctionsConsumer is
    IBondFunctionsConsumer,
    FunctionsClient,
    AccessControl
{
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;
    address internal immutable i_bondOracle;

    bytes32 internal s_lastRequestId;
    bytes internal s_lastResponse;
    bytes internal s_lastError;
    uint64 internal s_subscriptionId;

    string internal constant source =
        'const series=["DGS2","DGS5","DGS10","DGS30"];'
        "const res=await Promise.all(series.map(id=>Functions.makeHttpRequest({url:`https://api.stlouisfed.org/fred/series/observations?series_id=${id}&api_key=${secrets.FRED_API_KEY}&file_type=json&limit=1`})));"
        "const vals=[];"
        "const ts=[];"
        "for(let i=0;i<res.length;i++){"
        "const o=res[i].data.observations[0];"
        "vals.push(Math.round(parseFloat(o.value)*10000));" // 👈 BPS SCALE
        "ts.push(Math.floor(new Date(o.date).getTime()/1000));"
        "}"
        "const timestamp=Math.min(...ts);"
        "return Functions.encodeAbiParameters(['uint256[]','uint256'],[vals,timestamp]);";

    constructor(
        address _router,
        bytes32 _donID,
        uint32 _gasLimit,
        address _bondOracle
    ) FunctionsClient(_router) {
        i_donID = _donID;
        i_gasLimit = _gasLimit;
        i_bondOracle = _bondOracle;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
    }

    function setSubscriptionId(uint64 subscriptionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(subscriptionId == 0) revert BondFunctionsConsumer__InvalidSubscriptionId();
        if(s_subscriptionId != 0) revert BondFunctionsConsumer__SubscriptionIdAlreadySet();
        s_subscriptionId = subscriptionId;
        emit SubscriptionIdSet(subscriptionId);
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
        require(requestId == s_lastRequestId, "bad request id");

        s_lastResponse = response;
        s_lastError = err;

        uint256 timestamp;

        if (err.length == 0) {
            (uint256[] memory values, uint256 ts) =
                abi.decode(response, (uint256[], uint256));

            require(values.length == 4, "invalid length");

            timestamp = ts;

            try IBondOracle(i_bondOracle).updateYields(values, ts, err) {}
            catch {}
        }

        emit Response(requestId, timestamp, response, err);
    }

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

    function getGasLimit() external view returns (uint32) {
        return i_gasLimit;
    }

    function getDonID() external view returns (bytes32) {
        return i_donID;
    }
    function getBondOracle() external view returns (address) {
        return i_bondOracle;
    }
}