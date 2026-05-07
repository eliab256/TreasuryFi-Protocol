//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC3525} from "./ERC3525.sol";
import {ERC3643} from "./ERC3643.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {YieldsMath} from "../library/YieldsMath.sol";
import {RiskManager} from "./RiskManager.sol";
import {UsdcUsdConverter} from "./UsdcUsdConverter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {
    IIdentityRegistry
} from "@t-rex/registry/interface/IIdentityRegistry.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PositionData, TreasuryBondTokenConstructorParams} from "../types.sol";
import {TokenConstants as C} from "./TokenConstants.sol";
import {IBondAutomation} from "../interfaces/IBondAutomation.sol";
import {IReservesAutomation} from "../interfaces/IReservesAutomation.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";



/**
 * @title TreasuryBondToken
 * @notice ERC-3525 token representing fractionalized positions in US Treasury bonds.
 * Each slot corresponds to a different bond maturity (2Y, 5Y, 10Y, 30Y).
 * Users can open new positions by depositing USDC and minting tokens, or close positions by burning tokens and withdrawing USDC.
 * The contract includes role-based access control for fee management and administrative functions.
 */
contract TreasuryBondToken is ERC3643, ERC3525, RiskManager, UsdcUsdConverter, ReentrancyGuard{

    // Nuovi eventi
    event PositionOpened(address indexed user, uint256 indexed tokenId, uint256 slot, uint256 value, uint256 feeCollected);
    event PositionClosed(address indexed user, uint256 indexed tokenId, uint256 slot, uint256 value, uint256 feeCollected);
    event PartialPositionClosed(address indexed user, uint256 indexed tokenId, uint256 slot, uint256 valueBurned, uint256 feeCollected);
    event YieldClaimed(address indexed user, uint256 indexed tokenId, uint256 yieldAmount, uint256 feeCollected);
    event ForceTransfer(address indexed from, address indexed to, uint256 indexed tokenId, uint256 value);
    event EntryFeeCollected(address indexed user, uint256 amount);
    event ExitFeeCollected(address indexed user, uint256 amount);
    event YieldFeeCollected(address indexed user, uint256 amount);
    event IdentityRegistrySet(address indexed identityRegistry);
    

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

    /// @dev constant unit value to calculate NAV.
    uint256 internal constant PAR = 1e18; 
    uint256 internal constant PERCENTAGE_YIELD_FEE = 20 * C.PERCENTAGE_PRECISION; // 20% fee on yield
    uint256 internal constant PERCENTAGE_ENTRY_FEE = 2 * C.PERCENTAGE_PRECISION / 10; // 0,2% fee on entry
    uint256 internal constant PERCENTAGE_EXIT_FEE_MAX = 5 * C.PERCENTAGE_PRECISION ; // 5% fee on exit

    
    uint256 private immutable i_minimumDepositAmount; // 10 USDC
    ITreasury private immutable i_treasury;

    mapping(uint256 => PositionData) private s_fromIdToPositionData;



    bytes32 public constant FEES_MANAGER_ROLE = keccak256("FEES_MANAGER_ROLE");
    bytes32 public constant AUTOMATION_TRIGGERER_ROLE = keccak256("AUTOMATION_TRIGGERER_ROLE");
    bytes32 public constant UPDATE_RISK_MANAGER_VALUES_ROLE = keccak256("UPDATE_RISK_MANAGER_VALUES_ROLE");

    modifier onlyValidSlot(uint256 slot) {
        _onlyValidSlot(slot);
        _;
    }

    modifier etherNotAccepted() {
        _notAcceptEther();
        _;
    }

    constructor(
        TreasuryBondTokenConstructorParams memory _params
    ) ERC3643(_params.name, _params.symbol, _params.decimalsStandard, address(this), _params.identityRegistry, address(0)) 
    ERC3525(_params.decimalsStandard) 
    RiskManager(_params.bondAutomation, _params.reservesAutomation, _params.reservesOracle, _params.bondOracle)
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
            _params.updateRiskManagerAutomation == address(0) ||
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
        _grantRole(FEES_MANAGER_ROLE, _params.feesCollector);
        _grantRole(AUTOMATION_TRIGGERER_ROLE, msg.sender);
        _grantRole(UPDATE_RISK_MANAGER_VALUES_ROLE, _params.updateRiskManagerAutomation);
        _grantRole(UPDATE_RISK_MANAGER_VALUES_ROLE, msg.sender);
        i_treasury = ITreasury(_params.treasury);
        i_minimumDepositAmount = 10 * (10 ** i_usdcDecimals); // 10 USDC with decimals

    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC3525, AccessControl) returns (bool) {
         return ERC3525.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }


