//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReservesResponse} from "../types.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract ReservesOracle is IReservesOracle, ERC165, AccessControl {
    using ECDSA for bytes32;

    uint256 internal constant STALENESS_THRESHOLD = 48 hours;
    uint8 internal constant DECIMALS = 8;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    ReservesResponse internal s_reservesResponse;
    address internal s_functionsConsumer;
    address internal s_reservesSigner;

    constructor(address _functionsConsumer, address _reservesSigner) {
        if (_functionsConsumer == address(0) || _reservesSigner == address(0))
            revert ReservesOracle__ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, _functionsConsumer);
        s_functionsConsumer = _functionsConsumer;
        s_reservesSigner = _reservesSigner;
    }


   function updateUsdValues(
        uint256[4] memory _usdValues,
        uint256 _cashUsd,
        uint256 _timestamp,
        bytes memory _signature,
        bytes32 _hash,
        bytes memory _err
    ) external onlyRole(UPDATER_ROLE) {
        if (_err.length > 0) {
            emit UsdValueUpdateFailed(_err);
            return;
        }

        // FIX 3: verifica firma sui dati già decodificati
        address recovered = ECDSA.recover(_hash, _signature);
        if (recovered != s_reservesSigner)
            revert ReservesOracle__InvalidSignature(recovered);

        // somma dei bucket bond
        uint256 bucketsSum =
            _usdValues[0] +
            _usdValues[1] +
            _usdValues[2] +
            _usdValues[3];

        // totale riserve = bond buckets + liquidità cash
        uint256 totalUsdValue = bucketsSum + _cashUsd;

        // @audit-issue: aggiungere cashUsdValue e totalUsdValue alla struct ReservesResponse in types.sol
        s_reservesResponse = ReservesResponse({
            twoYearUsdValue: _usdValues[0],
            fiveYearUsdValue: _usdValues[1],
            tenYearUsdValue: _usdValues[2],
            thirtyYearUsdValue: _usdValues[3],
            cashBufferUsdValue: _cashUsd,
            totalUsdValue: totalUsdValue,
            timestamp: _timestamp
        });

        emit UsdValueUpdated(
            _usdValues[0],
            _usdValues[1],
            _usdValues[2],
            _usdValues[3],
            _cashUsd,
            totalUsdValue,
            _timestamp
        );
    }


    function getReserveUsdValue(uint256 _slot) external view returns (uint256) {
        ReservesResponse memory usdValues = s_reservesResponse;
        if (_isStale(usdValues.timestamp)) revert ReservesOracle__DataIsStale();

        if (_slot == 1) return usdValues.twoYearUsdValue;
        if (_slot == 2) return usdValues.fiveYearUsdValue;
        if (_slot == 3) return usdValues.tenYearUsdValue;
        if (_slot == 4) return usdValues.thirtyYearUsdValue;

        revert ReservesOracle__InvalidSlot();
    }

    function isStale() public view returns (bool) {
        return _isStale(s_reservesResponse.timestamp);
    }

    function _isStale(uint256 _timestamp) internal view returns (bool) {
        return (block.timestamp - _timestamp) > STALENESS_THRESHOLD;
    }

    function getTotalUsdValue() external view returns (uint256) {
        if (_isStale(s_reservesResponse.timestamp)) revert ReservesOracle__DataIsStale();
        return s_reservesResponse.totalUsdValue;
    }

    function getCashBufferUsdValue() external view returns (uint256) {
        if (_isStale(s_reservesResponse.timestamp)) revert ReservesOracle__DataIsStale();
        return s_reservesResponse.cashBufferUsdValue;
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
