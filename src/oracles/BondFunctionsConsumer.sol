//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBondFunctionsConsumer} from "../interfaces/IBondFunctionsConsumer.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {
    FunctionsClient
} from "@chainlink/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    FunctionsRequest
} from "@chainlink/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {BondYieldsResponse} from "../types.sol";

contract BondFunctionsConsumer is
    IBondFunctionsConsumer,
    FunctionsClient,
    Ownable
{
    using FunctionsRequest for FunctionsRequest.Request;

    // Callback gas limit
    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;
    address internal immutable i_bondOracle;

    // State variables (all internal)
    bytes32 internal s_lastRequestId;
    bytes internal s_lastResponse;
    bytes internal s_lastError;
    uint64 internal s_subscriptionId;
    address internal s_authorizedCaller; // BondAutomation contract

    // JavaScript source code
    string internal constant source =
        'const series=["DGS2","DGS5","DGS10","DGS30"];'
        "const responses=await Promise.all(series.map((id)=>Functions.makeHttpRequest({url:`https://api.stlouisfed.org/fred/series/observations?series_id=${id}&api_key=${secrets.FRED_API_KEY}&file_type=json&sort_order=desc&limit=1`})));"
        "const values=[];"
        "const timestamps=[];"
        "for(let i=0;i<responses.length;i++){"
        "const res=responses[i];"
        "if(res.error){throw Error(`Request failed for ${series[i]}`);}"
        "const obs=res.data.observations[0];"
        'if(!obs||obs.value==="."){throw Error(`Missing data for ${series[i]}`);}'
        "values.push(Math.round(parseFloat(obs.value)*100));"
        "timestamps.push(Math.floor(new Date(obs.date).getTime()/1000));"
        "}"
        "const timestamp=Math.min(...timestamps);"
        'console.log("timestamp:",timestamp);'
        'return Functions.encodeAbiParameters(["uint64[]","uint256"],[values,timestamp]);';

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor(
        address _router,
        bytes32 _donID,
        uint32 _gasLimit,
        address _bondOracle
    ) FunctionsClient(_router) Ownable(msg.sender) {
        if (_bondOracle == address(0))
            revert BondFunctionsConsumer__ZeroAddress();
        i_donID = _donID;
        i_gasLimit = _gasLimit;
        i_bondOracle = _bondOracle;
    }

    /// @notice Sets the authorized caller (BondAutomation) — only owner
    function setAuthorizedCaller(address _caller) external onlyOwner {
        if (_caller == address(0)) revert BondFunctionsConsumer__ZeroAddress();
        s_authorizedCaller = _caller;
        emit AuthorizedCallerSet(_caller);
    }

    function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        s_subscriptionId = _subscriptionId;
        emit SubscriptionIdSet(_subscriptionId);
    }

    /**
     * @notice Sends an HTTP request for character information
     * @return requestId The ID of the request
     */
    function sendRequest() external returns (bytes32 requestId) {
        if (msg.sender != s_authorizedCaller) {
            revert BondFunctionsConsumer__NotAuthorized();
        }
        if (s_subscriptionId == 0) {
            revert BondFunctionsConsumer__InvalidSubscriptionId();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code

        // Send the request and store the request ID
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            s_subscriptionId,
            i_gasLimit,
            i_donID
        );

        return s_lastRequestId;
    }

    /**
     * @notice Callback function for fulfilling a request
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     * @param err Any errors from the Functions request
     */
    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId); // Check if request IDs match
        }
        // Update the contract's state variables with the response and any errors
        s_lastResponse = response;
        s_lastError = err;

        uint256 timestampResponse = 0;

        if (err.length == 0 && response.length > 0) {
            (uint64[] memory values, uint256 ts) = abi.decode(
                response,
                (uint64[], uint256)
            );
            if (values.length < 4)
                revert BondFunctionsConsumer__IncompleteResponse(values.length);
            timestampResponse = ts;
        }

        try IBondOracle(i_bondOracle).updateYield(response, err) {
            // success
        } catch (bytes memory oracleErr) {
            emit OracleUpdateFailed(oracleErr);
        }
        // Emit an event to log the response
        emit Response(requestId, timestampResponse, response, s_lastError);
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
}
