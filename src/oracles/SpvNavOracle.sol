//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ISpvNavOracle} from "../interfaces/ISpvNavOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SpvNavsResponse} from "../types.sol";

contract SpvNavOracle is ISpvNavOracle, AccessControl {
    using ECDSA for bytes32;

    uint256 internal constant STALENESS_THRESHOLD = 48 hours;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    SpvNavsResponse internal s_spvNavsResponse;
    address internal s_functionsConsumer;
    address internal s_spvSigner;

    constructor(address _functionsConsumer, address _spvSigner) {
        if (_functionsConsumer == address(0) || _spvSigner == address(0))
            revert SpvNavOracle__ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, _functionsConsumer);
        s_functionsConsumer = _functionsConsumer;
        s_spvSigner = _spvSigner;
    }

    function updateNav(
        bytes memory response,
        bytes memory err
    ) external onlyRole(UPDATER_ROLE) {
        if (err.length > 0) {
            emit NavUpdateFailed(err);
            return;
        }

        (
            uint256[4] memory navs,
            uint256 timestamp,
            bytes memory signature,
            bytes32 hash
        ) = abi.decode(response, (uint256[4], uint256, bytes, bytes32));

        if (navs.length < 4) revert SpvNavOracle__IncompleteResponse(navs.length);

        address recovered = ECDSA.recover(hash, signature);
        if (recovered != s_spvSigner) revert SpvNavOracle__InvalidSignature(recovered);

        s_spvNavsResponse = SpvNavsResponse({
            twoYearNav: navs[0],
            fiveYearNav: navs[1],
            tenYearNav: navs[2],
            thirtyYearNav: navs[3],
            timestamp: timestamp
        });

        emit NavUpdated(
            s_spvNavsResponse.twoYearNav,
            s_spvNavsResponse.fiveYearNav,
            s_spvNavsResponse.tenYearNav,
            s_spvNavsResponse.thirtyYearNav,
            s_spvNavsResponse.timestamp
        );
    }

    function getNav(uint256 _slot) external view returns (uint256) {
        SpvNavsResponse memory navs = s_spvNavsResponse;
        if (_isStale(navs.timestamp)) revert SpvNavOracle__DataIsStale();

        if (_slot == 1) return navs.twoYearNav;
        if (_slot == 2) return navs.fiveYearNav;
        if (_slot == 3) return navs.tenYearNav;
        if (_slot == 4) return navs.thirtyYearNav;

        revert SpvNavOracle__InvalidSlot();
    }

    function isStale() public view returns (bool) {
        return _isStale(s_spvNavsResponse.timestamp);
    }

    function _isStale(uint256 _timestamp) internal view returns (bool) {
        return (block.timestamp - _timestamp) > STALENESS_THRESHOLD;
    }

    function getLastUpdatedTimestamp() public view returns (uint256) {
        return s_spvNavsResponse.timestamp;
    }

    function getFunctionsConsumer() public view returns (address) {
        return s_functionsConsumer;
    }

    function getSpvSigner() public view returns (address) {
        return s_spvSigner;
    }
}
