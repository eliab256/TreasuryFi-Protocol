// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReservesResponse} from "../types.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract ReservesOracle is IReservesOracle, ERC165, AccessControl {
    using ECDSA for bytes32;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint256 internal constant STALENESS_THRESHOLD = 48 hours;

    ReservesResponse internal s_state;
    address internal s_signer;

    constructor(address consumer, address signer) {
        if (consumer == address(0) || signer == address(0))
            revert ReservesOracle__ZeroAddress();
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
        if (err.length > 0) {
            emit UsdValueUpdateFailed(err);
            return;
        }

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
            twoYearUsdBondsValue: bond[0],
            fiveYearUsdBondsValue: bond[1],
            tenYearUsdBondsValue: bond[2],
            thirtyYearUsdBondsValue: bond[3],

            twoYearUsdCashValue: cash[0],
            fiveYearUsdCashValue: cash[1],
            tenYearUsdCashValue: cash[2],
            thirtyYearUsdCashValue: cash[3],

            cashBufferUsdTotalValue: cashSum,
            totalUsdBondsValue: bondSum,
            totalUsdPortfolioValue: bondSum + cashSum,
            timestamp: timestamp
        });

        emit UsdValueUpdated(
            bond[0],
            bond[1],
            bond[2],
            bond[3],
            bondSum + cashSum, // totalUsdPortfolioValue
            timestamp
        );
    }

    // ----------------------------
    // READ FUNCTIONS
    // ----------------------------
    function getAllReserves() external view returns (ReservesResponse memory) {
        if (_isStale()) revert ReservesOracle__DataIsStale();
        return s_state;
    }

    function getTotalUsdValue() external view returns (uint256) {
        if (_isStale()) revert ReservesOracle__DataIsStale();
        return s_state.totalUsdPortfolioValue;
    }

    function isStale() external view returns (bool) {
        return _isStale();
    }

    function _isStale() internal view returns (bool) {
        if (s_state.timestamp == 0) return true;
        return block.timestamp - s_state.timestamp > STALENESS_THRESHOLD;
    }

    function getLastUpdatedTimestamp() public view returns (uint256) {
        return s_state.timestamp;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC165) returns (bool) {
        return
            interfaceId == type(IReservesOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
