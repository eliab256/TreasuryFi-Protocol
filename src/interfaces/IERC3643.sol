//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IModularCompliance} from "@t-rex/compliance/modular/IModularCompliance.sol";
import {IIdentityRegistry} from "@t-rex/registry/interface/IIdentityRegistry.sol";

/**
 * @title IERC3643
 * @notice Public API interface for the ERC3643 compliance-aware token standard.
 * @dev Defines all external admin functions that must be implemented by the concrete token contract.
 *      Abstract contract ERC3643 inherits this interface and provides the internal logic (_function()).
 *      The concrete token contract (TreasuryBondToken) overrides these functions with access-controlled wrappers.
 */
interface IERC3643 {

    // --- Events ---
    event IdentityRegistryAdded(address indexed identityRegistry);
    event AddressFrozen(address indexed wallet, bool indexed frozen, address indexed owner);
    event TokenValueFrozen(uint256 indexed tokenId, uint256 amount);
    event TokenValueUnfrozen(uint256 indexed tokenId, uint256 amount);
    event ComplianceAdded(address indexed compliance);
    event Paused(address indexed account); 
    event Unpaused(address indexed account); 
    event UpdatedTokenInformation(string name, string symbol, uint8 decimals, string version, address onchainID); 
    event RecoverySuccess(address indexed lostWallet, address indexed newWallet, address indexed investorOnchainID);


    // --- Custom error ---
    error ERC3643__InvalidName();
    error ERC3643__InvalidSymbol();
    error ERC3643__InvalidDecimals();
    error ERC3643__ZeroAddress();
    error ERC3643__TokenPaused();
    error ERC3643__TokenNotPaused();
    error ERC3643__AmountExceedsAvailableValue();
    error ERC3643__AmountExceedsAvailableFrozen();
    error ERC3643__NoTokensToRecover();
    error ERC3643__RecoveryNotPossible();
    error ERC3643__SenderNotVerified();
    error ERC3643__ReceiverNotVerified();
    error ERC3643__SenderFrozen();
    error ERC3643__ReceiverFrozen();

    // --- Admin functions ---

    function setIdentityRegistry(address identityRegistry) external;

    function setNameAndSymbol(string calldata name_, string calldata symbol_) external;

    function setOnchainID(address onchainID) external;

    function recoveryAddress(address lostWallet, address newWallet, address investorOnchainID) external returns (bool);

    function pause() external;

    function unpause() external;

    function setAddressFrozen(address userAddress, bool freeze) external;

    function freezePartialTokens(uint256 tokenId, uint256 amount) external;

    function unfreezePartialTokens(uint256 tokenId, uint256 amount) external;

    function batchSetAddressFrozen(address[] calldata userAddresses, bool[] calldata freeze) external;

    function batchFreezePartialTokens(uint256[] calldata tokenId, uint256[] calldata amounts) external;

    function batchUnfreezePartialTokens(uint256[] calldata tokenId, uint256[] calldata amounts) external;

    function setCompliance(address compliance) external;

    // --- Getters ---

    function compliance() external view returns (IModularCompliance);

    function identityRegistry() external view returns (IIdentityRegistry);

    function paused() external view returns (bool);

    function onchainID() external view returns (address);

    function version() external pure returns (string memory);

    function getWalletFrozenStatus(address wallet) external view returns (bool);

    function getFrozenValue(uint256 tokenId) external view returns (uint256);

    function getAvailableValue(uint256 tokenId) external view returns (uint256);
}
