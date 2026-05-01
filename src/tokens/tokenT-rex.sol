//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// import "./IToken.sol";
// import "@onchain-id/solidity/contracts/interface/IIdentity.sol";
// import "./TokenStorage.sol";
// import "../roles/AgentRoleUpgradeable.sol";

// contract Token is IToken, AgentRoleUpgradeable, TokenStorage {


//     /**
//      *  @dev See {IToken-batchTransfer}.
//      */
//     function batchTransfer(address[] calldata _toList, uint256[] calldata _amounts) external override {
//         for (uint256 i = 0; i < _toList.length; i++) {
//             transfer(_toList[i], _amounts[i]);
//         }
//     }



//     /**
//      *  @dev See {IToken-batchForcedTransfer}.
//      */
//     function batchForcedTransfer(
//         address[] calldata _fromList,
//         address[] calldata _toList,
//         uint256[] calldata _amounts
//     ) external override {
//         for (uint256 i = 0; i < _fromList.length; i++) {
//             forcedTransfer(_fromList[i], _toList[i], _amounts[i]);
//         }
//     }

//     /**
//      *  @dev See {IToken-batchMint}.
//      */
//     function batchMint(address[] calldata _toList, uint256[] calldata _amounts) external override {
//         for (uint256 i = 0; i < _toList.length; i++) {
//             mint(_toList[i], _amounts[i]);
//         }
//     }

//     /**
//      *  @dev See {IToken-batchBurn}.
//      */
//     function batchBurn(address[] calldata _userAddresses, uint256[] calldata _amounts) external override {
//         for (uint256 i = 0; i < _userAddresses.length; i++) {
//             burn(_userAddresses[i], _amounts[i]);
//         }
//     }


//     /**
//      *  @dev See {IToken-forcedTransfer}.
//      */
//     function forcedTransfer(
//         address _from,
//         address _to,
//         uint256 _amount
//     ) public override onlyAgent returns (bool) {
//         require(balanceOf(_from) >= _amount, "sender balance too low");
//         uint256 freeBalance = balanceOf(_from) - (_frozenTokens[_from]);
//         if (_amount > freeBalance) {
//             uint256 tokensToUnfreeze = _amount - (freeBalance);
//             _frozenTokens[_from] = _frozenTokens[_from] - (tokensToUnfreeze);
//             emit TokensUnfrozen(_from, tokensToUnfreeze);
//         }
//         if (_tokenIdentityRegistry.isVerified(_to)) {
//             _transfer(_from, _to, _amount);
//             _tokenCompliance.transferred(_from, _to, _amount);
//             return true;
//         }
//         revert("Transfer not possible");
//     }






// }
