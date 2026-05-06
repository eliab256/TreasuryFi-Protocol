//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IIdentityRegistry} from "@t-rex/registry/interface/IIdentityRegistry.sol";
import {IModularCompliance} from "@t-rex/compliance/modular/IModularCompliance.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIdentity} from "@onchain-id/solidity/contracts/interface/IIdentity.sol";

abstract contract ERC3643 is AccessControl {

    // Eventi
    event IdentityRegistryAdded(address indexed identityRegistry);
    event AddressFrozen(address indexed wallet, bool indexed frozen, address indexed owner);
    event TokenValueFrozen(uint256 indexed tokenId, uint256 amount);
    event TokenValueUnfrozen(uint256 indexed tokenId, uint256 amount);
    event ComplianceAdded(address indexed compliance);
    event Paused(address indexed account); 
    event Unpaused(address indexed account); 
    event UpdatedTokenInformation(string name, string symbol, uint8 decimals, string version, address onchainID); 
    event RecoverySuccess(address indexed lostWallet, address indexed newWallet, address indexed investorOnchainID);


    // Custom error
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


    /// @dev Token information
    /// @dev  decimals inherit from erc3525
    string internal s_name;
    string internal s_symbol;
    address internal s_tokenOnchainID;
    bool internal s_tokenPaused = false;
    string internal constant TOKEN_VERSION = "4.1.3";

    /// @dev Variables of freeze and pause functions
    mapping(address => bool) internal s_frozenWallets;
    // mapping: tokenId => frozen value
    mapping(uint256 => uint256) private s_frozenValues;
    bool internal s_recovering;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE"); 

    /// @dev Identity Registry contract used by the onchain validator system
    IIdentityRegistry internal s_tokenIdentityRegistry;

    /// @dev Compliance contract linked to the onchain validator system
    IModularCompliance internal s_tokenCompliance;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _onchainID,
        address _identityRegistry,
        address _compliance
    )  {
        if (bytes(_name).length == 0) revert ERC3643__InvalidName();
        if (bytes(_symbol).length == 0)
            revert ERC3643__InvalidSymbol();
        if (_decimals == 0 || _decimals > 18)
            revert ERC3643__InvalidDecimals();
        if( _identityRegistry == address(0)){
            revert ERC3643__ZeroAddress();
        }
        s_name = _name;
        s_symbol = _symbol;
        s_tokenOnchainID = _onchainID;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);

        _setIdentityRegistry(_identityRegistry);
        _setCompliance(_compliance);
    }

    function _setIdentityRegistry(
        address _identityRegistry
    ) internal {
         if (_identityRegistry == address(0)) revert ERC3643__ZeroAddress();
        s_tokenIdentityRegistry = IIdentityRegistry(_identityRegistry);
        emit IdentityRegistryAdded(_identityRegistry);
    }

    function setName(string calldata _name) external onlyRole(OWNER_ROLE) {
          if (bytes(_name).length == 0) revert ERC3643__InvalidName();
        s_name = _name;
        emit UpdatedTokenInformation(_name, s_symbol, valueDecimals(), TOKEN_VERSION, s_tokenOnchainID);
    }

    function setSymbol(string calldata _symbol) external onlyRole(OWNER_ROLE) {
        if (bytes(_symbol).length == 0) revert ERC3643__InvalidSymbol();
        s_symbol = _symbol;
        emit UpdatedTokenInformation(s_name, _symbol, valueDecimals(), TOKEN_VERSION, s_tokenOnchainID);
    }

    function _setOnchainID(address _onchainID) internal {
        if (_onchainID == address(0)) revert ERC3643__ZeroAddress();
        s_tokenOnchainID = _onchainID;
        emit UpdatedTokenInformation(s_name, s_symbol, valueDecimals(), TOKEN_VERSION, _onchainID);
    }

    // @audit-issue aggiustare la funzione per erc3525
    function recoveryAddress(
    address _lostWallet,
    address _newWallet,
    address _investorOnchainID
    ) external onlyRole(OWNER_ROLE) returns (bool) {
        // Checks if the new wallet is different from the lost one and not already verified in the identity registry
        if (_newWallet == _lostWallet) revert ERC3643__RecoveryNotPossible();
        if (s_tokenIdentityRegistry.isVerified(_newWallet)) revert ERC3643__RecoveryNotPossible();

        // checks if has tokens to recover
        if (balanceOf(_lostWallet) == 0) revert ERC3643__NoTokensToRecover();

        IIdentity investorOnchainID = IIdentity(_investorOnchainID);
        bytes32 key = keccak256(abi.encode(_newWallet));

        if (!investorOnchainID.keyHasPurpose(key, 1)) revert ERC3643__RecoveryNotPossible();

        // 1. Register the new wallet BEFORE the transfer
        //    so _beforeValueTransfer finds newWallet as verified
        s_tokenIdentityRegistry.registerIdentity(
            _newWallet,
            investorOnchainID,
            s_tokenIdentityRegistry.investorCountry(_lostWallet)
        );

        // 2. Recovery flag: bypasses the SenderFrozen check in _beforeValueTransfer
        s_recovering = true;

        // 3. Delegate the transfer of tokens (ERC3525 logic) to the child contract
        try this._executeRecoveryTransferExternal(_lostWallet, _newWallet) {
        // recovery succeeded
        } catch {
            s_recovering = false;
            //Cleanup of the registration done above if the transfer fails, to avoid leaving an orphan identity in the registry
            s_tokenIdentityRegistry.deleteIdentity(_newWallet);
            revert ERC3643__RecoveryNotPossible();
        }

        s_recovering = false;
        
        // 4. Propagate the freeze at wallet level if present
        if (s_frozenWallets[_lostWallet]) {
            _setAddressFrozen(_newWallet, true);
            _setAddressFrozen(_lostWallet, false); // unfreeze the old wallet
        }

        // 5. Remove the identity of the lost wallet
        s_tokenIdentityRegistry.deleteIdentity(_lostWallet);

        emit RecoverySuccess(_lostWallet, _newWallet, _investorOnchainID);
        return true;
    }

    /// @dev Override in TreasuryBondToken to implement ERC3525 transfer
    function _executeRecoveryTransfer(
        address lostWallet,
        address newWallet
    ) internal virtual;

    function _pause() internal {
        _whenNotPaused();
        s_tokenPaused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        _whenPaused();
        s_tokenPaused = false;
        emit Unpaused(msg.sender);
    }


    function _setAddressFrozen(address _userAddress, bool _freeze) internal {
        s_frozenWallets[_userAddress] = _freeze;

        emit AddressFrozen(_userAddress, _freeze, msg.sender);
    }

    function _freezePartialToken(uint256 _tokenId, uint256 _amount) internal {
        uint256 tokenValue  = balanceOf(_tokenId);        // valore del token
        uint256 frozenValue = s_frozenValues[_tokenId];

        if (tokenValue < frozenValue + _amount) {
            revert ERC3643__AmountExceedsAvailableValue();
        }

        s_frozenValues[_tokenId] = frozenValue + _amount;
        emit TokenValueFrozen(_tokenId, _amount);
    }

    function _unfreezePartialToken(uint256 _tokenId, uint256 _amount) internal {
        uint256 frozenValue = s_frozenValues[_tokenId];

        if (frozenValue < _amount) {
            revert ERC3643__AmountExceedsAvailableFrozen();
        }

        s_frozenValues[_tokenId] = frozenValue - _amount;
        emit TokenValueUnfrozen(_tokenId, _amount);
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     * @dev Made to be inherited and used in the main token contract to restrict token transfers and other state changing functions when the token is paused
     */
    function _whenNotPaused() internal view {
        if (s_tokenPaused) {
            revert ERC3643__TokenPaused();
        }
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     * @dev Made to be inherited and used in the main token contract to restrict certain functions to be only called when the token is paused
     */
    function _whenPaused() internal view {
        if (!s_tokenPaused) {
            revert ERC3643__TokenNotPaused();
        }
    }

    function _setCompliance(address _compliance) internal {
        if (address(s_tokenCompliance) != address(0)) {
            s_tokenCompliance.unbindToken(address(this));
        }
        s_tokenCompliance = IModularCompliance(_compliance);
        s_tokenCompliance.bindToken(address(this));
        emit ComplianceAdded(_compliance);
    }

////////////////////////////////////////////////////////////////////
///////////////////////////// Getters ////////////////////////////// 
////////////////////////////////////////////////////////////////////  


    function compliance() external view  returns (IModularCompliance) {
        return s_tokenCompliance;
    }

    function paused() external view returns (bool) {
        return s_tokenPaused;
    }

    function onchainID() public view returns (address) {
        return s_tokenOnchainID;
    }

    function version() public pure returns (string memory) {
        return TOKEN_VERSION;
    }

    function getWalletFrozenStatus(address _wallet) public view returns (bool) {
        return s_frozenWallets[_wallet];
    }

    function getFrozenValue(uint256 _tokenId) public view returns (uint256) {
        return s_frozenValues[_tokenId];
    }

    function getAvailableValue(uint256 _tokenId) public view returns (uint256) {
        return balanceOf(_tokenId) - s_frozenValues[_tokenId];
    }

    function _beforeValueTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value) internal virtual {
            _whenNotPaused();
            if(_from != address(0)){
                if(! s_tokenIdentityRegistry.isVerified(_from)){
                    revert ERC3643__SenderNotVerified();
                }
                if (!s_recovering && s_frozenWallets[_from]) {
                    revert ERC3643__SenderFrozen();
                }
                // @audit-info recuperare info da erc3525 per check frozen value
            }
            if(_to != address(0)){
                if(! s_tokenIdentityRegistry.isVerified(_to)){
                    revert ERC3643__ReceiverNotVerified();
                }
                if(s_frozenWallets[_to]){
                    revert ERC3643__ReceiverFrozen();   
                }

                uint256 frozenValue = s_frozenValues[_toTokenId];
            }
    }

    /**
     * @dev balanceOf function overloaded to support both address and tokenId queries for ERC3643 and ERC3525 compatibility
     * @dev set to virtual to be overridden in the main token contract with the actual logic to return balances based on address or tokenId
     * @param _owner The address to query the balance of (for ERC3643) or the tokenId to query the balance of (for ERC3525)
     * @return The balance of the address or tokenId depending on the input type
     */
    function balanceOf(address _owner) public view virtual returns (uint256);

    /**
     * @dev balanceOf function overloaded to support both address and tokenId queries for ERC3643 and ERC3525 compatibility
     * @dev set to virtual to be overridden in the main token contract with the actual logic to return balances based on address or tokenId
     */
    function balanceOf(uint256 _tokenId) public view virtual returns (uint256);


    function valueDecimals() public view virtual returns (uint8);


}