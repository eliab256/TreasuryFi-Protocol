//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IToken} from "@t-rex/token/IToken.sol";
import {IIdentityRegistry} from "@t-rex/identity-registry/IIdentityRegistry.sol";
import {IModularCompliance} from "@t-rex/compliance/modular/IModularCompliance.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ERC3643 is IToken {

    /// @dev Token information
    string internal   s_tokenName;
    string internal  s_tokenSymbol;
    uint8 internal immutable i_tokenDecimals;
    address internal s_tokenOnchainID;
    string internal constant _TOKEN_VERSION = "4.1.3";

    /// @dev Variables of freeze and pause functions
    mapping(address => bool) internal s_frozenWallets;
    mapping(address => uint256) internal s_frozenTokens;

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
    ) Ownable() {
        if (bytes(_name).length == 0) revert ERC3643__InvalidName();
        if (bytes(_symbol).length == 0)
            revert ERC3643__InvalidSymbol();
        if (_decimals == 0 || _decimals > 18)
            revert ERC3643__InvalidDecimals();
        s_tokenName = _name;
        s_tokenSymbol = _symbol;
        i_tokenDecimals = _decimals;
        s_tokenOnchainID = _onchainID;
        setIdentityRegistry(_identityRegistry);
        setCompliance(_compliance);
    }

    /**
     *  @dev See {IToken-setIdentityRegistry}.
     */
    function setIdentityRegistry(
        address _identityRegistry
    ) public onlyOwner {
         if (_identityRegistry == address(0)) revert ERC3643__ZeroAddress();
        s_tokenIdentityRegistry = IIdentityRegistry(_identityRegistry);
        emit IdentityRegistryAdded(_identityRegistry);
    }

    /**
     *  @dev See {IToken-setName}.
     */
    function setName(string calldata _name) external override onlyOwner {
          if (bytes(_name).length == 0) revert ERC3643__InvalidName();
        s_tokenName = _name;
        emit UpdatedTokenInformation(s_tokenName, s_tokenSymbol, i_tokenDecimals, _TOKEN_VERSION, s_tokenOnchainID);
    }

    /**
     *  @dev See {IToken-setSymbol}.
     */
    function setSymbol(string calldata _symbol) external override onlyOwner {
        if (bytes(_symbol).length == 0) revert ERC3643__InvalidSymbol();
        s_tokenSymbol = _symbol;
        emit UpdatedTokenInformation(s_tokenName, s_tokenSymbol, i_tokenDecimals, _TOKEN_VERSION, s_tokenOnchainID);
    }

    /**
     *  @dev See {IToken-setOnchainID}.
     *  if _onchainID is set at zero address it means no ONCHAINID is bound to this token
     */
    function setOnchainID(address _onchainID) external override onlyOwner {
        s_tokenOnchainID = _onchainID;
        emit UpdatedTokenInformation(_tokenName, _tokenSymbol, _tokenDecimals, _TOKEN_VERSION, _tokenOnchainID);
    }

    /**
     *  @dev See {IToken-pause}.
     */
    function pause() external override onlyAgent whenNotPaused {
        s_tokenPaused = true;
        emit Paused(msg.sender);
    }

    /**
     *  @dev See {IToken-unpause}.
     */
    function unpause() external override onlyAgent whenPaused {
        _tokenPaused = false;
        emit Unpaused(msg.sender);
    }


    function setAddressFrozen(address _userAddress, bool _freeze) external onlyRole(OWNER_ROLE) {
         _setAddressFrozen(_userAddress, _freeze);
    }


    function freezePartialTokens(address _userAddress, uint256 _amount) external onlyRole(OWNER_ROLE) {
        _freezPartialTokens(_userAddress, _amount);
    }

    function unfreezePartialTokens(address _userAddress, uint256 _amount) external onlyRole(OWNER_ROLE) {
        _unfreezePartialTokens(_userAddress, _amount);
    }

    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _setAddressFrozen(_userAddresses[i], _freeze[i]);
        }
    }


    function batchFreezePartialTokens(address[] calldata _userAddresses, uint256[] calldata _amounts) external {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _freezePartialTokens(_userAddresses[i], _amounts[i]);
        }
    }

    /**
     *  @dev See {IToken-batchUnfreezePartialTokens}.
     */
    function batchUnfreezePartialTokens(address[] calldata _userAddresses, uint256[] calldata _amounts) external {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            unfreezePartialTokens(_userAddresses[i], _amounts[i]);
        }
    }


    function _setAddressFrozen(address _userAddress, bool _freeze) internal {
        s_frozen[_userAddress] = _freeze;

        emit AddressFrozen(_userAddress, _freeze, msg.sender);
    }

    function _freezPartialTokens(address _userAddress, uint256 _amount) internal {
        uint256 balance = balanceOf(_userAddress);
        uint256 frozenTokens = s_frozenTokens[_userAddress];
        if (balance < frozenTokens + _amount) {
            revert ERC3643__AmountExceedsAvailableBalance();
        }
        s_frozenTokens[_userAddress] = frozenTokens + (_amount);
        emit TokensFrozen(_userAddress, _amount);
    }

    function _unfreezePartialTokens(address _userAddress, uint256 _amount) internal {
        uint256 frozenTokens = s_frozenTokens[_userAddress];
        if (frozenTokens < _amount) {
            revert ERC3643__AmountShouldBeLessOrEqualToFrozen();
        }
        s_frozenTokens[_userAddress] = frozenTokens - (_amount);
        emit TokensUnfrozen(_userAddress, _amount);
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

    /**
     *  @dev See {IToken-setCompliance}.
     */
    function setCompliance(address _compliance) public override onlyOwner {
        if (address(_tokenCompliance) != address(0)) {
            _tokenCompliance.unbindToken(address(this));
        }
        s_tokenCompliance = IModularCompliance(_compliance);
        s_tokenCompliance.bindToken(address(this));
        emit ComplianceAdded(_compliance);
    }

    /**
     *  @dev See {IToken-compliance}.
     */
    function compliance() external view override returns (IModularCompliance) {
        return s_tokenCompliance;
    }

    /**
     *  @dev See {IToken-paused}.
     */
    function paused() external view override returns (bool) {
        return s_tokenPaused;
    }


    /**
     *  @dev See {IToken-decimals}.
     */
    function decimals() external view override returns (uint8) {
        return i_tokenDecimals;
    }

    /**
     *  @dev See {IToken-name}.
     */
    function name() external view override returns (string memory) {
        return s_tokenName;
    }

    /**
     *  @dev See {IToken-onchainID}.
     */
    function onchainID() external view override returns (address) {
        return s_tokenOnchainID;
    }

    /**
     *  @dev See {IToken-symbol}.
     */
    function symbol() external view override returns (string memory) {
        return s_tokenSymbol;
    }

    /**
     *  @dev See {IToken-version}.
     */
    function version() external pure override returns (string memory) {
        return _TOKEN_VERSION;
    }


}