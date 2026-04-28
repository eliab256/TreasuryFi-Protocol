//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBondFunctionsConsumer} from "../interfaces/IBondFunctionsConsumer.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {
    FunctionsClient
} from "@chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    FunctionsRequest
} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {BondYieldsResponse} from "../types.sol";

contract BondFunctionsConsumer is
    IBondFunctionsConsumer,
    FunctionsClient,
    AccessControl
{
    using FunctionsRequest for FunctionsRequest.Request;

    //roles
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

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
    ) FunctionsClient(_router) Ownable() {
        if (_bondOracle == address(0))
            revert BondFunctionsConsumer__ZeroAddress();
        i_donID = _donID;
        i_gasLimit = _gasLimit;
        i_bondOracle = _bondOracle;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);       
    }

    /// @notice Sets the authorized caller (BondAutomation) — only owner
    function setAuthorizedCaller(address _caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_caller == address(0)) revert BondFunctionsConsumer__ZeroAddress();
        s_authorizedCaller = _caller;
        emit AuthorizedCallerSet(_caller);
    }

    function setSubscriptionId(uint64 _subscriptionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_subscriptionId = _subscriptionId;
        emit SubscriptionIdSet(_subscriptionId);
    }

    /**
     * @notice Sends an HTTP request for character information
     * @return requestId The ID of the request
     */
    function sendRequest() external onlyRole(UPDATER_ROLE) returns (bytes32 requestId) {

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
            revert BondFunctionsConsumer__UnexpectedRequestID(requestId); // Check if request IDs match
        }
        // Update the contract's state variables with the response and any errors
        s_lastResponse = response;
        s_lastError = err;

        uint256 timestamp = 0;

        if (err.length == 0 && response.length > 0) {
            (uint64[] memory values, uint256 ts) = abi.decode(
                response,
                (uint64[], uint256)
            );
            if (values.length < 4)
                revert BondFunctionsConsumer__IncompleteResponse(values.length);
            timestamp = ts;
        }

        try IBondOracle(i_bondOracle).updateYields(response, err) {} catch (bytes memory oracleErr) {
            emit OracleUpdateFailed(oracleErr);
        } else {
            try
                IBondOracle(i_bondOracle).updateYields(
                    [uint256(0), 0, 0, 0],
                    0,
                    err
                )
            {} catch {}
        }

        // Emit an event to log the response
        emit Response(requestId, timestamp, response, err);
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
