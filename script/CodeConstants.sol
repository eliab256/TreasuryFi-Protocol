//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

abstract contract CodeConstants {
    uint256 internal constant KYC_CLAIM_TOPIC = 1;
    uint256 internal constant AML_CLAIM_TOPIC = 2;

    uint256 internal constant ECDSA_SCHEME = 1;
    uint16 internal constant DEFAULT_COUNTRY = 380; // IT

    bytes internal constant DEFAULT_KYC_DATA = abi.encodePacked("KYC_APPROVED");

    address public constant SEPOLIA_FUNCIONS_ROUTER =
        0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;

    address public constant MAINNET_FUNCTIONS_ROUTER =
        0x65Dcc24F8ff9e51F10DCc7Ed1e4e2A61e6E14bd6;
}
