//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IModularCompliance} from "@t-rex/compliance/modular/IModularCompliance.sol";

/**
 * @title IERC3643
 * @notice Public API interface for the ERC3643 compliance-aware token standard.
 * @dev Defines all external admin functions that must be implemented by the concrete token contract.
 *      Abstract contract ERC3643 inherits this interface and provides the internal logic (_function()).
 *      The concrete token contract (TreasuryBondToken) overrides these functions with access-controlled wrappers.
 */
interface IERC3643 {

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

    function paused() external view returns (bool);

    function onchainID() external view returns (address);

    function version() external pure returns (string memory);

    function getWalletFrozenStatus(address wallet) external view returns (bool);

    function getFrozenValue(uint256 tokenId) external view returns (uint256);

    function getAvailableValue(uint256 tokenId) external view returns (uint256);
}
