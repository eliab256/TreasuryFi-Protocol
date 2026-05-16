//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC3525} from "./ERC3525.sol";
import {ERC3643} from "./ERC3643.sol";
import {IModularCompliance} from "@t-rex/compliance/modular/IModularCompliance.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {YieldsMath} from "../library/YieldsMath.sol";
import {RiskManager} from "./RiskManager.sol";
import {UsdcUsdConverter} from "./UsdcUsdConverter.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PositionData, TreasuryBondTokenConstructorParams, SlotRiskParams} from "../types.sol";
import {TokenConstants as C} from "./TokenConstants.sol";
import {IBondAutomation} from "../interfaces/IBondAutomation.sol";
import {IReservesAutomation} from "../interfaces/IReservesAutomation.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {ITreasuryBondToken} from "../interfaces/ITreasuryBondToken.sol";

/**
 * @title TreasuryBondToken
 * @notice ERC-3525 token representing fractionalized positions in US Treasury bond buckets.
 * Each slot corresponds to a different bond maturity (2Y, 5Y, 10Y, 30Y).
 * Users can open new positions by depositing USDC and minting tokens, or close positions by burning tokens and withdrawing USDC.
 * The contract includes role-based access control for fee management and administrative functions.
 */
contract TreasuryBondToken is ITreasuryBondToken, ERC3643, ERC3525, RiskManager, UsdcUsdConverter, ReentrancyGuard, AccessControl{
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE"); 
    bytes32 public constant FEES_MANAGER_ROLE = keccak256("FEES_MANAGER_ROLE");
    bytes32 public constant AUTOMATION_TRIGGERER_ROLE = keccak256("AUTOMATION_TRIGGERER_ROLE");
    bytes32 public constant UPDATE_RISK_MANAGER_VALUES_ROLE = keccak256("UPDATE_RISK_MANAGER_VALUES_ROLE");

    uint256 private immutable i_minimumDepositAmount; // 10 USDC

    /// @dev mapping from token ID to position data, which includes the entry yield and 
    ///      the timestamp of when the position was opened.
    mapping(uint256 => PositionData) private s_fromIdToPositionData;


    modifier onlyValidSlot(uint256 slot) {
        _onlyValidSlot(slot);
        _;
    }

    modifier onlySlotWithRiskParamsSet(uint256 slot) {
        _onlyValidSlot(slot);
        _checkSlotRiskParamsSet(slot);
        _;
    }

    modifier etherNotAccepted() {
        _notAcceptEther();
        _;
    }
    
    /**
     * @notice Constructor for the TreasuryBondToken contract.
     * @dev All checks are done on this constructor and then are passed to the respective parent constructors. 
     *      This is to ensure that if any of the parameters are invalid, the deployment will fail before any 
     *      state changes occur in the parent contracts.
     * @param _params The parameters required for initializing the contract. Check types.sol for details.
     */
    constructor(
        TreasuryBondTokenConstructorParams memory _params
    ) ERC3643("TreasuryFi Bond Token", "TBT", _params.decimalsStandard, address(this), _params.identityRegistry, address(0)) 
    ERC3525("TreasuryFi Bond Token", "TBT", _params.decimalsStandard) 
    RiskManager(_params.bondAutomation, _params.reservesAutomation, _params.reservesOracle, _params.bondOracle, _params.treasury)
    UsdcUsdConverter(_params.usdcAddress, _params.usdcPriceFeedAddress, _params.decimalsStandard){
        // Checks for zero addresses
        
        if (
            _params.usdcAddress == address(0) ||
            _params.usdcPriceFeedAddress == address(0) ||
            _params.feesCollector == address(0) ||
            _params.bondAutomation == address(0) ||
            _params.reservesAutomation == address(0) ||
            _params.reservesOracle == address(0) ||
            _params.bondOracle == address(0) ||
            _params.treasury == address(0)
        ) revert TreasuryBondToken__ZeroAddress();

        // ERC165 interface checks for oracles
        if (!IERC165(_params.bondOracle).supportsInterface(type(IBondOracle).interfaceId)) {
            revert TreasuryBondToken__InvalidOracle(
                _params.bondOracle,
                type(IBondOracle).interfaceId
            );
        }
        if (!IERC165(_params.reservesOracle).supportsInterface(type(IReservesOracle).interfaceId)) {
            revert TreasuryBondToken__InvalidOracle(
                _params.reservesOracle,
                type(IReservesOracle).interfaceId
            );
        }

        // ERC165 interface checks for automations
        if (!IERC165(_params.bondAutomation).supportsInterface(type(IBondAutomation).interfaceId)) {
            revert TreasuryBondToken__InvalidAutomation(
                _params.bondAutomation,
                type(IBondAutomation).interfaceId
            );
        }
        if (!IERC165(_params.reservesAutomation).supportsInterface(type(IReservesAutomation).interfaceId)) {
            revert TreasuryBondToken__InvalidAutomation(
                _params.reservesAutomation,
                type(IReservesAutomation).interfaceId
            );
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(FEES_MANAGER_ROLE, _params.feesCollector);
        _grantRole(AUTOMATION_TRIGGERER_ROLE, msg.sender);
        _grantRole(UPDATE_RISK_MANAGER_VALUES_ROLE, msg.sender);

        i_minimumDepositAmount = 10 * (10 ** i_usdcDecimals); // 10 USDC with decimals
    }

    function setUpdateRiskManagerAutomation(address _updateRiskManagerAutomation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_updateRiskManagerAutomation == address(0)) revert TreasuryBondToken__ZeroAddress();
        _grantRole(UPDATE_RISK_MANAGER_VALUES_ROLE, _updateRiskManagerAutomation);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC3525, AccessControl) returns (bool) {
         return ERC3525.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

////////////////////////////////////////////////////////////////////
///////////////////// RiskManager inheritance ////////////////////// 
////////////////////////////////////////////////////////////////////  

    /// @dev Inherited from RiskManager. See parent contract for details.
    function setSlotRiskParams(uint256 _slot, SlotRiskParams memory _params) public onlyRole(OWNER_ROLE) onlyValidSlot(_slot) {
        _setSlotRiskParams(_slot, _params);
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function triggerReservesUpkeep() public onlyRole(AUTOMATION_TRIGGERER_ROLE) {
        _triggerReservesUpkeep();
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function triggerYieldsUpkeep() public onlyRole(AUTOMATION_TRIGGERER_ROLE) {
        _triggerYieldsUpkeep();
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function updateYieldsValues() public onlyRole(UPDATE_RISK_MANAGER_VALUES_ROLE) {
        _updateYieldsValues();
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function updateReserveValues() public onlyRole(UPDATE_RISK_MANAGER_VALUES_ROLE) {
        _updateReservesValues();
    }

////////////////////////////////////////////////////////////////////
/////////////////// Positions related functions //////////////////// 
////////////////////////////////////////////////////////////////////  

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function openNewPosition(
        address _mintTo,
        uint256 _slot,
        uint256 _value
    ) public onlySlotWithRiskParamsSet(_slot) nonReentrant {
        if (_value < i_minimumDepositAmount) {
            revert TreasuryBondToken__InvalidValue();
        }
        // 1. Calculate entry fees and net amount to invest
        (uint256 netAmount, uint256 feeCollected) = _calculateEntryFees(_value);
        // 2. TransferFrom caller di usdc _value to treasury contract
        i_treasury.depositUsdcFromOpenNewPosition(_value, msg.sender, _slot, feeCollected);
        // 3.  convert net amount from usdc to usd with std decimals (18)
        uint256 netAmountInUsd = _convertUsdcToUsd18(netAmount);

        // 4. call _mint to: checks ERC3643, checks RiskManager, checks ERc3525 accounting, 
        uint256 newTokenId = _mint(_mintTo, _slot, netAmountInUsd);
        
        // 5. emit event newPositionOpened
        emit PositionOpened(_mintTo, newTokenId, _slot, _value, netAmountInUsd, C.PAR);
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function closePosition(uint256 _tokenId) public nonReentrant onlyApprovedOrOwner(_tokenId) {
        address owner = ownerOf(_tokenId);
        uint256 slot = slotOf(_tokenId);
        uint256 tokenBalance = balanceOf(_tokenId);
        (uint256 usdcPayout, uint256 netYieldToClaimInUsdc, uint256 managmentFeeInUsdc , uint256 earlyRedeemFeeUsdc, uint256 currentNAV) = _closePositionValue(_tokenId, slot, tokenBalance);
        uint256 totalUsdcOutFromSlotLiquidity = usdcPayout + netYieldToClaimInUsdc + earlyRedeemFeeUsdc + managmentFeeInUsdc;
        _riskManagerBeforeTransferLiquidity(slot, totalUsdcOutFromSlotLiquidity);
        _burn(_tokenId);
        i_treasury.withdrawUsdcFromClosePosition(usdcPayout, owner, slot, netYieldToClaimInUsdc, earlyRedeemFeeUsdc, managmentFeeInUsdc);
        // emit event position closed
        emit PositionClosed(owner, _tokenId, slot, tokenBalance, usdcPayout, currentNAV);
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function closePartialPosition(
        uint256 _tokenId,
        uint256 _valueToBurn
    ) public nonReentrant onlyApprovedOrOwner(_tokenId) {
        address owner = ownerOf(_tokenId);
        uint256 slot = slotOf(_tokenId);
        (uint256 usdcPayout, uint256 netYieldToClaimInUsdc, uint256 managmentFeeInUsdc , uint256 earlyRedeemFeeUsdc, uint256 currentNAV) = _closePositionValue(_tokenId, slot, _valueToBurn);
        uint256 totalUsdcOutFromSlotLiquidity = usdcPayout + netYieldToClaimInUsdc + earlyRedeemFeeUsdc + managmentFeeInUsdc;
        _riskManagerBeforeTransferLiquidity(slot, totalUsdcOutFromSlotLiquidity);
        _burnValue(_tokenId, _valueToBurn);
        i_treasury.withdrawUsdcFromClosePosition(usdcPayout, owner, slot, netYieldToClaimInUsdc, earlyRedeemFeeUsdc, managmentFeeInUsdc);

        uint256 remainingBalance = balanceOf(_tokenId); // get remaining balance after burn
        //emit event position partially closed  
        emit PartialPositionClosed(owner, _tokenId, slot, _valueToBurn, remainingBalance, usdcPayout, currentNAV);
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function forceTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) public onlyRole(OWNER_ROLE) returns (bool) {
        if (ownerOf(_tokenId) != _from) revert TreasuryBondToken__InvalidTokenOwner();

        uint256 slot = slotOf(_tokenId);
        uint256 tokenValue = balanceOf(_tokenId);

        // 1. Settle all accrued yield to _from before the transfer.
        //    This mirrors the behaviour of _beforeTransfer for regular transfers.
        (uint256 netPayout, uint256 managementFee) = _claimYield(_tokenId, s_fromIdToPositionData[_tokenId]);
        if (netPayout + managementFee > 0) {
            _riskManagerBeforeTransferLiquidity(slot, netPayout + managementFee);
            i_treasury.transferUsdcFromYieldClaim(netPayout, _from, slot, managementFee);
        }

        // 2. Unfreeze any frozen value on the token so the ERC3525 transfer is not blocked.
        uint256 frozenVal = getFrozenValue(_tokenId);
        if (frozenVal > 0) _unfreezePartialToken(_tokenId, frozenVal);

        // 3. Execute the transfer bypassing compliance and freeze checks.
        //    s_forcedTransfer is set/reset around the external call so the flag is
        //    always cleared even if the inner call reverts.
        s_forcedTransfer = true;
        try this._executeForcedTransferExternal(_from, _to, _tokenId) {
            s_forcedTransfer = false;
        } catch {
            s_forcedTransfer = false;
            revert TreasuryBondToken__ForcedTransferFailed();
        }

        emit ForceTransfer(_from, _to, _tokenId, tokenValue);
        return true;
    }

    /**
     * @notice Public wrapper required for try/catch in forceTransfer.
     * @dev Solidity requires that calls in try/catch blocks are external. We use `this.` to make an
     *      external call to the contract itself. The onlyRole guard prevents arbitrary external calls.
     */
    function _executeForcedTransferExternal(
        address _from,
        address _to,
        uint256 _tokenId
    ) external onlyRole(OWNER_ROLE) {
        _transferTokenId(_from, _to, _tokenId);
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function transferFrom(
        uint256 _fromTokenId,
        address _to,
        uint256 _value
    ) public payable override etherNotAccepted  returns (uint256 newTokenId) {
        newTokenId = super.transferFrom(_fromTokenId, _to, _value);
        if(!_checkOnERC721Received(ownerOf(_fromTokenId), _to, newTokenId, "")){
            revert ERC3525__TransferToNonERC721ReceiverImplementer();
        }
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function transferFrom(uint256, uint256, uint256) public payable override {
        revert TreasuryBondToken__FunctionDisabled();
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted nonReentrant{
        super.transferFrom(_from, _to, _tokenId);
        if(!_checkOnERC721Received(_from, _to, _tokenId, "")){
            revert ERC3525__TransferToNonERC721ReceiverImplementer();
        }
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public payable override etherNotAccepted  {
        super.safeTransferFrom(_from, _to, _tokenId, _data);
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted  {
        super.safeTransferFrom(_from, _to, _tokenId, "");
    }

    /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function claimYield(uint256 _tokenId) public nonReentrant onlyApprovedOrOwner(_tokenId){
        // 1. get position data from tokenId
        PositionData memory posData = s_fromIdToPositionData[_tokenId];

        // 2. verify that the lock period for claiming yield has elapsed since the last claim or since minting if it's the first claim
        if(posData.lastClaimTimestamp + C.LOCK_PERIOD_CLAIM_YIELD > block.timestamp){
            revert TreasuryBondToken__LockPeriodNotElapsed();
        }

        // 3. get slot and balance from tokenId
        uint256 slot = _slotOf(_tokenId);

        // 4. get total yield to claim in usd with 18 decimals, this function also updates the lastClaimTimestamp to now
        (uint256 netPayout, uint256 managmentFee) = _claimYield(_tokenId, posData);

        // 5. ensure treasury has enough liquidity to pay yield
        _riskManagerBeforeTransferLiquidity(slot, netPayout + managmentFee);

        // 6. call treasury to transfer USDC to the user, this call will also update the treasury 
        //    accounting and emit the event usdcWithdrawnFromClaimYield 
        i_treasury.transferUsdcFromYieldClaim(netPayout , msg.sender, slot, managmentFee);

        // emit event yield claimed
        emit YieldClaimed(msg.sender, _tokenId, netPayout + managmentFee, managmentFee);
    }

////////////////////////////////////////////////////////////////////
//////////////////////// Internal functions //////////////////////// 
////////////////////////////////////////////////////////////////////  

    /**
     * @notice Internal function to calculate the current Net Asset Value (NAV) for a given position.
     * @dev Formula (yield rose):   NAV = PAR * (MAX_PERCENTAGE - D_mod * (currentYield - entryYield) / PERCENTAGE_PRECISION) / MAX_PERCENTAGE
     *      Formula (yield fell):   NAV = PAR * (MAX_PERCENTAGE + D_mod * (entryYield - currentYield) / PERCENTAGE_PRECISION) / MAX_PERCENTAGE
     *      Where D_mod is the duration modifier for the slot, acting as price sensitivity to yield changes.
     *      If the discount reaches or exceeds 100%, NAV is capped at 0.
     * @param _entryYield The yield at the time the position was opened.
     * @param _currentYield The current yield for the slot.
     * @param _slot The slot identifier for the position.
     * @return currentNAV The calculated current NAV for the position.
     */
    function _calculateCurrentNAV(uint256 _entryYield, uint256 _currentYield, uint256 _slot) internal pure returns (uint256 currentNAV) {
        uint256 D_mod = _getDmodForSlot(_slot);
        currentNAV = YieldsMath.calculateCurrentNAV(C.PAR, _entryYield, _currentYield, D_mod);
    }

    /**
     * @notice Internal function to close a position and calculate the payout values. 
     * @dev Manage both full and partial position closures by calculating the payout proportionally to the value being burned.
     * @param _tokenId The ID of the token representing the position.
     * @param _slot The slot identifier for the position.
     * @param _valueToBurn The value of the position to burn.
     * @return usdcPayout The USDC payout after fees.
     * @return netYieldToClaimInUsdc The net yield to claim in USDC.
     * @return managmentFeeInUsdc The management fee in USDC.
     * @return earlyRedeemFeeUsdc The early redeem fee in USDC.
     * @return currentNAV The current Net Asset Value (NAV) of the position.
     */
    function _closePositionValue(
        uint256 _tokenId,
        uint256 _slot,
        uint256 _valueToBurn
        ) internal returns (uint256 usdcPayout, uint256 netYieldToClaimInUsdc, uint256 managmentFeeInUsdc, uint256 earlyRedeemFeeUsdc, uint256 currentNAV){
        // 1. Get the current yield for the slot 
        (uint256 currentYield, , ) = _getMarketDataForSlot(_slot);

        // 2. get position data
        PositionData memory posData = s_fromIdToPositionData[_tokenId];

        // 3. accrue all pending interests until now (in USDC)
        (netYieldToClaimInUsdc, managmentFeeInUsdc) = _claimYield(_tokenId, posData);

        // 4. Calculate the current NAV based on the entry yield and current yield  
        currentNAV = _calculateCurrentNAV(posData.entryYield, currentYield, _slot);
        uint256 usdPayoutBeforeFees = (_valueToBurn * currentNAV) / C.PAR;

        // 5. Convert payout and fees from USD with 18 decimals to USDC with 6 decimals
        uint256 usdcPayoutBeforeFees = _convertUsd18ToUsdc(usdPayoutBeforeFees);

        // 6. Calculate early redeem fee if the position is closed before the penalty period for that slot
        earlyRedeemFeeUsdc = _calculateEarlyRedeemFee(posData.mintTimestamp, usdcPayoutBeforeFees, _slot);
        
        // 7. Returns parameter to call treasury withdraw function 
        usdcPayout = usdcPayoutBeforeFees - earlyRedeemFeeUsdc;
        return (usdcPayout, netYieldToClaimInUsdc, managmentFeeInUsdc , earlyRedeemFeeUsdc, currentNAV);
    }

    /**
     * @notice Internal function to calculate and transfer accrued yield to the user before any value change (transfer, burn).
     * @param _tokenId The ID of the token for which to claim yield.
     * @param positionData The position data associated with the token.
     * @return netPayoutUsdc The net payout in USDC after deducting management fees.
     * @return managmentFeeUsdc The management fee in USDC to send to the treasury.
     */
    function _claimYield(uint256 _tokenId, PositionData memory positionData) internal returns (uint256 netPayoutUsdc, uint256 managmentFeeUsdc) {
        // 1.  Get balance of token
        uint256 value = balanceOf(_tokenId);
        // questa funzione viene usata anche durante i transfer 
        uint256 principalUsd = YieldsMath.calculatePrincipalUsd(value , positionData.entryNAV, C.PAR);
        uint256 elapsedTime = block.timestamp - positionData.lastClaimTimestamp;
        uint256 grossAccrued = principalUsd * positionData.entryYield * elapsedTime / (365 days * C.PERCENTAGE_PRECISION);

        // retreive managment fee and net payout from gross accrued yield
        uint256 managmentFee = grossAccrued * C.PERCENTAGE_YIELD_FEE / C.MAX_PERCENTAGE;
        uint256 netPayout = grossAccrued - managmentFee;

        // 5. Convert payout and fees from USD with 18 decimals to USDC with 6 decimals
        netPayoutUsdc;
        managmentFeeUsdc;
        {
            uint256[] memory usdAmounts = new uint256[](2);
            usdAmounts[0] = netPayout;
            usdAmounts[1] = managmentFee;

            uint256[] memory usdcAmounts = _convertMultipleUsd18ToUsdcArray(usdAmounts);
            netPayoutUsdc = usdcAmounts[0];
            managmentFeeUsdc = usdcAmounts[1]; 
        }    

        // update last claim timestamp to now
        s_fromIdToPositionData[_tokenId].lastClaimTimestamp = block.timestamp;
        // chiamare trasury
        // emette l' evento di interesse maturato
    }

    /**
     * @notice Hook that is called before any transfer of value. This includes minting and burning.
     * @dev Inherit from both ERC3643 and ERC3525, so we need to override and call both parent implementations. 
     *      This function is used to implement the necessary checks and state updates before any value transfer occurs, including:
     *      - Compliance checks from ERC3643 (e.g. KYC/AML checks on _to address)
     *      - RiskManager checks (e.g. ensuring sufficient liquidity before allowing transfers that would reduce slot liquidity)
     *      - Yield claiming before transfers (to ensure users receive accrued yield up to the transfer moment)
     *      - PositionData initialization for new tokens in case of minting or partial transfers
     *      After ERC3643 logic has been splitted into _beforeMint, _beforeBurn and _beforeTransfer.
     * @param _from The address which previously owned the token (zero address if minting).
     * @param _to The address which will receive the token (zero address if burning).
     * @param _fromTokenId The token ID from which value is being transferred (zero if minting).
     * @param _toTokenId The token ID to which value is being transferred (zero if burning).
     * @param _slot The slot of the token being transferred.
     * @param _value The amount of value being transferred.
     */
    function _beforeValueTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    ) internal override(ERC3643, ERC3525) {
        // 1. ERC3643 checks
        super._beforeValueTransfer(_from, _to, _fromTokenId, _toTokenId, _slot, _value);

        // 2. Conditional logic based on whether it's a mint, burn, or transfer 
        if (_from == address(0)) {
            _beforeMint(_to, _fromTokenId,_toTokenId, _slot, _value);
        } else if (_to == address(0)) {
            _beforeBurn(_from, _fromTokenId, _slot, _value);
        } else {
            _beforeTransfer(_from, _to, _fromTokenId, _toTokenId, _slot, _value);
        }
    }

    /**
     * @notice Hook that is called before minting new tokens.
     * @dev This function is called when mint or transferFrom new tokens (partial transfer). 
     * @dev Used on _beforeValueTransfer to implement the logic that needs to run before minting new tokens
     * @param _to The address which will receive the newly minted tokens.
     * @param _fromTokenId The token ID from which value is being transferred (zero if minting).
     * @param _toTokenId The token ID to which value is being transferred (zero if burning).
     * @param _slot The slot of the token being minted.
     * @param _value The amount of value being minted.
     */
    function _beforeMint(
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {
        // 1. Checks on RiskManager abd update riskManagerStorage if necessary
        _riskManagerBeforeMint(_slot, _value);

        // 2. Initialize PositionData for the new token with current slot yield and PAR NAV.
        //    For partial transfers, PositionData will be overwritten in _beforeTransfer with
        //    the inherited values from the source token (entryYield, entryNAV, mintTimestamp).
        (uint256 currentYield, , ) = _getMarketDataForSlot(_slot);
        s_fromIdToPositionData[_toTokenId] = PositionData({
            entryYield: currentYield,
            entryNAV: C.PAR,
            mintTimestamp: block.timestamp,
            lastClaimTimestamp: block.timestamp
        });

    }

    /**
     * @notice Hook that is called before burning tokens.
     * @dev This function is called on _beforeValueTransfer when burning tokens or partial burning.
     * @param _from The address which previously owned the tokens.
     * @param _fromTokenId The token ID from which value is being burned.
     * @param _slot The slot of the token being burned.
     * @param _value The amount of value being burned.
     */
    function _beforeBurn(
        address _from,
        uint256 _fromTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {
        // 1. Checks on RiskManager abd update riskManagerStorage if necessary
        _riskManagerBeforeBurn(_slot, _value);

        // 2. Update or delete PositionData struct for the tokenId being burned
        // if the entire balance of the tokenId is being burned, delete the PositionData struct
        if(balanceOf(_fromTokenId) == _value){
            delete s_fromIdToPositionData[_fromTokenId];
        }
    }

    /**
     * @notice Hook that is called before transferring tokens.
     * @dev This function is called on _beforeValueTransfer when transferring tokens or partial transfers.
     * @dev Used to claiming yield for the source token before the transfer and to initialize PositionData for the destination token in case of partial transfer.
     * @param _from The address which previously owned the tokens.
     * @param _to The address which will receive the tokens.
     * @param _fromTokenId The token ID from which value is being transferred.
     * @param _toTokenId The token ID to which value is being transferred.
     * @param _slot The slot of the token being transferred.
     * @param _value The amount of value being transferred.
     */
    function _beforeTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {
        // Claim yield accrued on the source token before the transfer
        (uint256 netPayout, uint256 managementFee) = _claimYield(_fromTokenId, s_fromIdToPositionData[_fromTokenId]);
        _riskManagerBeforeTransferLiquidity(_slot, netPayout + managementFee);
        i_treasury.transferUsdcFromYieldClaim(netPayout, _from, _slot, managementFee);

        // Partial transfer (value-split): _beforeMint already wrote a default PositionData on _toTokenId.
        // Overwrite it here with the source token's entryYield, entryNAV and mintTimestamp so the lock
        // period is inherited and the yield rate is preserved. lastClaimTimestamp stays block.timestamp
        // (set by _beforeMint) so the new token accrues yield only from the transfer moment forward.
        if (_fromTokenId != _toTokenId) {
            PositionData memory fromPosData = s_fromIdToPositionData[_fromTokenId];
            s_fromIdToPositionData[_toTokenId] = PositionData({
                entryYield:          fromPosData.entryYield,
                entryNAV:            fromPosData.entryNAV,
                mintTimestamp:       fromPosData.mintTimestamp,
                lastClaimTimestamp:  block.timestamp
            });
        }
    }


    /**
     * @notice Hook that is called after any transfer of value. This includes minting and burning.
     * @dev This function can be used to implement custom logic that needs to run after value transfers.
     * @param _from The address which previously owned the token (zero address if minting).
     * @param _to The address which will receive the token (zero address if burning).
     * @param _fromTokenId The token ID from which value is being transferred (zero if minting).
     * @param _toTokenId The token ID to which value is being transferred (zero if burning).
     * @param _slot The slot of the token being transferred.
     * @param _value The amount of value being transferred.
     */
    function _afterValueTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    ) internal override {}


    /**
     * @notice Calculates the entry fee for a given deposit amount based on a predefined percentage on deposit.
     * @param _amount The amount of USDC being deposited to open a new position.
     * @return netAmount The amount that will be actually invested after deducting the entry fee.
     * @return feeCollected The amount of USDC collected as entry fee.
     */
    function _calculateEntryFees(
        uint256 _amount
    ) internal pure returns (uint256 netAmount, uint256 feeCollected) {
        feeCollected = (_amount * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
        netAmount = _amount - feeCollected;
    }

    /**
    * @notice Calculates the early redemption fee for a token.
    * @dev The fee decreases linearly over time until it reaches zero
    *      at the end of the penalty period.
    * @param _mintTimestamp The timestamp when the token was minted
    * @param _usdValue The amount of usd being redeemed 
    * @param _slot The slot associated with the token
    *
    * @return feeAmount The fee amount to pay
    */
    function _calculateEarlyRedeemFee(
        uint256 _mintTimestamp,
        uint256 _usdValue,
        uint256 _slot
    ) internal view returns (uint256 feeAmount) {
        uint256 penaltyPeriod = _getPenaltyPeriod(_slot); 
        uint256 elapsedTime = block.timestamp - _mintTimestamp;

        // No fee after penalty period expires
        if (elapsedTime >= penaltyPeriod) {
            return 0;
        }

        uint256 remainingTime = penaltyPeriod - elapsedTime;
        uint256 currentFeePercentage = (C.PERCENTAGE_EXIT_FEE_MAX * remainingTime) / penaltyPeriod;

        feeAmount =(_usdValue * currentFeePercentage) / C.MAX_PERCENTAGE;
    }

    /**
     * @notice Returns the penalty period associated with a slot
     * @dev Each slot has a predefined penalty period constant. 
     *      This function maps the slot ID to its corresponding penalty period.
     * @param _slot The slot ID for which to get the penalty period
     * @return The penalty period in seconds for the given slot
     */
    function _getPenaltyPeriod(uint256 _slot) internal pure returns (uint256) {
        if (_slot == C.SLOT_2Y) {
            return C.PENALTY_PERIOD_2Y;
        }

        if (_slot == C.SLOT_5Y) {
            return C.PENALTY_PERIOD_5Y;
        }

        if (_slot == C.SLOT_10Y) {
            return C.PENALTY_PERIOD_10Y;
        }

        if (_slot == C.SLOT_30Y) {
            return C.PENALTY_PERIOD_30Y;
        }

        revert TreasuryBondToken__InvalidSlot();
    }
    
    /**
     * @notice Internal function to validate that a slot is one of the predefined constants.
     * @dev Ensures that the provided slot is valid.
     * @param _slot The slot to validate.
     * Reverts if the slot is not one of the predefined constants (2Y, 5Y, 10Y, 30Y).
     */
    function _onlyValidSlot(uint256 _slot) internal pure {
        if (
            _slot != C.SLOT_2Y &&
            _slot != C.SLOT_5Y &&
            _slot != C.SLOT_10Y &&
            _slot != C.SLOT_30Y
        ) {
            revert TreasuryBondToken__InvalidSlot();
        }
    }

    /**
     * @notice Internal function to prevent acceptance of Ether.
     * @dev Reverts if any Ether is sent to the contract. This is important to prevent accidental 
     *      loss of funds, as the contract is designed to work with USDC and not Ether.
     * @dev This function is used as a modifier on functions that should not accept Ether, 
     *      ensuring that any attempt to send Ether will be rejected with a clear error message.
     */
    function _notAcceptEther() internal view {
        if (msg.value > 0) {
            revert TreasuryBondToken__EtherNotAccepted();
        }
    }


////////////////////////////////////////////////////////////////////
///////////////////////// public getters /////////////////////////// 
////////////////////////////////////////////////////////////////////  

    function ownerOf(uint256 tokenId) public view override returns (address) {
        return super.ownerOf(tokenId);
    }

    function balanceOf(uint256 tokenId) public view override(ERC3643, ERC3525) returns (uint256) {
        return super.balanceOf(tokenId);
    }
    function balanceOf(address owner) public view override(ERC3643, ERC3525) returns (uint256) {
        return super.balanceOf(owner);
    }

    /**
     * @notice Returns the total liabilities for a specific bond slot (maturity).
     * @dev Each slot represents a different bond maturity (2Y, 5Y, 10Y, 30Y).
     * @param _slot The slot ID representing the bond maturity.
     * @return The total liabilities (in USDC) for the specified slot.
     */
    function getTotalLiabilitiesPerSlot(
        uint256 _slot
    ) external view onlyValidSlot(_slot) returns (uint256) {
        return _getTotalLiabilitiesForSlot(_slot);
    }

    /**
     * @notice Asserts the solvency of the protocol.
     * @dev public wrapper for the internal _assertSolvency function in Riskmanager.
     */
    function assertSolvency() external view {
        _assertSolvency();
    }

    function getNextRedemptionWindow(uint256 _slot) external view returns (uint256 nextWindowOpen, uint256 windowDuration) {
        (nextWindowOpen, windowDuration) = _getNextRedemptionWindow(_slot);
    }

    /**
     * @notice Returns the position data for a given tokenId.
     * @dev Includes interest rate, mint timestamp, and maturity timestamp for the position.
     * @param _tokenId The ERC-3525 token ID representing the position.
     * @return The PositionData struct containing details about the position.
     */
    function getPositionData(
        uint256 _tokenId
    ) external view returns (PositionData memory) {
        _requireMinted(_tokenId);
        return s_fromIdToPositionData[_tokenId];
    }

    /**
     * @notice Internal function to get the D-modifier for a specific bond slot.
     * @dev This function replaces the need for a mapping or switch statement by directly returning 
     *      the constant D-modifier based on the slot ID. This choice was made for gas optimization, 
     *      as it avoids storage reads and allows the compiler to optimize the code more effectively.
     * @param _slot The slot ID representing the bond maturity.
     * @return The D-modifier for the specified slot.
     */
    function _getDmodForSlot(uint256 _slot) internal pure returns (uint256) {
        if (_slot == C.SLOT_2Y)  return C.D_MOD_2Y;
        if (_slot == C.SLOT_5Y)  return C.D_MOD_5Y;
        if (_slot == C.SLOT_10Y) return C.D_MOD_10Y;
        if (_slot == C.SLOT_30Y) return C.D_MOD_30Y;
    }

    // /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function name() public view override(ERC3643, ERC3525) returns (string memory) {
        return super.name();
    }

    // /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function symbol() public view override(ERC3643, ERC3525) returns (string memory) {
        return super.symbol();
    }

    // /// @dev Inherit from ITreasuryBondToken. See interface for details.
    function valueDecimals() public view override(ERC3643, ERC3525) returns (uint8) {
        return super.valueDecimals();
    }

////////////////////////////////////////////////////////////////////
/////////////////////// ERC3643 inheritance //////////////////////// 
////////////////////////////////////////////////////////////////////  

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function setNameAndSymbol(string calldata _name, string calldata _symbol) external override onlyRole(OWNER_ROLE) {
        (string memory name_, string memory symbol_) = _setNameAndSymbol(_name, _symbol);
        s_name = name_;
        s_symbol = symbol_;
    }
     
    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function setIdentityRegistry(address _identityRegistry) public override onlyRole(OWNER_ROLE) {
        _setIdentityRegistry(_identityRegistry);
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function setOnchainID(address _onchainID) public override onlyRole(OWNER_ROLE) {
        _setOnchainID(_onchainID);
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function setCompliance(address _compliance) public override onlyRole(OWNER_ROLE) {
        _setCompliance(_compliance);
    }

    /**
     * @notice Public wrapper necessary for try/catch functionality.
     * @dev Solidity requires that calls in try/catch blocks are external. We use `this.` to make an external call to the contract itself.
     * The function is marked `onlyRole` to prevent arbitrary calls from outside.
     */
    function _executeRecoveryTransferExternal(address lostWallet, address newWallet) external override onlyRole(RECOVERY_ROLE) {
        _executeRecoveryTransfer(lostWallet, newWallet);
    }

    function _executeRecoveryTransfer(
        address lostWallet,
        address newWallet
    ) internal override {
        // balanceOf(address) returns the number of ERC721 tokens owned by the address, so if it's 0 it means there are no tokens to recover
        uint256 tokenCount = balanceOf(lostWallet);

        // id snaphot BEFORE transfer to avoid issues with token enumeration after transfer
        uint256[] memory tokenIds = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(lostWallet, i);
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Frozen values are mapped by tokenId, they follow the token automatically,
            // no need to migrate them (the mapping s_frozenValues[tokenId] remains unchanged).

            // _transferTokenId is internal in ERC3525 and bypasses the onlyApprovedOrOwner check
            _transferTokenId(lostWallet, newWallet, tokenId);
        }
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function recoveryAddress( address _lostWallet, address _newWallet, address _investorOnchainID) 
    public override onlyRole(RECOVERY_ROLE) returns (bool) {
        return _recoveryAddress(_lostWallet, _newWallet, _investorOnchainID);
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function pause () public override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function unpause () public override onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function setAddressFrozen(address _userAddress, bool _freeze) external override onlyRole(FREEZER_ROLE) {
        _setAddressFrozen(_userAddress, _freeze);
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function freezePartialTokens(uint256 _tokenId, uint256 _amount) external override onlyRole(FREEZER_ROLE) {
        _freezePartialToken(_tokenId, _amount);
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function unfreezePartialTokens(uint256 _tokenId, uint256 _amount) external override onlyRole(FREEZER_ROLE) {
        _unfreezePartialToken(_tokenId, _amount);
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external override onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _setAddressFrozen(_userAddresses[i], _freeze[i]);
        }
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function batchFreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external override onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < _tokenId.length; i++) {
            _freezePartialToken(_tokenId[i], _amounts[i]);
        }
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function batchUnfreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external override onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < _tokenId.length; i++) {
            _unfreezePartialToken(_tokenId[i], _amounts[i]);
        }
    }

////////////////////////////////////////////////////////////////////
/////////////////// ERC3643 Getters inheritance //////////////////// 
////////////////////////////////////////////////////////////////////  
    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function compliance() external view  returns (IModularCompliance) {
        return s_tokenCompliance;
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function paused() external view returns (bool) {
        return s_tokenPaused;
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function onchainID() public view returns (address) {
        return s_tokenOnchainID;
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function version() public pure returns (string memory) {
        return TOKEN_VERSION;
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function getWalletFrozenStatus(address _wallet) public view returns (bool) {
        return s_frozenWallets[_wallet];
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function getFrozenValue(uint256 _tokenId) public view returns (uint256) {
        return s_frozenValues[_tokenId];
    }

    /// @dev Inherit from IERC3643 on ITreasuryBondToken. See interface for details.
    function getAvailableValue(uint256 _tokenId) public view returns (uint256) {
        return balanceOf(_tokenId) - s_frozenValues[_tokenId];
    }

}
