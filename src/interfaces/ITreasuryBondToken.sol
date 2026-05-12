//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {PositionData} from "../types.sol";
import {IERC3525} from "./IERC3525.sol";

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


    // --- RiskManager ---

    /**
     * @notice Updates the risk manager yields values from the oracle.
     * @dev Normally called by UpdateRiskManagerAutomation via UPDATE_RISK_MANAGER_VALUES_ROLE.
     * The deployer retains this role as emergency fallback in case Chainlink Automation
     * stops functioning, allowing manual intervention without governance delay.
     */
    function updateYieldsValues() external;

    /**
     * @notice Updates the risk manager reserves and liquidity buffers values from the oracle.
     * @dev Normally called by UpdateRiskManagerAutomation via UPDATE_RISK_MANAGER_VALUES_ROLE.
     * The deployer retains this role as emergency fallback in case Chainlink Automation
     * stops functioning, allowing manual intervention without governance delay.
     */
    function updateReserveValues() external;

    /**
     * @notice Function to manually trigger the reserves upkeep.
     * @dev Can only be called by an account with the AUTOMATION_TRIGGERER_ROLE.
     * @dev Internal function inherited from RiskManager.
     */
    function triggerReservesUpkeep() external;

    /**
     * @notice Function to manually trigger the bond yields upkeep.
     * @dev Can only be called by an account with the AUTOMATION_TRIGGERER_ROLE.
     * @dev Internal function inherited from RiskManager.
     */
    function triggerYieldsUpkeep() external;

    // --- Positions ---
    function openNewPosition(address _mintTo, uint256 _slot, uint256 _value) external;
    function closePosition(uint256 _tokenId) external;
    function closePartialPosition(uint256 _tokenId, uint256 _valueToBurn) external;
    function claimYield(uint256 _tokenId) external;

    // --- ERC3525/ERC721 ---
    // function ownerOf(uint256 tokenId) external view returns (address);
    // function balanceOf(uint256 tokenId) external view returns (uint256);
    // function balanceOf(address owner) external view returns (uint256);
    // function transferFrom(uint256 _fromTokenId, address _to, uint256 _value) external payable returns (uint256);

    /**
     * @notice Disabled function to prevent transfers between tokens.
     * @dev This function is intentionally disabled to enforce the non-transferable nature of the tokens.
     */
    // function transferFrom(uint256, uint256, uint256) external payable;
    // function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    // function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) external payable;
    // function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;

    // --- Getters ---
    function getTotalLiabilitiesPerSlot(uint256 _slot) external view returns (uint256);
    function getPositionData(uint256 _tokenId) external view returns (PositionData memory);
    // function name() external view returns (string memory);
    // function symbol() external view returns (string memory);
    // function valueDecimals() external view returns (uint8);

    // --- Compliance/Admin public functions for ERC3643 ---

    /**
     * @notice Sets the address of the IdentityRegistry contract from internal function in ERC3643 abstract contract.
     * @dev check _setIdentityRegistry in ERC3643 for details.
     * @param _identityRegistry The address of the IdentityRegistry contract.
     */
    function setIdentityRegistry(address _identityRegistry) external;

    /**
     * @notice Sets the address of the OnchainID contract from internal function in ERC3643 abstract contract.
     * @dev check _setOnchainID in ERC3643 for details.
     * @param _onchainID The address of the OnchainID contract.
     */
    function setOnchainID(address _onchainID) external;

    /**
     * @notice Sets the address of the Compliance contract from internal function in ERC3643 abstract contract.
     * @dev check _setCompliance in ERC3643 for details.
     * @param _compliance The address of the Compliance contract.
     */
    function setCompliance(address _compliance) external;

    /**
     * @notice Pauses all token transfers and operations.
     * @dev check _pause in ERC3643 for details.
     */
    function pause() external;

    /**
     * @notice Unpauses all token transfers and operations.
     * @dev check _unpause in ERC3643 for details.
     */
    function unpause() external;


    function setAddressFrozen(address _userAddress, bool _freeze) external;
    function freezePartialTokens(uint256 _tokenId, uint256 _amount) external;
    function unfreezePartialTokens(uint256 _tokenId, uint256 _amount) external;
    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external;
    function batchFreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external;
    function batchUnfreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external;

    /**
     * @notice Forces the transfer of a token from one wallet to another on behalf of a regulatory authority.
     * @dev Bypasses standard compliance checks (frozen sender/receiver, paused state).
     *      The receiver must still be a verified identity in the IdentityRegistry.
     *      Accrued yield is settled to _from before the transfer.
     *      Any frozen value on the token is released before the transfer is executed.
     * @param _from The current owner of the token.
     * @param _to   The receiver of the token. Must be KYC-verified.
     * @param _tokenId The token to transfer.
     * @return bool true if successful.
     */
    function forceTransfer(address _from, address _to, uint256 _tokenId) external returns (bool);
}

