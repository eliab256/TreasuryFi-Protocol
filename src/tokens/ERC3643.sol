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
    string internal   s_tokenName;
    string internal  s_tokenSymbol;
    uint8 internal immutable i_tokenDecimals;
    address internal s_tokenOnchainID;
    string internal constant TOKEN_VERSION = "4.1.3";

    /// @dev Variables of freeze and pause functions
    mapping(address => bool) internal s_frozenWallets;
    // mapping: tokenId => frozen value
    mapping(uint256 => uint256) private s_frozenValues;
    bool internal s_recovering;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bool internal s_tokenPaused = false;

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
        s_tokenName = _name;
        s_tokenSymbol = _symbol;
        i_tokenDecimals = _decimals;
        s_tokenOnchainID = _onchainID;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);

        setIdentityRegistry(_identityRegistry);
        setCompliance(_compliance);
    }

    /**
     *  @dev See {IToken-setIdentityRegistry}.
     */
    function setIdentityRegistry(
        address _identityRegistry
    ) public onlyRole(OWNER_ROLE) {
         if (_identityRegistry == address(0)) revert ERC3643__ZeroAddress();
        s_tokenIdentityRegistry = IIdentityRegistry(_identityRegistry);
        emit IdentityRegistryAdded(_identityRegistry);
    }

    function setName(string calldata _name) external onlyRole(OWNER_ROLE) {
          if (bytes(_name).length == 0) revert ERC3643__InvalidName();
        s_tokenName = _name;
        emit UpdatedTokenInformation(s_tokenName, s_tokenSymbol, i_tokenDecimals, TOKEN_VERSION, s_tokenOnchainID);
    }

    function setSymbol(string calldata _symbol) external onlyRole(OWNER_ROLE) {
        if (bytes(_symbol).length == 0) revert ERC3643__InvalidSymbol();
        s_tokenSymbol = _symbol;
        emit UpdatedTokenInformation(s_tokenName, s_tokenSymbol, i_tokenDecimals, TOKEN_VERSION, s_tokenOnchainID);
    }

    function setOnchainID(address _onchainID) external onlyRole(OWNER_ROLE) {
        s_tokenOnchainID = _onchainID;
        emit UpdatedTokenInformation(s_tokenName, s_tokenSymbol, i_tokenDecimals, TOKEN_VERSION, s_tokenOnchainID);
    }

    // @audit-issue aggiustare la funzione per erc3525
    function recoveryAddress(
    address lostWallet,
    address newWallet,
    address investorOnchainID
    ) external onlyRole(OWNER_ROLE) returns (bool) {
        // balanceOf(address) → number of ERC721 tokens owned, correct for "has token?" check
        if (balanceOf(lostWallet) == 0) revert ERC3643__NoTokensToRecover();

        IIdentity onchainID = IIdentity(investorOnchainID);
        bytes32 key = keccak256(abi.encode(newWallet));

        if (!onchainID.keyHasPurpose(key, 1)) revert ERC3643__RecoveryNotPossible();

        // 1. Register the new wallet BEFORE the transfer
        //    so _beforeValueTransfer finds newWallet as verified
        s_tokenIdentityRegistry.registerIdentity(
            newWallet,
            onchainID,
            s_tokenIdentityRegistry.investorCountry(lostWallet)
        );

        // 2. Recovery flag: bypasses the SenderFrozen check in _beforeValueTransfer
        s_recovering = true;

        // 3. Delegate the transfer of tokens (ERC3525 logic) to the child contract
        _executeRecoveryTransfer(lostWallet, newWallet);

        s_recovering = false;

        // 4. Propagate the freeze at wallet level if present
        if (s_frozenWallets[lostWallet]) {
            _setAddressFrozen(newWallet, true);
            _setAddressFrozen(lostWallet, false); // unfreeze the old wallet
        }

        // 5. Remove the identity of the lost wallet
        s_tokenIdentityRegistry.deleteIdentity(lostWallet);

        emit RecoverySuccess(lostWallet, newWallet, investorOnchainID);
        return true;
    }

    /// @dev Override in TreasuryBondToken to implement ERC3525 transfer
    function _executeRecoveryTransfer(
        address lostWallet,
        address newWallet
    ) internal virtual;

    function pause() external onlyRole(OWNER_ROLE) {
        _whenNotPaused();
        s_tokenPaused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(OWNER_ROLE) {
        _whenPaused();
        s_tokenPaused = false;
        emit Unpaused(msg.sender);
    }


    function setAddressFrozen(address _userAddress, bool _freeze) external onlyRole(OWNER_ROLE) {
        _setAddressFrozen(_userAddress, _freeze);
    }


    function freezePartialTokens(uint256 _tokenId, uint256 _amount) external onlyRole(OWNER_ROLE) {
        _freezePartialToken(_tokenId, _amount);
    }

    function unfreezePartialTokens(uint256 _tokenId, uint256 _amount) external onlyRole(OWNER_ROLE) {
        _unfreezePartialToken(_tokenId, _amount);
    }

    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _setAddressFrozen(_userAddresses[i], _freeze[i]);
        }
    }


    function batchFreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external {
        for (uint256 i = 0; i < _tokenId.length; i++) {
            _freezePartialToken(_tokenId[i], _amounts[i]);
        }
    }


    function batchUnfreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external {
        for (uint256 i = 0; i < _tokenId.length; i++) {
            _unfreezePartialToken(_tokenId[i], _amounts[i]);
        }
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

    function setCompliance(address _compliance) public onlyRole(OWNER_ROLE) {
        if (address(s_tokenCompliance) != address(0)) {
            s_tokenCompliance.unbindToken(address(this));
        }
        s_tokenCompliance = IModularCompliance(_compliance);
        s_tokenCompliance.bindToken(address(this));
        emit ComplianceAdded(_compliance);
    }

    function compliance() external view  returns (IModularCompliance) {
        return s_tokenCompliance;
    }

    function paused() external view returns (bool) {
        return s_tokenPaused;
    }

    function decimals() external view returns (uint8) {
        return i_tokenDecimals;
    }

    function name() external view returns (string memory) {
        return s_tokenName;
    }

    function onchainID() external view returns (address) {
        return s_tokenOnchainID;
    }

    function symbol() external view returns (string memory) {
        return s_tokenSymbol;
    }

    function version() external pure returns (string memory) {
        return TOKEN_VERSION;
    }

    function getWalletFrozenStatus(address _wallet) external view returns (bool) {
        return s_frozenWallets[_wallet];
    }

    function getFrozenValue(uint256 _tokenId) external view returns (uint256) {
    return s_frozenValues[_tokenId];
    }

    function getAvailableValue(uint256 _tokenId) external view returns (uint256) {
        return balanceOf(_tokenId) - s_frozenValues[_tokenId];
    }

    function _beforeValueTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value) internal override{
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

    function _afterValueTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value) internal override {
            
    }


}