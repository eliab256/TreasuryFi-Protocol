//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@solvprotocol/erc-3525/IERC721.sol";
import {IERC3525} from "@solvprotocol/erc-3525/IERC3525.sol";
import {IERC721Receiver} from "@solvprotocol/erc-3525/IERC721Receiver.sol";
import {IERC3525Receiver} from "@solvprotocol/erc-3525/IERC3525Receiver.sol";
import {
    IERC721Enumerable
} from "@solvprotocol/erc-3525/extensions/IERC721Enumerable.sol";

contract ERC3525 is Context, IERC3525, IERC721Enumerable {
    error ERC3525__InvalidTokenID();
    error ERC3525__ApprovalToCurrentOwner();
    error ERC3525__CallerIsNotOwnerNorApproved();
    error ERC3525__BalanceQueryForZeroAddress();
    error ERC3525__GlobalIndexOutOfBounds();
    error ERC3525__OwnerIndexOutOfBounds();
    error ERC3525__ApproveToCaller();
    error ERC3525__InsufficientAllowance();
    error ERC3525__MintToZeroAddress();
    error ERC3525__CannotMintZeroTokenId();
    error ERC3525__TokenAlreadyMinted();
    error ERC3525__BurnValueExceedsBalance();
    error ERC3525__ApproveValueToZeroAddress();
    error ERC3525__ApproveCallerIsNotOwnerNorApprovedForAll();
    error ERC3525__TransferCallerIsNotOwnerNorApproved();

    struct TokenData {
        uint256 id;
        uint256 slot;
        uint256 balance;
        address owner;
        address approved;
        address[] valueApprovals;
    }

    struct AddressData {
        uint256[] ownedTokens;
        mapping(uint256 => uint256) ownedTokensIndex;
        mapping(address => bool) approvals;
    }

    string private s_name;
    string private s_symbol;
    uint8 private immutable i_decimals;
    uint256 private _tokenIdGenerator;

    // id => (approval => allowance)
    // @dev _approvedValues cannot be defined within TokenData, cause struct containing mappings cannot be constructed.
    mapping(uint256 => mapping(address => uint256)) private _approvedValues;

    TokenData[] private _allTokens;

    // key: id
    mapping(uint256 => uint256) private _allTokensIndex;

    mapping(address => AddressData) private _addressData;

    modifier onlyMinted(uint256 tokenId_) {
        _requireMinted(tokenId_);
        _;
    }

    modifier onlyApprovedOrOwner(uint256 tokenId_) {
        if (!_isApprovedOrOwner(_msgSender(), tokenId_)) {
            revert ERC3525__TransferCallerIsNotOwnerNorApproved();
        }
        _;
    }

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        _tokenIdGenerator = 1;
        s_name = _name;
        s_symbol = _symbol;
        i_decimals = _decimals;
    }

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override returns (bool) {
        return
            _interfaceId == type(IERC165).interfaceId ||
            _interfaceId == type(IERC3525).interfaceId ||
            _interfaceId == type(IERC721).interfaceId ||
            _interfaceId == type(IERC721Enumerable).interfaceId;
    }

    /**
     * @dev Returns the token collection name.
     */
    function name() public view virtual returns (string memory) {
        return s_name;
    }

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() public view virtual returns (string memory) {
        return s_symbol;
    }

    /**
     * @dev Returns the number of decimals the token uses for value.
     */
    function valueDecimals() public view virtual returns (uint8) {
        return i_decimals;
    }

    function balanceOf(
        uint256 _tokenId
    ) public view virtual override onlyMinted(_tokenId) returns (uint256) {
        return _allTokens[_allTokensIndex[_tokenId]].balance;
    }

    function ownerOf(
        uint256 _tokenId
    )
        public
        view
        virtual
        override
        onlyMinted(_tokenId)
        returns (address owner_)
    {
        owner_ = _allTokens[_allTokensIndex[_tokenId]].owner;
        if (owner_ == address(0)) {
            revert ERC3525__InvalidTokenID();
        }
    }

    function slotOf(
        uint256 _tokenId
    ) public view virtual override onlyMinted(_tokenId) returns (uint256) {
        return _allTokens[_allTokensIndex[_tokenId]].slot;
    }

    function approve(
        uint256 _tokenId,
        address _to,
        uint256 _value
    ) public payable virtual override onlyApprovedOrOwner(_tokenId) {
        address owner = ERC3525.ownerOf(_tokenId);
        if (_to == owner) {
            revert ERC3525__ApprovalToCurrentOwner();
        }

        _approveValue(_tokenId, _to, _value);
    }

    function allowance(
        uint256 _tokenId,
        address _operator
    ) public view virtual override onlyMinted(_tokenId) returns (uint256) {
        return _approvedValues[_tokenId][_operator];
    }

    function transferFrom(
        uint256 _fromTokenId,
        address _to,
        uint256 _value
    ) public payable virtual override returns (uint256 newTokenId) {
        _spendAllowance(_msgSender(), _fromTokenId, _value);

        newTokenId = _createDerivedTokenId(_fromTokenId);
        _mint(_to, newTokenId, ERC3525.slotOf(_fromTokenId), 0);
        _transferValue(_fromTokenId, newTokenId, _value);
    }

    function transferFrom(
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _value
    ) public payable virtual override {
        _spendAllowance(_msgSender(), _fromTokenId, _value);
        _transferValue(_fromTokenId, _toTokenId, _value);
    }

    function balanceOf(
        address _owner
    ) public view virtual override returns (uint256 balance) {
        if (_owner == address(0)) {
            revert ERC3525__BalanceQueryForZeroAddress();
        }
        return _addressData[_owner].ownedTokens.length;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable virtual override onlyApprovedOrOwner(_tokenId) {
        _transferTokenId(_from, _to, _tokenId);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public payable virtual override onlyApprovedOrOwner(_tokenId) {
        _safeTransferTokenId(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable virtual override {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function approve(
        address _to,
        uint256 _tokenId
    ) public payable virtual override {
        address owner = ERC3525.ownerOf(_tokenId);
        if (_to == owner) {
            revert ERC3525__ApprovalToCurrentOwner();
        }

        if (
            !(_msgSender() == owner ||
                ERC3525.isApprovedForAll(owner, _msgSender()))
        ) {
            revert ERC3525__ApproveCallerIsNotOwnerNorApprovedForAll();
        }

        _approve(_to, _tokenId);
    }

    function getApproved(
        uint256 _tokenId
    ) public view virtual override onlyMinted(_tokenId) returns (address) {
        return _allTokens[_allTokensIndex[_tokenId]].approved;
    }

    function setApprovalForAll(
        address _operator,
        bool _approved
    ) public virtual override {
        _setApprovalForAll(_msgSender(), _operator, _approved);
    }

    function isApprovedForAll(
        address _owner,
        address _operator
    ) public view virtual override returns (bool) {
        return _addressData[_owner].approvals[_operator];
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(
        uint256 _index
    ) public view virtual override returns (uint256) {
        if (_index >= ERC3525.totalSupply()) {
            revert ERC3525__GlobalIndexOutOfBounds();
        }
        return _allTokens[_index].id;
    }

    function tokenOfOwnerByIndex(
        address _owner,
        uint256 _index
    ) public view virtual override returns (uint256) {
        if (_index >= ERC3525.balanceOf(_owner)) {
            revert ERC3525__OwnerIndexOutOfBounds();
        }
        return _addressData[_owner].ownedTokens[_index];
    }

    function _setApprovalForAll(
        address owner_,
        address operator_,
        bool approved_
    ) internal virtual {
        if (owner_ == operator_) {
            revert ERC3525__ApproveToCaller();
        }

        _addressData[owner_].approvals[operator_] = approved_;

        emit ApprovalForAll(owner_, operator_, approved_);
    }

    function _isApprovedOrOwner(
        address operator_,
        uint256 tokenId_
    ) internal view virtual returns (bool) {
        address owner = ERC3525.ownerOf(tokenId_);
        return (operator_ == owner ||
            ERC3525.isApprovedForAll(owner, operator_) ||
            ERC3525.getApproved(tokenId_) == operator_);
    }

    function _spendAllowance(
        address operator_,
        uint256 tokenId_,
        uint256 value_
    ) internal virtual {
        uint256 currentAllowance = ERC3525.allowance(tokenId_, operator_);
        if (
            !_isApprovedOrOwner(operator_, tokenId_) &&
            currentAllowance != type(uint256).max
        ) {
            if (currentAllowance < value_) {
                revert ERC3525__InsufficientAllowance();
            }
            _approveValue(tokenId_, operator_, currentAllowance - value_);
        }
    }

    function _exists(uint256 tokenId_) internal view virtual returns (bool) {
        return
            _allTokens.length != 0 &&
            _allTokens[_allTokensIndex[tokenId_]].id == tokenId_;
    }

    function _requireMinted(uint256 tokenId_) internal view virtual {
        if (!_exists(tokenId_)) {
            revert ERC3525__InvalidTokenID();
        }
    }

    function _mint(
        address to_,
        uint256 slot_,
        uint256 value_
    ) internal virtual returns (uint256 tokenId) {
        tokenId = _createOriginalTokenId();
        _mint(to_, tokenId, slot_, value_);
    }

    function _mint(
        address to_,
        uint256 tokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual {
        if (to_ == address(0)) {
            revert ERC3525__MintToZeroAddress();
        }
        if (tokenId_ == 0) {
            revert ERC3525__CannotMintZeroTokenId();
        }
        if (_exists(tokenId_)) {
            revert ERC3525__TokenAlreadyMinted();
        }

        _beforeValueTransfer(address(0), to_, 0, tokenId_, slot_, value_);
        __mintToken(to_, tokenId_, slot_);
        __mintValue(tokenId_, value_);
        _afterValueTransfer(address(0), to_, 0, tokenId_, slot_, value_);
    }

    function _mintValue(
        uint256 tokenId_,
        uint256 value_
    ) internal virtual onlyMinted(tokenId_) {
        address owner = ERC3525.ownerOf(tokenId_);
        uint256 slot = ERC3525.slotOf(tokenId_);
        _beforeValueTransfer(address(0), owner, 0, tokenId_, slot, value_);
        __mintValue(tokenId_, value_);
        _afterValueTransfer(address(0), owner, 0, tokenId_, slot, value_);
    }

    function __mintValue(uint256 tokenId_, uint256 value_) private {
        _allTokens[_allTokensIndex[tokenId_]].balance += value_;
        emit TransferValue(0, tokenId_, value_);
    }

    function __mintToken(address to_, uint256 tokenId_, uint256 slot_) private {
        TokenData memory tokenData = TokenData({
            id: tokenId_,
            slot: slot_,
            balance: 0,
            owner: to_,
            approved: address(0),
            valueApprovals: new address[](0)
        });

        _addTokenToAllTokensEnumeration(tokenData);
        _addTokenToOwnerEnumeration(to_, tokenId_);

        emit Transfer(address(0), to_, tokenId_);
        emit SlotChanged(tokenId_, 0, slot_);
    }

    function _burn(uint256 tokenId_) internal virtual onlyMinted(tokenId_) {
        TokenData storage tokenData = _allTokens[_allTokensIndex[tokenId_]];
        address owner = tokenData.owner;
        uint256 slot = tokenData.slot;
        uint256 value = tokenData.balance;

        _beforeValueTransfer(owner, address(0), tokenId_, 0, slot, value);

        _clearApprovedValues(tokenId_);
        _removeTokenFromOwnerEnumeration(owner, tokenId_);
        _removeTokenFromAllTokensEnumeration(tokenId_);

        emit TransferValue(tokenId_, 0, value);
        emit SlotChanged(tokenId_, slot, 0);
        emit Transfer(owner, address(0), tokenId_);

        _afterValueTransfer(owner, address(0), tokenId_, 0, slot, value);
    }

    function _burnValue(
        uint256 tokenId_,
        uint256 burnValue_
    ) internal virtual onlyMinted(tokenId_) {
        TokenData storage tokenData = _allTokens[_allTokensIndex[tokenId_]];
        address owner = tokenData.owner;
        uint256 slot = tokenData.slot;
        uint256 value = tokenData.balance;

        if (value < burnValue_) {
            revert ERC3525__BurnValueExceedsBalance();
        }

        _beforeValueTransfer(owner, address(0), tokenId_, 0, slot, burnValue_);

        tokenData.balance -= burnValue_;
        emit TransferValue(tokenId_, 0, burnValue_);

        _afterValueTransfer(owner, address(0), tokenId_, 0, slot, burnValue_);
    }

    function _addTokenToOwnerEnumeration(
        address to_,
        uint256 tokenId_
    ) private {
        _allTokens[_allTokensIndex[tokenId_]].owner = to_;

        _addressData[to_].ownedTokensIndex[tokenId_] = _addressData[to_]
            .ownedTokens
            .length;
        _addressData[to_].ownedTokens.push(tokenId_);
    }

    function _removeTokenFromOwnerEnumeration(
        address from_,
        uint256 tokenId_
    ) private {
        _allTokens[_allTokensIndex[tokenId_]].owner = address(0);

        AddressData storage ownerData = _addressData[from_];
        uint256 lastTokenIndex = ownerData.ownedTokens.length - 1;
        uint256 lastTokenId = ownerData.ownedTokens[lastTokenIndex];
        uint256 tokenIndex = ownerData.ownedTokensIndex[tokenId_];

        ownerData.ownedTokens[tokenIndex] = lastTokenId;
        ownerData.ownedTokensIndex[lastTokenId] = tokenIndex;

        delete ownerData.ownedTokensIndex[tokenId_];
        ownerData.ownedTokens.pop();
    }

    function _addTokenToAllTokensEnumeration(
        TokenData memory tokenData_
    ) private {
        _allTokensIndex[tokenData_.id] = _allTokens.length;
        _allTokens.push(tokenData_);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId_) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId_];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        TokenData memory lastTokenData = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenData; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenData.id] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId_];
        _allTokens.pop();
    }

    function _approve(address to_, uint256 tokenId_) internal virtual {
        _allTokens[_allTokensIndex[tokenId_]].approved = to_;
        emit Approval(ERC3525.ownerOf(tokenId_), to_, tokenId_);
    }

    function _approveValue(
        uint256 tokenId_,
        address to_,
        uint256 value_
    ) internal virtual {
        if (to_ == address(0)) {
            revert ERC3525__ApproveValueToZeroAddress();
        }
        if (!_existApproveValue(to_, tokenId_)) {
            _allTokens[_allTokensIndex[tokenId_]].valueApprovals.push(to_);
        }
        _approvedValues[tokenId_][to_] = value_;

        emit ApprovalValue(tokenId_, to_, value_);
    }

    function _clearApprovedValues(uint256 tokenId_) internal virtual {
        TokenData storage tokenData = _allTokens[_allTokensIndex[tokenId_]];
        uint256 length = tokenData.valueApprovals.length;
        for (uint256 i = 0; i < length; i++) {
            address approval = tokenData.valueApprovals[i];
            delete _approvedValues[tokenId_][approval];
        }
        delete tokenData.valueApprovals;
    }

    function _existApproveValue(
        address to_,
        uint256 tokenId_
    ) internal view virtual returns (bool) {
        uint256 length = _allTokens[_allTokensIndex[tokenId_]]
            .valueApprovals
            .length;
        for (uint256 i = 0; i < length; i++) {
            if (
                _allTokens[_allTokensIndex[tokenId_]].valueApprovals[i] == to_
            ) {
                return true;
            }
        }
        return false;
    }

    function _transferValue(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 value_
    ) internal virtual {
        if (!_exists(fromTokenId_)) {
            revert ERC3525__InvalidTokenID();
        }
        if (!_exists(toTokenId_)) {
            revert ERC3525__InvalidTokenID();
        }

        TokenData storage fromTokenData = _allTokens[
            _allTokensIndex[fromTokenId_]
        ];
        TokenData storage toTokenData = _allTokens[_allTokensIndex[toTokenId_]];

        if (fromTokenData.balance < value_) {
            revert ERC3525__BurnValueExceedsBalance();
        }
        if (fromTokenData.slot != toTokenData.slot) {
            revert ERC3525__GlobalIndexOutOfBounds();
        }

        _beforeValueTransfer(
            fromTokenData.owner,
            toTokenData.owner,
            fromTokenId_,
            toTokenId_,
            fromTokenData.slot,
            value_
        );

        fromTokenData.balance -= value_;
        toTokenData.balance += value_;

        emit TransferValue(fromTokenId_, toTokenId_, value_);

        _afterValueTransfer(
            fromTokenData.owner,
            toTokenData.owner,
            fromTokenId_,
            toTokenId_,
            fromTokenData.slot,
            value_
        );

        if (!_checkOnERC3525Received(fromTokenId_, toTokenId_, value_, "")) {
            revert("ERC3525: transfer rejected by ERC3525Receiver");
        }
    }

    function _transferTokenId(
        address from_,
        address to_,
        uint256 tokenId_
    ) internal virtual {
        if (ERC3525.ownerOf(tokenId_) != from_) {
            revert ERC3525__CallerIsNotOwnerNorApproved();
        }
        if (to_ == address(0)) {
            revert ERC3525__MintToZeroAddress();
        }

        uint256 slot = ERC3525.slotOf(tokenId_);
        uint256 value = ERC3525.balanceOf(tokenId_);

        _beforeValueTransfer(from_, to_, tokenId_, tokenId_, slot, value);

        _approve(address(0), tokenId_);
        _clearApprovedValues(tokenId_);

        _removeTokenFromOwnerEnumeration(from_, tokenId_);
        _addTokenToOwnerEnumeration(to_, tokenId_);

        emit Transfer(from_, to_, tokenId_);

        _afterValueTransfer(from_, to_, tokenId_, tokenId_, slot, value);
    }

    function _safeTransferTokenId(
        address from_,
        address to_,
        uint256 tokenId_,
        bytes memory data_
    ) internal virtual {
        _transferTokenId(from_, to_, tokenId_);
        if (!_checkOnERC721Received(from_, to_, tokenId_, data_)) {
            revert("ERC3525: transfer to non ERC721Receiver");
        }
    }

    function _checkOnERC3525Received(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 value_,
        bytes memory data_
    ) internal virtual returns (bool) {
        address to = ERC3525.ownerOf(toTokenId_);
        if (_isContract(to)) {
            try
                IERC165(to).supportsInterface(
                    type(IERC3525Receiver).interfaceId
                )
            returns (bool retval) {
                if (retval) {
                    bytes4 receivedVal = IERC3525Receiver(to).onERC3525Received(
                        _msgSender(),
                        fromTokenId_,
                        toTokenId_,
                        value_,
                        data_
                    );
                    return
                        receivedVal ==
                        IERC3525Receiver.onERC3525Received.selector;
                } else {
                    return true;
                }
            } catch (bytes memory /** reason */) {
                return true;
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from_ address representing the previous owner of the given token ID
     * @param to_ target address that will receive the tokens
     * @param tokenId_ uint256 ID of the token to be transferred
     * @param data_ bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from_,
        address to_,
        uint256 tokenId_,
        bytes memory data_
    ) private returns (bool) {
        if (_isContract(to_)) {
            try
                IERC721Receiver(to_).onERC721Received(
                    _msgSender(),
                    from_,
                    tokenId_,
                    data_
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /* solhint-disable */
    function _beforeValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual {}

    function _afterValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual {}
    /* solhint-enable */

    function _createOriginalTokenId() internal virtual returns (uint256) {
        return _tokenIdGenerator++;
    }

    function _createDerivedTokenId(
        uint256 fromTokenId_
    ) internal virtual returns (uint256) {
        fromTokenId_;
        return _createOriginalTokenId();
    }

    function _isContract(address addr_) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(addr_)
        }
        return (size > 0);
    }
}
