//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReservesResponse} from "../types.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract ReservesOracle is IReservesOracle, ERC165, AccessControl {
    using ECDSA for bytes32;

    uint256 internal constant STALENESS_THRESHOLD = 48 hours;
    uint8 internal constant DECIMALS = 8;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    ReservesResponse internal s_reservesResponse;
    address internal s_functionsConsumer;
    address internal s_reservesSigner;
    uint8 internal s_decimals;

    constructor(address _functionsConsumer, address _reservesSigner) {
        if (_functionsConsumer == address(0) || _reservesSigner == address(0))
            revert ReservesOracle__ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, _functionsConsumer);
        s_functionsConsumer = _functionsConsumer;
        s_reservesSigner = _reservesSigner;
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

        if (navs.length < 4)
            revert ReservesOracle__IncompleteResponse(navs.length);

        address recovered = ECDSA.recover(hash, signature);
        if (recovered != s_reservesSigner)
            revert ReservesOracle__InvalidSignature(recovered);

        s_reservesResponse = ReservesResponse({
            twoYearNav: navs[0],
            fiveYearNav: navs[1],
            tenYearNav: navs[2],
            thirtyYearNav: navs[3],
            timestamp: timestamp
        });

        emit NavUpdated(
            s_reservesResponse.twoYearNav,
            s_reservesResponse.fiveYearNav,
            s_reservesResponse.tenYearNav,
            s_reservesResponse.thirtyYearNav,
            s_reservesResponse.timestamp
        );
    }

    function getNav(uint256 _slot) external view returns (uint256) {
        ReservesResponse memory navs = s_reservesResponse;
        if (_isStale(navs.timestamp)) revert ReservesOracle__DataIsStale();

        if (_slot == 1) return navs.twoYearNav;
        if (_slot == 2) return navs.fiveYearNav;
        if (_slot == 3) return navs.tenYearNav;
        if (_slot == 4) return navs.thirtyYearNav;

        revert ReservesOracle__InvalidSlot();
    }

    function isStale() public view returns (bool) {
        return _isStale(s_reservesResponse.timestamp);
    }

    function _isStale(uint256 _timestamp) internal view returns (bool) {
        return (block.timestamp - _timestamp) > STALENESS_THRESHOLD;
    }

    function getDecimals() public pure returns (uint8) {
        return DECIMALS;
    }

    function getLastUpdatedTimestamp() public view returns (uint256) {
        return s_reservesResponse.timestamp;
    }

    function getFunctionsConsumer() public view returns (address) {
        return s_functionsConsumer;
    }

    function getReservesSigner() public view returns (address) {
        return s_reservesSigner;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC165) returns (bool) {
        return
            interfaceId == type(IReservesOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