////////////////////////////////////////////////////////////////////
///////////////////// RiskManager inheritance ////////////////////// 
////////////////////////////////////////////////////////////////////  

    /**
     * @notice Function to manually trigger the reserves upkeep.
     * @dev Can only be called by an account with the AUTOMATION_TRIGGERER_ROLE.
     * @dev Internal function inherited from RiskManager.
     */
    function triggerReservesUpkeep() public onlyRole(AUTOMATION_TRIGGERER_ROLE) {
        _triggerReservesUpkeep();
    }

    /**
     * @notice Function to manually trigger the bond yields upkeep.
     * @dev Can only be called by an account with the AUTOMATION_TRIGGERER_ROLE.
     * @dev Internal function inherited from RiskManager.
     */
    function triggerYieldsUpkeep() public onlyRole(AUTOMATION_TRIGGERER_ROLE) {
        _triggerYieldsUpkeep();
    }

    /**
    * @notice Updates the risk manager yields values from the oracle.
    * @dev Normally called by UpdateRiskManagerAutomation via UPDATE_RISK_MANAGER_VALUES_ROLE.
    * The deployer retains this role as emergency fallback in case Chainlink Automation
    * stops functioning, allowing manual intervention without governance delay.
    */
    function updateYieldsValues() public onlyRole(UPDATE_RISK_MANAGER_VALUES_ROLE) {
        _updateYieldsValues();
    }

    function updateReserveValues() public onlyRole(UPDATE_RISK_MANAGER_VALUES_ROLE) {
        _updateReservesValues();
    }

