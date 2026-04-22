//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {CodeConstants} from "./CodeConstants.sol";
import {Identity} from "@onchain-id/solidity/contracts/Identity.sol";
import {
    IIdentity
} from "@onchain-id/solidity/contracts/interface/IIdentity.sol";
import {
    IdentityRegistry
} from "@t-rex/registry/implementation/IdentityRegistry.sol";

contract RegisterInvestor is Script, CodeConstants {
    /**
     * @notice Full-flow registration with explicit country code.
     * @param _identityRegistry Address of deployed IdentityRegistry
     * @param _claimIssuer Address of trusted ClaimIssuer
     * @param _investorWallet Investor EOA to register
     * @param _countryCode Country code stored in IdentityRegistry
     * @param _claimSignerPrivateKey Private key used to sign the KYC claim
     */
    function run(
        address _identityRegistry,
        address _claimIssuer,
        address _investorWallet,
        uint16 _countryCode,
        uint256 _claimSignerPrivateKey
    ) external {
        _run(
            _identityRegistry,
            _claimIssuer,
            _investorWallet,
            _countryCode,
            _claimSignerPrivateKey
        );
    }

    /// @notice Convenience overload using DEFAULT_COUNTRY.
    function run(
        address _identityRegistry,
        address _claimIssuer,
        address _investorWallet,
        uint256 _claimSignerPrivateKey
    ) external {
        _run(
            _identityRegistry,
            _claimIssuer,
            _investorWallet,
            DEFAULT_COUNTRY,
            _claimSignerPrivateKey
        );
    }

    function _run(
        address _identityRegistry,
        address _claimIssuer,
        address _investorWallet,
        uint16 _countryCode,
        uint256 _claimSignerPrivateKey
    ) internal {
        require(_identityRegistry != address(0), "IdentityRegistry=0");
        require(_claimIssuer != address(0), "ClaimIssuer=0");
        require(_investorWallet != address(0), "Investor=0");
        require(_claimSignerPrivateKey != 0, "SignerPK=0");

        vm.startBroadcast();

        IdentityRegistry identityRegistry = IdentityRegistry(_identityRegistry);

        // registerIdentity/updateIdentity/updateCountry are onlyAgent in T-REX.
        if (!identityRegistry.isAgent(msg.sender)) {
            identityRegistry.addAgent(msg.sender);
        }

        // 1) Reuse Identity if already linked in IR, otherwise deploy a new one.
        address linkedIdentity = address(
            identityRegistry.identity(_investorWallet)
        );
        Identity identity = linkedIdentity == address(0)
            ? new Identity(_investorWallet, false)
            : Identity(linkedIdentity);

        // 2) Ensure KYC claim exists for this issuer/topic.
        bytes32 claimId = keccak256(abi.encode(_claimIssuer, KYC_CLAIM_TOPIC));
        if (!_hasClaim(identity, claimId, _claimIssuer, KYC_CLAIM_TOPIC)) {
            bytes memory signature = _signClaim(
                _claimSignerPrivateKey,
                address(identity),
                KYC_CLAIM_TOPIC,
                DEFAULT_KYC_DATA
            );

            identity.addClaim(
                KYC_CLAIM_TOPIC,
                ECDSA_SCHEME,
                _claimIssuer,
                signature,
                DEFAULT_KYC_DATA,
                ""
            );
        }

        // 3) Register (or update) investor link in IdentityRegistry.
        if (!identityRegistry.contains(_investorWallet)) {
            identityRegistry.registerIdentity(
                _investorWallet,
                IIdentity(address(identity)),
                _countryCode
            );
        } else {
            if (
                address(identityRegistry.identity(_investorWallet)) !=
                address(identity)
            ) {
                identityRegistry.updateIdentity(
                    _investorWallet,
                    IIdentity(address(identity))
                );
            }
            if (
                identityRegistry.investorCountry(_investorWallet) !=
                _countryCode
            ) {
                identityRegistry.updateCountry(_investorWallet, _countryCode);
            }
        }

        // 4) Final verification.
        require(
            identityRegistry.isVerified(_investorWallet),
            "Investor not verified"
        );

        vm.stopBroadcast();
    }

    function _hasClaim(
        Identity _identity,
        bytes32 _claimId,
        address _expectedIssuer,
        uint256 _expectedTopic
    ) internal view returns (bool) {
        (uint256 topic, , address issuer, , , ) = _identity.getClaim(_claimId);

        return topic == _expectedTopic && issuer == _expectedIssuer;
    }

    function _signClaim(
        uint256 _privateKey,
        address _identity,
        uint256 _topic,
        bytes memory _data
    ) internal returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encode(_identity, _topic, _data));
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, prefixedHash);
        return abi.encodePacked(r, s, v);
    }
}
