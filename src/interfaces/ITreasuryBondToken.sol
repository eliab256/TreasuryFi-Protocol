//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {PositionData, SlotRiskParams} from "../types.sol";
import {IERC3525} from "./IERC3525.sol";
import {IERC3643} from "./IERC3643.sol";
import {IRiskManager} from "./IRiskManager.sol";
import {IUsdcUsdConverter} from "./IUsdcUsdConverter.sol";

interface ITreasuryBondToken is IERC3643 , IERC3525  , IRiskManager, IUsdcUsdConverter {
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

    // ------ Errors ------
    error TreasuryBondToken__InvalidSlot();
    error TreasuryBondToken__FunctionDisabled();
    error TreasuryBondToken__EtherNotAccepted();
    error TreasuryBondToken__InvalidValue();
    error TreasuryBondToken__ZeroAddress();
    error TreasuryBondToken__InvalidOracle(address oracle, bytes4 interfaceId);
    error TreasuryBondToken__InvalidAutomation(address automation, bytes4 interfaceId);
    error TreasuryBondToken__LockPeriodNotElapsed();
    error TreasuryBondToken__InvalidTokenOwner();
    error TreasuryBondToken__ForcedTransferFailed();


    // --- Admin ---

    /**
     * @notice Grants UPDATE_RISK_MANAGER_VALUES_ROLE to the given automation contract.
     * @param _updateRiskManagerAutomation The address of the automation contract.
     */
    function setUpdateRiskManagerAutomation(address _updateRiskManagerAutomation) external;

    /**
     * @notice Sets the risk parameters for a given slot.
     * @param _slot The slot to configure.
     * @param _params The risk parameters to apply.
     */
    function setSlotRiskParams(uint256 _slot, SlotRiskParams memory _params) external;

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

    /**
     * @notice Opens a new position by minting a new token.
     * @param _mintTo The address to mint the new token to.
     * @param _slot The slot to associate with the new position.
     * @param _value The value to deposit for the new position in USDC.
     * @return newTokenId The ID of the newly minted token.
     */
    function openNewPosition(address _mintTo, uint256 _slot, uint256 _value) external returns(uint256 newTokenId);
    
    /**
     * @notice Closes an entire existing position by burning the token and paying out USDC.
     * @param _tokenId The ID of the token representing the position to close.
     */
    function closePosition(uint256 _tokenId) external;

    /**
     * @notice Closes a partial position by burning a specified amount of the token and paying out USDC.
     * @param _tokenId The ID of the token representing the position to close.
     * @param _valueToBurn The amount of the token to burn.
     */
    function closePartialPosition(uint256 _tokenId, uint256 _valueToBurn) external;

    /**
     * @notice Claims the accrued yield for a given position.
     * @param _tokenId The ID of the token representing the position.
     */
    function claimYield(uint256 _tokenId) external;

    // --- ERC3525/ERC721 ---
    /**
     * @notice Disabled function to prevent transfers between tokens.
     * @dev This function is intentionally disabled to enforce the non-transferable nature of the tokens.
     */
    // function transferFrom(uint256, uint256, uint256) external payable;

    // --- Getters ---
    function getTotalLiabilitiesPerSlot(uint256 _slot) external view returns (uint256);
    function getPositionData(uint256 _tokenId) external view returns (PositionData memory);

    /**
     * @notice Calculates the claimable yield in USDC for a given tokenId based on current timestamp.
     * @dev This function:
     *      1. Retrieves position data (entryYield, lastClaimTimestamp)
     *      2. Calculates principal in USD based on token balance and entryNAV
     *      3. Calculates time elapsed since last claim
     *      4. Computes gross accrued yield: principal * yield * elapsed / (365 days * MAX_PERCENTAGE)
     *      5. Deducts management fee from gross accrued
     *      6. Converts net yield from USD (18 decimals) to USDC (6 decimals)
     * @param _tokenId The ERC-3525 token ID representing the position.
     * @return claimableYieldUsdc The net claimable yield in USDC (after fees), with 6 decimals.
     */
    function getClaimableYieldInUsdc(uint256 _tokenId) external view returns (uint256);
    function getMinimumDepositAmount() external view returns (uint256);
    function assertSolvency() external view;
    function getNextRedemptionWindow(uint256 _slot) external view returns (uint256 nextWindowOpen, uint256 windowDuration);

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

