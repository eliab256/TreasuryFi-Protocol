//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {IUpdateRiskManagerAutomation} from "../interfaces/IUpdateRiskManagerAutomation.sol";
import {ITreasuryBondToken} from "../interfaces/ITreasuryBondToken.sol";

/**
 * @title UpdateRiskManagerAutomation
 */
 contract UpdateRiskManagerAutomation is IUpdateRiskManagerAutomation, AccessControl{

    bytes32 public constant AUTOMATION_ROLE = keccak256("AUTOMATION_ROLE");

    address private s_chainlinkForwarder;
    uint256 private s_upkeepId;

    uint256 internal s_lastReserveUpdate;
    uint256 internal s_lastYieldsUpdate;

    address private immutable i_reservesOracle;
    address private immutable i_bondYieldsOracle;
    address private immutable i_tokenContract;

    constructor(
        address _tokenContract, 
        address _reservesOracle, 
        address _bondYieldsOracle,
        address _admin) {
        if(_tokenContract == address(0) || _reservesOracle == address(0) || _bondYieldsOracle == address(0) || _admin == address(0))
            revert UpdateRiskManager__ZeroAddress();
        i_reservesOracle = _reservesOracle;
        i_bondYieldsOracle = _bondYieldsOracle;
        i_tokenContract = _tokenContract;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(AUTOMATION_ROLE, _tokenContract);
    }

    /**
     * @notice Sets the Chainlink Automation forwarder address
     * @dev Can only be set once by an admin
     */
    function setChainlinkForwarder(
        address _chainlinkForwarder
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_chainlinkForwarder == address(0)) revert UpdateRiskManager__ZeroAddress();

        if (s_chainlinkForwarder != address(0)) {
            revert UpdateRiskManager__ChainlinkForwarderAddressAlreadySet();
        }
        s_chainlinkForwarder = _chainlinkForwarder;
        _grantRole(AUTOMATION_ROLE, _chainlinkForwarder);
    }

    /**
     * @notice Sets the upkeep ID
     * @dev Can only be set once by an admin
     */
    function setUpkeepId(
        uint256 _upkeepId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_upkeepId == 0) revert UpdateRiskManager__InvalidUpkeepId();

        if (s_upkeepId != 0) {
            revert UpdateRiskManager__ChainlinkUpkeepIdAlreadySet();
        }
        s_upkeepId = _upkeepId;
    }


    function checkUpkeep(
        bytes calldata
    ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 yieldsTimestamp = IBondOracle(i_bondYieldsOracle).getLastUpdatedTimestamp();
        uint256 reservesTimestamp = IReservesOracle(i_reservesOracle).getLastUpdatedTimestamp();

        bool yieldsUpdateNeeded = yieldsTimestamp > s_lastYieldsUpdate;
        bool reservesUpdateNeeded = reservesTimestamp > s_lastReserveUpdate;

        // If only one of them needs an update, we still want to perform upkeep to update that one and avoid unnecessary delays. 
        upkeepNeeded = yieldsUpdateNeeded || reservesUpdateNeeded;

        // The performData will indicate which one(s) need updating.
        performData = abi.encode(yieldsUpdateNeeded, reservesUpdateNeeded);
        return (upkeepNeeded, performData);
    }

    /**
     * @notice Performs the upkeep, callable by Chainlink Automation forwarder or RiskManager.
     * @dev Access is restricted via AUTOMATION_ROLE, granted to both s_chainlinkForwarder and i_tokenContract.
     * @param performData ABI-encoded (bool yieldsUpdateNeeded, bool reservesUpdateNeeded)
     */
    function performUpkeep(bytes calldata performData) external onlyRole(AUTOMATION_ROLE) {
        (bool yieldsUpdateNeeded, bool reservesUpdateNeeded) = abi.decode(performData, (bool, bool));

         uint256 yieldsTimestamp = IBondOracle(i_bondYieldsOracle).getLastUpdatedTimestamp();
         uint256 reservesTimestamp = IReservesOracle(i_reservesOracle).getLastUpdatedTimestamp();
    
        yieldsUpdateNeeded = yieldsUpdateNeeded && (yieldsTimestamp > s_lastYieldsUpdate);
        reservesUpdateNeeded = reservesUpdateNeeded && (reservesTimestamp > s_lastReserveUpdate);

        if (!yieldsUpdateNeeded && !reservesUpdateNeeded) {
            revert UpdateRiskManager__UpkeepNotNeeded();
        }

        if (yieldsUpdateNeeded) {
            ITreasuryBondToken(i_tokenContract).updateYieldsValues();
            s_lastYieldsUpdate = yieldsTimestamp;
        }
        if (reservesUpdateNeeded) {
            ITreasuryBondToken(i_tokenContract).updateReserveValues();
            s_lastReserveUpdate = reservesTimestamp;
        }

        if (msg.sender != s_chainlinkForwarder) {
            emit ManualUpkeepExecuted(msg.sender, block.timestamp);
        }
    }

    // --- Getters ---
    function getChainlinkForwarder() external view returns (address) {
        return s_chainlinkForwarder;
    }

    function getUpkeepId() external view returns (uint256) {
        return s_upkeepId;
    }

    function getTokenContract() external view returns (address) {
        return i_tokenContract;
    }

    function getReservesOracle() external view returns (address) {
        return i_reservesOracle;
    }

    function getBondOracle() external view returns (address) {
        return i_bondYieldsOracle;
    }


}
