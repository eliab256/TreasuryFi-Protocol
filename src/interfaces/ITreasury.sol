//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    // ------ Errors ------
    error Treasury__ZeroAddress();
    error Treasury__TokenContractAlreadySet();
    error Treasury__AmountExceedsTotalFeesToBeCollected();
    error Treasury__AmountExceedsFeesToBeCollected();
    error Treasury__InsufficientLiquidity();
    error TreasuryBondToken__InvalidSlot();
    error Treasury__InvalidArrayInput();

    // ------ Events ------
    event usdcDepositedFromOpenNewPosition(uint256 indexed amount, address indexed from, uint256 indexed slot);
    event usdcWithdrawnFromClosePosition(uint256 indexed amount, address indexed to, uint256 indexed slot);
    event LiquidityInjected(uint256 indexed amount, uint256 indexed slot);
    event FeesUsedToInjectLiquidity(uint256 indexed amount, uint256 indexed slot);
    event FeesCollected(uint256 indexed amount, address indexed to);
    event usdcWithdrawnFromClaimYield(uint256 indexed amount, address indexed to, uint256 indexed slot);
    event FeeGenerated(uint256 indexed depositFee, uint256 indexed yieldFee, uint256 indexed exitFee, uint256 slot);


    // ------ Main functions ------

    /**
     * @notice Sets the token contract address that is allowed to interact with the treasury.
     * @dev Only callable by admin. This is used to set the TreasuryBondToken contract as the only contract that can call the treasury's main functions.
     * @param _tokenContract The address of the token contract.
     */
    function setTokenContract(address _tokenContract) external;

    /**
     * @notice Handles USDC deposits when opening a new position. 
     * @dev Access control ensures only the TreasuryBondToken can call this function.
     * @param _amount The amount of USDC being deposited by the user (net of fees).
     * @param _from The address of the user depositing USDC.
     * @param _slot The slot corresponding to the bond being purchased (2Y, 5Y, 10Y, or 30Y).
     * @param _feeAmount The amount of fees collected on this deposit, used for fee accounting.
     */
    function depositUsdcFromOpenNewPosition(uint256 _amount, address _from, uint256 _slot, uint256 _feeAmount) external; 

    /**
     * @notice Handles USDC withdrawals when closing a position. 
     * @param _usdcPayout The amount of USDC being withdrawn by the user (net of fees).
     * @param _to The address of the user withdrawing USDC.
     * @param _slot The slot corresponding to the bond being closed (2Y, 5Y, 10Y, or 30Y).
     * @param _yieldPayout The amount of yield being paid out to the user before closing the position.
     * @param _exitFee The amount of exit fees calculated on the USDC payout if the position is closed 
     *        before the penalty period, used for fee accounting.
     * @param _managementFee The amount of management fees calculated on the remaining yield amount, used for fee accounting.
     */
    function withdrawUsdcFromClosePosition(uint256 _usdcPayout, address _to, uint256 _slot, uint256 _yieldPayout, uint256 _exitFee, uint256 _managementFee) external;

    /**
     * @notice Handles USDC transfers when claiming yield.
     * @param _yieldPayout The amount of yield being paid out to the user.
     * @param _to The address of the user receiving the yield.
     * @param _slot The slot corresponding to the bond for which yield is being claimed (2Y, 5Y, 10Y, or 30Y).
     * @param _feeOnYield The amount of fees collected on the yield, used for fee accounting.
     */
    function transferUsdcFromYieldClaim(uint256 _yieldPayout, address _to, uint256 _slot, uint256 _feeOnYield) external;

    /**
     * @notice Handles USDC injections into the treasury.
     * @dev    Only callable by admin to allow manual liquidity injections.
     * @param _amount The amount of USDC being injected.
     * @param _slot The slot corresponding to the bond for which liquidity is being injected (2Y, 5Y, 10Y, or 30Y).
     */
    function injectLiquidity(uint256 _amount, uint256 _slot) external;

    /**
     * @notice Handles USDC injections into the treasury for multiple slots.
     * @dev    Only callable by admin to allow manual liquidity injections.
     * @param _amounts The amounts of USDC being injected for each slot.
     * @param _slots The slots corresponding to the bonds for which liquidity is being injected (2Y, 5Y, 10Y, or 30Y).
     */
    function injectLiquidityOnMultipleSlots(uint256[] calldata _amounts, uint256[] calldata _slots) external;

    /**
     * @notice Uses the fees collected to inject liquidity into the treasury.
     * @dev    Only callable by admin to allow using collected fees for liquidity. Used to avoid two separate transactions 
     *         for collecting fees and injecting liquidity, allowing for more efficient treasury management.
     * @param _amount The amount of USDC being injected, can be set to type(uint256).max to use all available fees.
     * @param _slot The slot corresponding to the bond for which liquidity is being injected (2Y, 5Y, 10Y, or 30Y).
     */
    function useFeesCollectedToInjectLiquidity(uint256 _amount, uint256 _slot) external;

    /**
     * @notice Collects the fees accumulated in the treasury.
     * @dev    Only callable by admin to allow fee collection.
     * @param _amount The amount of USDC being collected.
     * @param _to The address to which the collected fees will be sent.
     */
    function collectFees(uint256 _amount, address _to) external;

    // ------ Getters ------

    /**
     * @notice Returns the total fees collected in the treasury.
     * @dev   This includes all fees that have been generated and are either still in the treasury or have already been collected by the admin.
     * @return The total fees collected.
     */
    function getTotalFeesCollected() external view returns (uint256);

    /**
     * @notice Returns the total fees to be collected in the treasury.
     * @dev   This includes all fees that have been generated but have not yet been collected by the admin. 
     *        This is used to track how much fees are still available for collection.
     * @return The total fees to be collected.
     */
    function getTotalFeesToBeCollected() external view returns (uint256);

    /**
     * @notice Returns the total USDC liquidity for a specific slot.
     * @dev   This includes all USDC liquidity deposited by users to open new positions 
     *        in that slot as well as any liquidity injected by the admin.
     * @param _slot The slot corresponding to the bond (2Y, 5Y, 10Y, or 30Y).
     * @return The total USDC liquidity for the specified slot.
     */
    function getTotalUsdcLiquidityPerSlot(uint256 _slot) external view returns (uint256);

    /**
     * @notice Returns the address of the USDC token contract.
     * @return The address of the USDC token.
     */
    function getUsdcAddress() external view returns (address);

}