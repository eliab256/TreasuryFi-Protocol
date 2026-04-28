//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC3525} from "./ERC3525.sol";
import {ERC3643} from "./ERC3643.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IIdentityRegistry
} from "@t-rex/registry/interface/IIdentityRegistry.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PositionData} from "../types.sol";
import {TokenConstants as C} from "./TokenConstants.sol";

/**
 * @title TreasuryBondToken
 * @notice ERC-3525 token representing fractionalized positions in US Treasury bonds.
 * Each slot corresponds to a different bond maturity (2Y, 5Y, 10Y, 30Y).
 * Users can open new positions by depositing USDC and minting tokens, or close positions by burning tokens and withdrawing USDC.
 * The contract includes role-based access control for fee management and administrative functions.
 */
contract TreasuryBondToken is ERC3643, ERC3525 {

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
    error TreasuryBondToken__SenderNotVerified();
    error TreasuryBondToken__ReceiverNotVerified();
    error TreasuryBondToken__WalletAlreadyFrozen();
    error TreasuryBondToken__WalletNotFrozen();
    error TreasuryBondToken__AmountExceedsAvailableBalance();
    error TreasuryBondToken__AmountShouldBeLessOrEqualToFrozen();

    
    uint256 internal constant MAX_PERCENTAGE = 100 * C.PERCENTAGE_PRECISION; // 100% in percentage precision
    uint256 internal constant PERCENTAGE_YIELD_FEE = 10 * C.PERCENTAGE_PRECISION; // 10% fee on yield
    uint256 internal constant PERCENTAGE_ENTRY_FEE = 1 * C.PERCENTAGE_PRECISION; // 1% fee on entry

    IERC20 private immutable i_usdc;
    AggregatorV3Interface private immutable i_usdcPriceFeed;
    uint8 private immutable i_usdcDecimals; // 6 for usdc
    uint8 private immutable i_usdcPriceFeedDecimals; // 8 for chainlink price feed
    uint256 private immutable i_minimumDepositAmount; // 10 USDC

    IReservesOracle private immutable i_reservesOracle;
    IBondOracle private immutable i_bondOracle;

    /// @dev liabilities for each slot, updated on mint, burn and yield claim
    mapping(uint256 => uint256) private s_totalValuePerSlot;

    mapping(uint256 => PositionData) private s_fromIdToPositionData;
    uint256 private s_totalFeesCollected;

    bytes32 public constant FEES_MANAGER_ROLE = keccak256("FEES_MANAGER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    modifier onlyValidSlot(uint256 slot) {
        _onlyValidSlot(slot);
        _;
    }

    modifier etherNotAccepted() {
        _notAcceptEther();
        _;
    }

    modifier whenNotPaused() {
        super._whenNotPaused();
        _;
    }

    modifier whenPaused(){
        super._whenPaused();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _usdcAddress,
        address _usdcPriceFeedAddress,
        address _identityRegistry,
        address _reservesOracle,
        address _bondOracle,
        address _feesCollector
    ) ERC3643(_name, _symbol, _decimals, address(this), _identityRegistry, address(0)) ERC3525(_name, _symbol, _decimals)  {
        // Checks
        if (
            _usdcAddress == address(0) ||
            _usdcPriceFeedAddress == address(0) ||
            _feesCollector == address(0)
        ) revert TreasuryBondToken__ZeroAddress();

        // ERC165 interface checks
        bytes4 bondOracleInterfaceId = type(IBondOracle).interfaceId;
        if (!IERC165(_bondOracle).supportsInterface(bondOracleInterfaceId)) {
            revert TreasuryBondToken__InvalidOracle(
                _bondOracle,
                bondOracleInterfaceId
            );
        }
        bytes4 reservesOracleInterfaceId = type(IReservesOracle).interfaceId;
        if (
            !IERC165(_reservesOracle).supportsInterface(
                reservesOracleInterfaceId
            )
        ) {
            revert TreasuryBondToken__InvalidOracle(
                _reservesOracle,
                reservesOracleInterfaceId
            );
        }

        _grantRole(FEES_MANAGER_ROLE, _feesCollector);
        i_usdc = IERC20(_usdcAddress);
        i_usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeedAddress);
        i_usdcDecimals = IERC20Metadata(_usdcAddress).decimals();
        i_usdcPriceFeedDecimals = i_usdcPriceFeed.decimals();
        i_minimumDepositAmount = 10 * (10 ** i_usdcDecimals); // 10 USDC with decimals
        i_reservesOracle = IReservesOracle(_reservesOracle);
        i_bondOracle = IBondOracle(_bondOracle);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC3525, AccessControl) returns (bool) {
         return ERC3525.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    function openNewPosition(
        address _mintTo,
        uint256 _slot,
        uint256 _value
    ) public onlyValidSlot(_slot) whenNotpaused{
        // @audit-issue implement openNewPosition function
        if (_value < i_minimumDepositAmount) {
            revert TreasuryBondToken__InvalidValue();
        }
        // 1. ERC-3463 checks
        // 2. TransferFrom caller di usdc _value to this contract
        // prendere una base fee di ingress
        (uint256 netAmount, uint256 feeCollected) = _calculateEntryFees(_value);
        // 3. _beforeValueTransfer hook to update internal accounting
        // update total value for the slot
        // 4. _mint the ERC-3525 token to the user with the specified slot
        // 5. Update positionData struct
        // 6. _afterValueTransfer hook to update internal accounting
    }

    function closePosition(uint256 _tokenId) public whenNotpaused{
        if (!_isApprovedOrOwner(_msgSender(), _tokenId)) {
            revert TreasuryBondToken__NotApprovedOrOwner();
        }
        // @audit-issue implement closePosition function
        // 1. ERC-3463 checks
        // 2. _beforeValueTransfer hook to update internal accounting
        // 3. dal value del token calcolo il controvalore in USDC e poi calcolo le fee di uscita
        //(uint256 netAmount, uint256 feeCollected) = _collectExitFees(value, maturityTime);
        // 3. TransferFrom this contract to caller the USDC value of the burned token
        // update total value for the slot
        // 4. Burn the specified ERC-3525 token
        _burn(_tokenId);
        // 5. _afterValueTransfer hook to update internal accounting
    }

    function closePartialPosition(
        uint256 _tokenId,
        uint256 _valueToBurn
    ) public whenNotpaused{
        if (!_isApprovedOrOwner(_msgSender(), _tokenId)) {
            revert TreasuryBondToken__NotApprovedOrOwner();
        }
        // @audit-issue implement closePartialPosition function
        // 1. ERC-3463 checks
        // 2. _beforeValueTransfer hook to update internal accounting
        // 3. dal value del token calcolo il controvalore in USDC e poi calcolo le fee di uscita
        //(uint256 netAmount, uint256 feeCollected) = _collectExitFees(value, maturityTime);
        // 3. TransferFrom this contract to caller the USDC value of the burned portion of the token
        // 4. Burn the specified value from the ERC-3525 token
        // update total value for the slot
        _burnValue(_tokenId, _valueToBurn);
        // 5. _afterValueTransfer hook to update internal accounting
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
    ) public payable override etherNotAccepted whenNotPaused returns (uint256 newTokenId) {
        // @audit-issue implement T-REX checks
       // newTokenId = super.transferFrom(_fromTokenId, _to, _value);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted whenNotPaused{
        // @audit-issue implement checks
        // T-rex checks
        //super.transferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public payable override etherNotAccepted whenNotPaused {
        // @audit-issue implement checks
        // T-rex checks
        //super.safeTransferFrom(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted whenNotPaused {
        // @audit-issue implement checks
        // T-rex checks
        //super.safeTransferFrom(_from, _to, _tokenId, "");
    }

    function claimYield(uint256 _tokenId) public whenNotPaused {
        // @audit-issue implement claimYield function
        // verifica che msg.sender sia owner o approved del token
        // verifica che sia passato abbastanza tempo dall'ultimo claim (es. 30 gg)
        // chiama la funzione interna per calcolare e trasferire gli interessi maturati
        // sottrarre la percentuale di yield trattenuta dal protocollo come fee
        // update total fees collected
        // aggiornare total value per slot
        _claimYield(_tokenId);
    }


    function _mint(
            address _mintTo,
            uint256 _tokenId,
            uint256 _slot,
            uint256 _value
        ) internal override {
            // aggiornare l' accounting del tot value per slot prima di mintare
            // @audit-info questo aggiornamento va fatto dentro _beforeValueTransfer o _afterValueTransfer? va valutato se è necessario distinguere tra mint, burn e transfer
            super._mint(_mintTo, _tokenId, _slot, _value);
    }

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
    ) internal override {
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
       


        // 2. Checks Reserves oracle
        // aggiornare l' accounting del tot value per slot prima di mintare
    }

    function _beforeBurn(
        address _from,
        uint256 _fromTokenId,
        uint256 _slot,
        uint256 _value
    ) internal {

        // aggiornare l' accounting del tot value per slot prima di burnare
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


    /// @inheritdoc ERC3643
    function _executeRecoveryTransfer(
        address lostWallet,
        address newWallet
    ) internal override {
        // balanceOf(address) restituisce il numero di token ERC721 posseduti
        uint256 tokenCount = balanceOf(lostWallet);

        // Snapshot degli id PRIMA di trasferire (l'array cambia ad ogni trasferimento)
        uint256[] memory tokenIds = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(lostWallet, i);
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // I frozen values sono mappati per tokenId → seguono il token automaticamente,
            // non serve migrarli (il mapping s_frozenValues[tokenId] rimane invariato).

            // _transferTokenId è internal in ERC3525 e bypassa il check onlyApprovedOrOwner
            _transferTokenId(lostWallet, newWallet, tokenId);
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
        * @notice Internal function to retrieve the NAV for a given slot from the Reserves Oracle.
        * @notice getNav reverts on reservesOracle contract if the data is stale, so no need to check staleness here
        * @param _slot The slot ID for which to retrieve the NAV (1 for 2Y, 2 for 5Y, 3 for 10Y, 4 for 30Y).
        * @return slotNav The NAV value for the specified slot.
        * @return navDecimals The number of decimals of the NAV value returned by the oracle.
     */
    function _getNav(uint256 _slot) internal view returns (uint256 slotNav, uint8 navDecimals) {
        slotNav = i_reservesOracle.getNav(_slot);
        navDecimals = i_reservesOracle.getDecimals(); 
    }


    function _calculateEntryFees(
        uint256 _amount
    ) internal returns (uint256 netAmount, uint256 feeCollected) {
        feeCollected = (_amount * PERCENTAGE_ENTRY_FEE) / C.PERCENTAGE_PRECISION;
        netAmount = _amount - feeCollected;
    }

    function _calculateExitFees(
        uint256 _amount,
        uint256 _maturityTime
    ) internal returns (uint256 netAmount, uint256 feeCollected) {
        // @audit-issue implement exit fee calculation
        // se il token è maturo non applicare fee
        // altrimenti applica anche una fee di uscita anticipata ponderata sulla diff tra scadenza e timestamp (es. 2%)
    }

    function _calculateYieldFees(uint256 _yieldAmount) internal returns (uint256 netYield, uint256 feeCollected) {
        // feeCollected = (_yieldAmount * PERCENTAGE_YIELD_FEE) / C.PERCENTAGE_PRECISION;
        // netYield = _yieldAmount - feeCollected;
    }

    function _convertUsdcUsd(
        uint256 _amount,
        bool _usdcToUsd
    ) internal view returns (uint256) {
        // @audit-issue implement convertUsdcUsd function
        // se _usdcToUsd è true, converti l'amount da USDC a USD usando il price feed di Chainlink
        // altrimenti converti da USD a USDC
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

    function _notAcceptEther() internal view {
        if (msg.value > 0) {
            revert TreasuryBondToken__EtherNotAccepted();
        }
    }


    /**
     * @notice Returns the total value deposited for a specific bond slot (maturity).
     * @dev Each slot represents a different bond maturity (2Y, 5Y, 10Y, 30Y).
     * @param _slot The slot ID representing the bond maturity.
     * @return The total value (in USDC) deposited in the specified slot.
     */
    function getTotalValuePerSlot(
        uint256 _slot
    ) external view onlyValidSlot(_slot) returns (uint256) {
        return s_totalValuePerSlot[_slot];
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
     * @notice Returns the total fees collected by the protocol.
     * @dev Fees are collected on yield and entry operations.
     * @return The total amount of fees collected (in USDC).
     */
    function getTotalFeesCollected() external view returns (uint256) {
        return s_totalFeesCollected;
    }


    function getLiabilitiesForSlot(uint256 _slot) external view onlyValidSlot(_slot) returns (uint256) {
         return s_totalValuePerSlot[_slot];
    }


    // @audit-issue move to a separated risk managment contract
    function getLiabilitiesForAllSlots() external view returns (uint256[4] memory) {
        uint256[4] memory liabilities;
        liabilities[0] = s_totalValuePerSlot[C.SLOT_2Y];
        liabilities[1] = s_totalValuePerSlot[C.SLOT_5Y];
        liabilities[2] = s_totalValuePerSlot[C.SLOT_10Y];
        liabilities[3] = s_totalValuePerSlot[C.SLOT_30Y];
        return liabilities;
    }

}
