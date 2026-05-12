//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasuryBondToken {
    // ------ Events ------
    event PositionOpened(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed slot,
        uint256 usdcDeposited,         
        uint256 valueMinted,      
        uint256 entryNAV      
    );
    event PositionClosed(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed slot,
        uint256 valueBurned,
        uint256 usdcPayout,
        uint256 exitNAV
    );
    event PartialPositionClosed(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed slot,
        uint256 valueBurned,
        uint256 valueRemaining,  // used on partial only
        uint256 usdcPayout,
        uint256 exitNAV
    );
    event YieldClaimed(address indexed user, uint256 indexed tokenId, uint256 yieldAmount, uint256 feeCollected);
    event ForceTransfer(address indexed from, address indexed to, uint256 indexed tokenId, uint256 value);
    event EntryFeeCollected(address indexed user, uint256 amount);
    event ExitFeeCollected(address indexed user, uint256 amount);
    event YieldFeeCollected(address indexed user, uint256 amount);
    event IdentityRegistrySet(address indexed identityRegistry);

    // ------ Errors ------
    error TreasuryBondToken__InvalidSlot();
    error TreasuryBondToken__FunctionDisabled();
    error TreasuryBondToken__NotApprovedOrOwner();
    error TreasuryBondToken__EtherNotAccepted();
    error TreasuryBondToken__InvalidValue();
    error TreasuryBondToken__ZeroAddress();
    error TreasuryBondToken__InvalidOracle(address oracle, bytes4 interfaceId);
    error TreasuryBondToken__InvalidAutomation(address automation, bytes4 interfaceId);
    error TreasuryBondToken__SenderNotVerified();
    error TreasuryBondToken__ReceiverNotVerified();
    error TreasuryBondToken__WalletAlreadyFrozen();
    error TreasuryBondToken__WalletNotFrozen();
    error TreasuryBondToken__AmountExceedsAvailableBalance();
    error TreasuryBondToken__AmountShouldBeLessOrEqualToFrozen();
    error TreasuryBondToken__LockPeriodNotElapsed();
    error TreasuryBondToken__InvalidTokenOwner();
    error TreasuryBondToken__ForcedTransferFailed();
}