////////////////////////////////////////////////////////////////////
/////////////////// Positions related functions //////////////////// 
////////////////////////////////////////////////////////////////////  
    function openNewPosition(
        address _mintTo,
        uint256 _slot,
        uint256 _value
    ) public onlyValidSlot(_slot) nonReentrant {
        if (_value < i_minimumDepositAmount) {
            revert TreasuryBondToken__InvalidValue();
        }
        // 1. Calculate entry fees and net amount to invest
        (uint256 netAmount, uint256 feeCollected) = _calculateEntryFees(_value);
        // 2. TransferFrom caller di usdc _value to treasury contract
        i_treasury.depositUsdcFromOpenNewPosition(_value, msg.sender, _slot, feeCollected);
        // 3.  convert net amount from usdc to usd with std decimals (18)
        uint256 netAmountInUsd = _convertUsdcToUsd18(netAmount);

        // 4. get current yield from slot
        uint256 currentYield = s_lastValidYieldPerSlot[_slot];

        // 5. call _mint to: checks ERC3643, checks RiskManager, checks ERc3525 accounting, 
        //    update storage and mint the token to the user
        // @audit-issue assicurarsi che i check siano effettivi dentro _beforeTransfer
        uint256 newTokenId = _mint(_mintTo, _slot, netAmountInUsd);
        
        // 6. Update positionData struct
        s_fromIdToPositionData[newTokenId] = PositionData({
            entryYield: currentYield, 
            entryNAV: PAR,
            mintTimestamp: block.timestamp,
            lastClaimTimestamp: block.timestamp
        });
        // 7. emit event newPositionOpened
        emit PositionOpened(_mintTo, newTokenId, _slot, netAmountInUsd, feeCollected);
    }

    function closePosition(uint256 _tokenId) public nonReentrant{
        _closePositionValue(_tokenId, balanceOf(_tokenId));
    }

    function closePartialPosition(
        uint256 _tokenId,
        uint256 _valueToBurn
    ) public nonReentrant {
        _closePositionValue(_tokenId, _valueToBurn);

    }

    function _calculateCurrentNAV(uint256 _tokenId, uint256 _entryYield) internal view returns (uint256 currentNAV) {
        uint256 slot = slotOf(_tokenId);
        uint256 currentYield = s_lastValidYieldPerSlot[slot];
        uint256 D_mod = _getModifiedDurationForSlot(slot);
        currentNAV = YieldsMath.calculateCurrentNAV(PAR, _entryYield, currentYield, D_mod);
    }

    function _closePositionValue(
        uint256 _tokenId,
        uint256 _valueToBurn
    ) internal {
        // 1. Get the slot of the tokenId
        //uint256 slot = slotOf(_tokenId);

        // get position data
        PositionData memory positionData = s_fromIdToPositionData[_tokenId];

        // 2. Get current yield for the slot
        //uint256 currentYield = s_lastValidYieldPerSlot[slot];

        // 3. Calculate the current NAV based on the entry yield and current yield
        uint256 currentNAV = _calculateCurrentNAV(_tokenId, positionData.entryYield);
        uint256 usdPayoutBeforeFees = (_valueToBurn * currentNAV) / PAR;
        // 1. Burn the specified value from the ERC-3525 token
        // 2. Send USDC amount to the user 
        //_calculateEarlyRedeemFee(_mintTimestamp, _valueToBurn, _slot);
        // 3. Update storage

    }

    function forceTransfer() onlyRole(OWNER_ROLE) public {
        // @audit-issue implement forceTransfer function
        // questa funzione permette al protocol owner di forzare il trasferimento di un token da un wallet all' altro in caso di furto o smarrimento
        // implementare checks per evitare abusi (es. solo wallet frozen, solo una volta ogni tot tempo, etc.)
    }

    /**
     * @notice Disabled function to prevent transfers between tokens.
     * @dev This function is intentionally disabled to enforce the non-transferable nature of the tokens.
     */
    function transferFrom(uint256, uint256, uint256) public payable override {
        revert TreasuryBondToken__FunctionDisabled();
    }

    function transferFrom(
        uint256 _fromTokenId,
        address _to,
        uint256 _value
    ) public payable override etherNotAccepted  returns (uint256 newTokenId) {
        // @audit-issue implement T-REX checks
       // newTokenId = super.transferFrom(_fromTokenId, _to, _value);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted {
        // @audit-issue implement checks
        // T-rex checks
        //super.transferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public payable override etherNotAccepted  {
        // @audit-issue implement checks
        // T-rex checks
        //super.safeTransferFrom(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted  {
        // @audit-issue implement checks
        // T-rex checks
        //super.safeTransferFrom(_from, _to, _tokenId, "");
    }

    function claimYield(uint256 _tokenId) public nonReentrant {
        // @audit-issue implement claimYield function
        // verifica che msg.sender sia owner o approved del token
        // verifica che sia passato abbastanza tempo dall'ultimo claim (es. 30 gg)
        // chiama la funzione interna per calcolare e trasferire gli interessi maturati
        // sottrarre la percentuale di yield trattenuta dal protocollo come fee
        // update total fees collected
        // aggiornare total value per slot
        _claimYield(_tokenId);
    }

