// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.t.sol";
import {IBondFunctionsConsumer} from "../../../src/interfaces/IBondFunctionsConsumer.sol";
import {IBondOracle} from "../../../src/interfaces/IBondOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract BondFunctionConsumer is BaseTest {

    function setUp() public override {
        super.setUp();  
    }

     function test_Constructor_SetsInitialState() public {
        // test immutable variable initialization

        // test initial role
    }

    function test_Constructor_RevertIfAddressZero() public {

    }

    function test_SetAutomationContract_AddressRoleAssignment() public {

    }

    function test_SetAutomationContract_RevertIfNotAdmin() public {

    }

    function test_SetAutomationContract_RevertIfZeroAddress() public {

    }

    function test_SetSubscriptionId_SetsSubscriptionId() public {

    }

    function test_SetSubscriptionId_RevertIfNotAdmin() public {

    }

    function test_SetSubscriptionId_RevertIfIdIsZero() public {

    }

    function test_SetSubscriptionId_RevertsIfAlreadySet() public {
        
    }

    // =========================================================================
    // sendRequest
    // =========================================================================

    function test_SendRequest_RevertsIfCallerLacksAutomationRole() public {}

    function test_SendRequest_SucceedsWhenCalledByAutomationContract() public {}

    function test_SendRequest_StoresLastRequestId() public {}

    function test_SendRequest_ReturnsRequestId() public {}

    // =========================================================================
    // _fulfillRequest – requestId validation
    // =========================================================================

    function test_FulfillRequest_RevertsIfRequestIdMismatch() public {}

    // =========================================================================
    // _fulfillRequest – storage
    // =========================================================================

    function test_FulfillRequest_StoresLastResponseOnSuccess() public {}

    function test_FulfillRequest_StoresLastErrorWhenErrNonEmpty() public {}

    // =========================================================================
    // _fulfillRequest – oracle interaction
    // =========================================================================
    
}