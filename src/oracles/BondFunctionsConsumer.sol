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
    error BondFunctionsConsumer__InvalidAddress();
    error BondFunctionsConsumer__InvalidResponseLength();
    using FunctionsRequest for FunctionsRequest.Request;

    /// @dev BondAutomation (chainlink automation + manual trigger from admin if grace pariod passed)
    bytes32 public constant AUTOMATION_ROLE = keccak256("AUTOMATION_ROLE");

    uint32 internal immutable i_gasLimit;
    bytes32 internal immutable i_donID;
    address internal immutable i_bondOracle;

    bytes32 internal s_lastRequestId;
    bytes internal s_lastResponse;
    bytes internal s_lastError;
    uint64 internal s_subscriptionId;

    /**
     * @notice The JavaScript source code for the Chainlink Functions request.
     *         It fetches the latest bond yields from the FRED API for different maturities.
     *         The yields are returned in basis points (BPS) and the timestamp of the latest observation.
     */
    string internal constant source =
        'const series=["DGS2","DGS5","DGS10","DGS30"];'
        "const res=await Promise.all(series.map(id=>Functions.makeHttpRequest({url:`https://api.stlouisfed.org/fred/series/observations?series_id=${id}&api_key=${secrets.FRED_API_KEY}&file_type=json&limit=1`})));"
        "const vals=[];"
        "const ts=[];"
        "for(let i=0;i<res.length;i++){"
        "const o=res[i].data.observations[0];"
        "vals.push(Math.round(parseFloat(o.value)*10000));"
        "ts.push(Math.floor(new Date(o.date).getTime()/1000));"
        "}"
        "const timestamp=Math.min(...ts);"
        "return Functions.encodeAbiParameters(['uint256[]','uint256'],[vals,timestamp]);";

    constructor(
        address _router,
        bytes32 _donID,
        uint32 _gasLimit,
        address _bondOracle,
        address _admin
    ) FunctionsClient(_router) {
        if(_router == address(0) || _bondOracle == address(0) || _admin == address(0)) {
            revert BondFunctionsConsumer__InvalidAddress();
        }
        i_donID = _donID;
        i_gasLimit = _gasLimit;
        i_bondOracle = _bondOracle;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function setAutomationContract(address _automationContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(_automationContract == address(0)) {
            revert BondFunctionsConsumer__InvalidAddress();
        }
        grantRole(AUTOMATION_ROLE, _automationContract);
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function setSubscriptionId(uint64 subscriptionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(subscriptionId == 0) revert BondFunctionsConsumer__InvalidSubscriptionId();
        if(s_subscriptionId != 0) revert BondFunctionsConsumer__SubscriptionIdAlreadySet();
        s_subscriptionId = subscriptionId;
        emit SubscriptionIdSet(subscriptionId);
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
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

    /**
     * @notice Internal function that fulfills the Chainlink Functions request. It validates the request ID, stores the response and error, 
     *         and updates the Bond Oracle with the new yields if the response is valid.
     * @param requestId The ID of the Chainlink Functions request being fulfilled.
     * @param response The response data from the Chainlink Functions request.
     * @param err The error data from the Chainlink Functions request, if any.
     */
    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (requestId != s_lastRequestId) revert BondFunctionsConsumer__UnexpectedRequestID(requestId);

        s_lastResponse = response;
        s_lastError = err;

        uint256 timestamp;

        if (err.length == 0) {
            (uint256[] memory values, uint256 ts) =
                abi.decode(response, (uint256[], uint256));

            if (values.length != 4) revert BondFunctionsConsumer__InvalidResponseLength();

            timestamp = ts;

            try IBondOracle(i_bondOracle).updateYields(values, ts, err) {}
            catch (bytes memory oracleErr) {
                emit OracleUpdateFailed(requestId, oracleErr);
            }
        }

        emit Response(requestId, timestamp, response, err);
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function getLastRequestId() external view returns (bytes32) {
        return s_lastRequestId;
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function getLastResponse() external view returns (bytes memory) {
        return s_lastResponse;
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function getLastError() external view returns (bytes memory) {
        return s_lastError;
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.  
    function getSubscriptionId() external view returns (uint64) {
        return s_subscriptionId;
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function getGasLimit() external view returns (uint32) {
        return i_gasLimit;
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function getDonID() external view returns (bytes32) {
        return i_donID;
    }

    /// @dev Inherited from IBondFunctionsConsumer. See interface for details.
    function getBondOracle() external view returns (address) {
        return i_bondOracle;
    }
}