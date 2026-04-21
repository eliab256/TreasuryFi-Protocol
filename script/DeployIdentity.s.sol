//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {CodeConstants} from "./CodeConstants.sol";
import {
    ClaimTopicsRegistry
} from "@t-rex/registry/implementation/ClaimTopicsRegistry.sol";
import {ClaimIssuer} from "@onchain-id/solidity/ClaimIssuer.sol";
import {
    TrustedIssuersRegistry
} from "@t-rex/registry/implementation/TrustedIssuersRegistry.sol";
import {
    IdentityRegistryStorage
} from "@t-rex/registry/implementation/IdentityRegistryStorage.sol";
import {
    IdentityRegistry
} from "@t-rex/registry/implementation/IdentityRegistry.sol";

contract DeployIdentity is Script, CodeConstants {
    ClaimTopicsRegistry public claimTopicsRegistry;
    ClaimIssuer public claimIssuer;
    TrustedIssuersRegistry public trustedIssuersRegistry;
    IdentityRegistryStorage public identityRegistryStorage;
    IdentityRegistry public identityRegistry;



    function run() external {
        vm.startBroadcast();
        // 1.2.1 Deploy ClaimTopicsRegistry and call addClaimTopic to register topic 1 (KYC)
        claimTopicsRegistry = new ClaimTopicsRegistry();
        claimTopicsRegistry.init();
        claimTopicsRegistry.addClaimTopic(KYC_CLAIM_TOPIC);
        //claimTopicsRegistry.addClaimTopic(AML_CLAIM_TOPIC);

        // 1.2.2 Deploy ClaimIssuer (from ONCHAINID), the entity that will sign investor KYC claims
        claimIssuer = new ClaimIssuer(address(claimTopicsRegistry)); //@audit-issue check valore consturctor

        //  1.2.3 Deploy TrustedIssuersRegistry call addTrustedIssuer to trust the ClaimIssuer for topic 1
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        trustedIssuersRegistry.init();
        uint256[] memory claimTopics = claimTopicsRegistry.getClaimTopics();
        trustedIssuersRegistry.addTrustedIssuer(
            address(claimIssuer),
            claimTopics
        );

        //  1.2.4 Deploy IdentityRegistryStorage
        identityRegistryStorage = new IdentityRegistryStorage();
        identityRegistryStorage.init();

        // 1.2.5 Deploy IdentityRegistry and pass addresses of TrustedIssuersRegistry, ClaimTopicsRegistry, IdentityRegistryStorage
        identityRegistry = new IdentityRegistry();
        identityRegistry.init(
            address(trustedIssuersRegistry),
            address(claimTopicsRegistry),
            address(identityRegistryStorage)
        );

        // 1.2.6 Bind IdentityRegistryStorage to IdentityRegistry by calling bindIdentityRegistry(identityRegistry) on the storage
        identityRegistryStorage.bindIdentityRegistry(address(identityRegistry));

        vm.stopBroadcast();
    }
}
