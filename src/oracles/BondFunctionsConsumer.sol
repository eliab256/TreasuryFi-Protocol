//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBondFunctionsConsumer} from "../interfaces/IBondFunctionsConsumer.sol";
import {
    FunctionsClient
} from "@chainlink/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {
    ConfirmedOwner
} from "@chainlink/src/v0.8/shared/access/ConfirmedOwner.sol";
import {
    FunctionsRequest
} from "@chainlink/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {BondYieldsResponse} from "../types.sol";

contract BondFunctionsConsumer is
    IBondFunctionsConsumer,
    FunctionsClient,
    ConfirmedOwner
{
    using FunctionsRequest for FunctionsRequest.Request;

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    // Event to log responses
    event Response(
        bytes32 indexed requestId,
        uint64 twoYearYield,
        uint64 fiveYearYield,
        uint64 tenYearYield,
        uint64 thirtyYearYield,
        uint256 timestamp,
        bytes response,
        bytes err
    );

    // Callback gas limit
    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;

    // State variables (all internal)
    bytes32 internal s_lastRequestId;
    bytes internal s_lastResponse;
    bytes internal s_lastError;
    BondYieldsResponse internal s_bondYieldsResponse;
    uint64 internal s_subscriptionId;

    // JavaScript source code
    string internal source =
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
    function getBondYieldsResponse()
        external
        view
        returns (BondYieldsResponse memory)
    {
        return s_bondYieldsResponse;
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
    function getSource() external view returns (string memory) {
        return source;
    }

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor(
        address _router,
        bytes32 _donID,
        uint32 _gasLimit
    ) FunctionsClient(_router) ConfirmedOwner(msg.sender) {
        i_donID = _donID;
        i_gasLimit = _gasLimit;
    }

    /**
     * @notice Sends an HTTP request for character information
     * @param subscriptionId The ID for the Chainlink subscription
     * @param args The arguments to pass to the HTTP request
     * @return requestId The ID of the request
     */
    function sendRequest(
        uint64 subscriptionId,
        string[] calldata args
    ) external onlyOwner returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (args.length > 0) req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
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
        abi.decode(response, (uint64[], uint256));
        (uint64[] memory values, uint256 timestamp) = abi.decode(
            response,
            (uint64[], uint256)
        );
        s_bondYieldsResponse = BondYieldsResponse({
            twoYearYield: values[0],
            fiveYearYield: values[1],
            tenYearYield: values[2],
            thirtyYearYield: values[3],
            timestamp: timestamp
        });
        s_lastError = err;

        // Emit an event to log the response
        emit Response(
            requestId,
            s_bondYieldsResponse.twoYearYield,
            s_bondYieldsResponse.fiveYearYield,
            s_bondYieldsResponse.tenYearYield,
            s_bondYieldsResponse.thirtyYearYield,
            s_bondYieldsResponse.timestamp,
            s_lastResponse,
            s_lastError
        );
    }
}
