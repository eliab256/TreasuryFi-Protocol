// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.t.sol";
import {UpdateRiskManagerAutomation} from "../../../src/automation/UpdateRiskManagerAutomation.sol";
import {ReservesResponse, BondYieldsResponse} from "../../../src/types.sol";

contract UpdateRiskManagerAutomationTest is BaseTest {
    UpdateRiskManagerAutomation internal updateRiskManagerAutomation;

    error UpdateRiskManager__ZeroAddress();
    error UpdateRiskManager__ChainlinkForwarderAddressAlreadySet();

    function setUp() public override {
        super.setUp();
        tokenMock token = new tokenMock();
        reservesOracleMock reservesOracle = new reservesOracleMock();
        yieldsOracleMock yieldsOracle = new yieldsOracleMock();
        updateRiskManagerAutomation = new UpdateRiskManagerAutomation(
            address(token),
            address(reservesOracle),
            address(yieldsOracle),
            ADMIN
        );

     
    }

    function test_Constructor_SetsOraclesAndToken() public view {
        
    }

    function test_Constructor_GrantsDefaultAdminAndTokenRole() public view {

    }

    function test_Constructor_RevertsWhenAnyAddressIsZero() public {
        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            address(0),
            i_reservesOracle,
            i_bondYieldsOracle,
            ADMIN
        );

        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            i_tokenContract,
            address(0),
            i_bondYieldsOracle,
            ADMIN
        );

        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            i_tokenContract,
            i_reservesOracle,
            address(0),
            ADMIN
        );

        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        new UpdateRiskManagerAutomation(
            i_tokenContract,
            i_reservesOracle,
            i_bondYieldsOracle,
            address(0)
        );
    }

    function test_SetChainlinkForwarder_SetsAddressAndGrantsRole() public {
        updateRiskManagerAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        assertTrue(updateRiskManagerAutomation.hasRole(AUTOMATION_ROLE, CHAINLINK_FORWARDER));
    }

    function test_SetChainlinkForwarder_RevertsWhenZeroAddress() public {
        vm.expectRevert(UpdateRiskManager__ZeroAddress.selector);
        updateRiskManagerAutomation.setChainlinkForwarder(address(0));
    }

    function test_SetChainlinkForwarder_RevertsWhenAlreadySet() public {
        updateRiskManagerAutomation.setChainlinkForwarder(CHAINLINK_FORWARDER);
        vm.expectRevert(UpdateRiskManager__ChainlinkForwarderAddressAlreadySet.selector);
        updateRiskManagerAutomation.setChainlinkForwarder(makeAddr("anotherForwarder"));
    }

    function test_SetUpkeepId_SetsUpkeepId() public {
        assertEq(updateRiskManagerAutomation.getUpkeepId(), 0);
        updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID);
        assertEq(updateRiskManagerAutomation.getUpkeepId(), UPKEEP_ID);
    }

    function test_SetUpkeepId_RevertsWhenZero() public {
        vm.expectRevert(UpdateRiskManager__InvalidUpkeepId.selector);
        updateRiskManagerAutomation.setUpkeepId(0);
    }

    function test_SetUpkeepId_RevertsWhenAlreadySet() public {
            updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID);
            vm.expectRevert(UpdateRiskManager__ChainlinkUpkeepIdAlreadySet.selector);
            updateRiskManagerAutomation.setUpkeepId(UPKEEP_ID + 1);
    }

    function test_CheckUpkeep_ReturnsFalseWhenBothIntervalsHaveNotElapsed() public {

    }

    function test_CheckUpkeep_ReturnsTrueAndCorrectPerformDataWhenIntervalsHaveElapsed() public {

    }

    function test_CheckUpkeep_ReturnsTrueAndCorrectPerformDataWhenOnlyOneIntervalHasElapsed() public {

    }

    function test_PerformUpkeep_RevertsWhenUpkeepNotNeeded() public {
        vm.expectRevert(UpdateRiskManager__UpkeepNotNeeded.selector);
        updateRiskManagerAutomation.performUpkeep("");
    }

    function test_PerformUpkeep_RevertsIfCalledByUnauthorizedAddress() public {
    
    }

    function test_PerformUpkeep_CallsReservesOracleWhenNeededAndUpdatesLastReserveUpdate() public {
        
    }

    function test_PerformUpkeep_CallsYieldsOracleWhenNeededAndUpdatesLastYieldsUpdate() public {
        
    }

    function test_PerformUpkeep_CallsBothOraclesWhenBothNeedUpdating() public {
        
    }

    function test_PerformUpkeep_EmitsManualUpkeepEventWhenExecutedByTokenContract() public {
        
    }

    function test_Getters_ReturnStoredValues() public view {
        // GET CHAINLOINK FORWARDER

        // GET UPKEEP ID    

        // GET BOND ORACLE ADDRESS

        // GET RESERVES ORACLE ADDRESS

        // GET TOKEN ADDRESS
    }
}

contract tokenMock {
    function callAutomationUpdate(address _automation) public view {
        (bool upkeepNeeded, bytes memory performData) = UpdateRiskManagerAutomation(_automation).checkUpkeep("");
        UpdateRiskManagerAutomation(_automation).performUpkeep(performData);
    }

    
}

contract reservesOracleMock {
    uint256 private s_lastTimestamp;

    function setLastTimestamp(uint256 timestamp) public {
        s_lastTimestamp = timestamp;
    }

    function getLastTimestamp() public view returns (uint256) {
        return s_lastTimestamp;
    }
}

contract yieldsOracleMock {
    uint256 private s_lastTimestamp;

    function setLastTimestamp(uint256 timestamp) public {
        s_lastTimestamp = timestamp;
    }

    function getLastTimestamp() public view returns (uint256) {
        return s_lastTimestamp;
    }
}