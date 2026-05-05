// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReservesResponse} from "../types.sol";

contract ReservesOracle is IReservesOracle, AccessControl {
    using ECDSA for bytes32;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint256 internal constant STALENESS_THRESHOLD = 48 hours;

    ReservesResponse internal s_state;
    address internal s_signer;

    constructor(address consumer, address signer) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, consumer);
        s_signer = signer;
    }

    // ----------------------------
    // CORE UPDATE FUNCTION
    // ----------------------------
    function updateUsdValues(
        uint256[4] memory bond,
        uint256[4] memory cash,
        uint256 timestamp,
        bytes memory signature,
        bytes memory err
    ) external onlyRole(UPDATER_ROLE) {
        if (err.length > 0) return;

        bytes32 hash = keccak256(
            abi.encode(bond, cash, timestamp)
        );

        address recovered = ECDSA.recover(hash, signature);
        if (recovered != s_signer)
            revert ReservesOracle__InvalidSignature(recovered);

        uint256 bondSum =
            bond[0] + bond[1] + bond[2] + bond[3];

        uint256 cashSum =
            cash[0] + cash[1] + cash[2] + cash[3];

        s_state = ReservesResponse({
            twoYearUsdValue: bond[0],
            fiveYearUsdValue: bond[1],
            tenYearUsdValue: bond[2],
            thirtyYearUsdValue: bond[3],

            twoYearCashValue: cash[0],
            fiveYearCashValue: cash[1],
            tenYearCashValue: cash[2],
            thirtyYearCashValue: cash[3],

            cashBufferUsdValue: cashSum,
            totalUsdValue: bondSum + cashSum,
            timestamp: timestamp
        });

        emit UsdValueUpdated(
            bond[0],
            bond[1],
            bond[2],
            bond[3],
            bondSum + cashSum,
            timestamp
        );
    }

    // ----------------------------
    // READ FUNCTIONS
    // ----------------------------
    function getAllReserves() external view returns (ReservesResponse memory) {
        require(!_isStale(), "stale data");
        return s_state;
    }

    function getTotalUsdValue() external view returns (uint256) {
        require(!_isStale(), "stale data");
        return s_state.totalUsdValue;
    }

    function isStale() external view returns (bool) {
        return _isStale();
    }

    function _isStale() internal view returns (bool) {
        return block.timestamp - s_state.timestamp > STALENESS_THRESHOLD;
    }

    function getLastUpdatedTimestamp() public view returns (uint256) {
        return s_state.timestamp;
    }
}