////////////////////////////////////////////////////////////////////
/////////////////// Internal functions //////////////////// 
////////////////////////////////////////////////////////////////////  

    function _claimYield(uint256 _tokenId) internal {
        // 1. Recupera lo slot, il valore del token e calcola gli interessi maturati in base al tempo trascorso
        // 2. Trasferisci gli interessi maturati in USDC al possessore del token
        // si può usare la func public che avrà un intervallo di tempo minimo tra due claim per evitare abusi
        // questa funzione viene usata anche durante i transfer
        // emette l' evento di interesse maturato
    }

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
            _beforeMint(_to, _toTokenId, _slot, _value);
        } else if (_to == address(0)) {
            _beforeBurn(_from, _fromTokenId, _slot, _value);
        } else {
            _beforeTransfer(_from, _to, _fromTokenId, _toTokenId, _slot, _value);
        }
    }

    function _beforeMint(
        address _to,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {
        // 1. Checks on RiskManager abd update riskManagerStorage if necessary
        _riskManagerBeforeMint(_slot, _value);

        // 2. @audit-issue aggiornare lo storage di treaduryBondToken prima di mintare

    }

    function _beforeBurn(
        address _from,
        uint256 _fromTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {
        // 1. Checks on RiskManager abd update riskManagerStorage if necessary
        _riskManagerBeforeBurn(_slot, _value);
        // 2. @audit-issue aggiornare lo storage di treaduryBondToken prima di burnare
    }

    function _beforeTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {

        // se si vuole implementare la funzione di transfer forzato dal protocol owner, è necessario aggiornare l' accounting del tot value per slot anche durante i transfer
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


    function _calculateEntryFees(
        uint256 _amount
    ) internal returns (uint256 netAmount, uint256 feeCollected) {
        feeCollected = (_amount * PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
        netAmount = _amount - feeCollected;
    }

    /**
    * @notice Calculates the early redemption fee for a token.
    * @dev The fee decreases linearly over time until it reaches zero
    *      at the end of the penalty period.
    * @param _mintTimestamp The timestamp when the token was minted
    * @param _value The amount being redeemed
    * @param _slot The slot associated with the token
    *
    * @return feeAmount The fee amount to pay
    */
    function _calculateEarlyRedeemFee(
        uint256 _mintTimestamp,
        uint256 _value,
        uint256 _slot
    ) internal view returns (uint256 feeAmount) {
        uint256 penaltyPeriod = _getPenaltyPeriod(_slot); 
        uint256 elapsedTime = block.timestamp - _mintTimestamp;

        // No fee after penalty period expires
        if (elapsedTime >= penaltyPeriod) {
            return 0;
        }

        uint256 remainingTime = penaltyPeriod - elapsedTime;

        // Linear fee decay
        uint256 currentFeePercentage =
            (PERCENTAGE_EXIT_FEE_MAX * remainingTime) / penaltyPeriod;

        feeAmount =
            (_value * currentFeePercentage) /
            C.MAX_PERCENTAGE;

        return feeAmount;
    }

    /**
    * @notice Returns the penalty period associated with a slot
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
     * @dev Reverts if any Ether is sent to the contract. This is important to prevent accidental loss of funds, as the contract is designed to work with USDC and not Ether.
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

    function _getDmodForSlot(uint256 _slot) internal pure returns (uint256) {
    if (_slot == C.SLOT_2Y)  return C.D_MOD_2Y;
    if (_slot == C.SLOT_5Y)  return C.D_MOD_5Y;
    if (_slot == C.SLOT_10Y) return C.D_MOD_10Y;
    if (_slot == C.SLOT_30Y) return C.D_MOD_30Y;
}

    function name() public view override returns (string memory) {
        return super.name();
    }

    function symbol() public view override returns (string memory) {
        return super.symbol();
    }

    function valueDecimals() public view override(ERC3643, ERC3525) returns (uint8) {
        return super.valueDecimals();
    }

////////////////////////////////////////////////////////////////////
/////////////////////// ERC3643 inheritance //////////////////////// 
////////////////////////////////////////////////////////////////////  
     
    function setIdentityRegistry(address _identityRegistry) public onlyRole(OWNER_ROLE) {
        _setIdentityRegistry(_identityRegistry);
    }

    function setOnchainID(address _onchainID) public onlyRole(OWNER_ROLE) {
        _setOnchainID(_onchainID);
    }

    function setCompliance(address _compliance) public onlyRole(OWNER_ROLE) {
        _setCompliance(_compliance);
    }

    /**
     * @notice Public wrapper necessary for try/catch functionality.
     * @dev Solidity requires that calls in try/catch blocks are external. We use `this.` to make an external call to the contract itself.
     * The function is marked `onlyRole` to prevent arbitrary calls from outside.
     */
    function _executeRecoveryTransferExternal(address lostWallet, address newWallet) external override onlyRole(OWNER_ROLE) {
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

    function pause () public onlyRole(OWNER_ROLE) {
        _pause();
    }

    function unpause () public onlyRole(OWNER_ROLE) {
        _unpause();
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

    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _setAddressFrozen(_userAddresses[i], _freeze[i]);
        }
    }


    function batchFreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < _tokenId.length; i++) {
            _freezePartialToken(_tokenId[i], _amounts[i]);
        }
    }


    function batchUnfreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < _tokenId.length; i++) {
            _unfreezePartialToken(_tokenId[i], _amounts[i]);
        }
    }



}
