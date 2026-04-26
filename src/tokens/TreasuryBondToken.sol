//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC3525} from "./ERC3525.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IIdentityRegistry
} from "@t-rex/registry/interface/IIdentityRegistry.sol";
import {IBondOracle} from "../interfaces/IBondOracle.sol";
import {IReservesOracle} from "../interfaces/IReservesOracle.sol";

/**
 * @title TreasuryBondToken
 * @notice ERC-3525 token representing fractionalized positions in US Treasury bonds.
 * Each slot corresponds to a different bond maturity (2Y, 5Y, 10Y, 30Y).
 * Users can open new positions by depositing USDC and minting tokens, or close positions by burning tokens and withdrawing USDC.
 * The contract includes role-based access control for fee management and administrative functions.
 */
contract TreasuryBondToken is ERC3525, AccessControl {
    event IdentityRegistryAdded(address indexed identityRegistry);

    error TreasuryBondToken__InvalidSlot();
    error TreasuryBondToken__FunctionDisabled();
    error TreasuryBondToken__NotApprovedOrOwner();
    error TreasuryBondToken__EtherNotAccepted();
    error TreasuryBondToken__InvalidValue();
    error TreasuryBondToken__InvalidName();
    error TreasuryBondToken__InvalidSymbol();
    error TreasuryBondToken__InvalidDecimals();
    error TreasuryBondToken__ZeroAddress();

    uint256 public constant SLOT_2Y = 1; // 2-Year Treasury exposure
    uint256 public constant SLOT_5Y = 2; // 5-Year Treasury exposure
    uint256 public constant SLOT_10Y = 3; // 10-Year Treasury exposure
    uint256 public constant SLOT_30Y = 4; // 30-Year Treasury exposure

    uint256 public constant PERCENTAGE_PRECISION = 10000; // For percentage calculations (e.g., 5% = 50000)
    uint256 private constant MAX_PERCENTAGE = 100 * PERCENTAGE_PRECISION; // 100% in percentage precision
    uint256 public constant PERCENTAGE_YIELD_FEE = 10 * PERCENTAGE_PRECISION; // 10% fee on yield
    uint256 public constant PERCENTAGE_ENTRY_FEE = 1 * PERCENTAGE_PRECISION; // 1% fee on entry

    IERC20 private immutable i_usdc;
    AggregatorV3Interface private immutable i_usdcPriceFeed;
    uint8 private immutable i_usdcDecimals; // 6 for usdc
    uint8 private immutable i_usdcPriceFeedDecimals; // 8 for chainlink price feed
    uint256 private immutable i_minimumDepositAmount; // 10 USDC

    IReservesOracle private immutable i_reservesOracle;
    IBondOracle private immutable i_bondOracle;

    IIdentityRegistry private s_tokenIdentityRegistry;

    mapping(uint256 => uint256) private s_totalValuePerSlot;
    uint256 private s_totalFeesCollected;

    bytes32 public constant FEES_MANAGER_ROLE = keccak256("FEES_MANAGER_ROLE");

    modifier onlyValidSlot(uint256 slot) {
        _onlyValidSlot(slot);
        _;
    }

    modifier etherNotAccepted() {
        _notAcceptEther();
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
    ) ERC3525(_name, _symbol, _decimals) {
        // Checks
        if (bytes(_name).length == 0) revert TreasuryBondToken__InvalidName();
        if (bytes(_symbol).length == 0)
            revert TreasuryBondToken__InvalidSymbol();
        if (_decimals == 0 || _decimals > 18)
            revert TreasuryBondToken__InvalidDecimals();
        if (
            _usdcAddress == address(0) ||
            _usdcPriceFeedAddress == address(0) ||
            _identityRegistry == address(0) ||
            _reservesOracle == address(0) ||
            _bondOracle == address(0) ||
            _feesCollector == address(0)
        ) revert TreasuryBondToken__ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEES_MANAGER_ROLE, _feesCollector);
        i_usdc = IERC20(_usdcAddress);
        i_usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeedAddress);
        i_usdcDecimals = IERC20Metadata(_usdcAddress).decimals();
        i_usdcPriceFeedDecimals = i_usdcPriceFeed.decimals();
        i_minimumDepositAmount = 10 * (10 ** i_usdcDecimals); // 10 USDC with decimals
        i_reservesOracle = IReservesOracle(_reservesOracle);
        i_bondOracle = IBondOracle(_bondOracle);
        setIdentityRegistry(_identityRegistry);
    }

    function setIdentityRegistry(
        address _identityRegistry
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        s_tokenIdentityRegistry = IIdentityRegistry(_identityRegistry);
        emit IdentityRegistryAdded(_identityRegistry);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC3525, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function openNewPosition(
        address _mintTo,
        uint256 _slot,
        uint256 _value
    ) public onlyValidSlot(_slot) {
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
        // 5. _afterValueTransfer hook to update internal accounting
    }

    function closePosition(uint256 _tokenId) public {
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
        ERC3525._burn(_tokenId);
        // 5. _afterValueTransfer hook to update internal accounting
    }

    function closePartialPosition(
        uint256 _tokenId,
        uint256 _valueToBurn
    ) public {
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
        ERC3525._burnValue(_tokenId, _valueToBurn);
        // 5. _afterValueTransfer hook to update internal accounting
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
    ) public payable override etherNotAccepted returns (uint256 newTokenId) {
        // @audit-issue implement T-REX checks
        newTokenId = super.transferFrom(_fromTokenId, _to, _value);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted {
        // @audit-issue implement checks
        // T-rex checks
        super.transferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public payable override etherNotAccepted {
        // @audit-issue implement checks
        // T-rex checks
        super.safeTransferFrom(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public payable override etherNotAccepted {
        // @audit-issue implement checks
        // T-rex checks
        super.safeTransferFrom(_from, _to, _tokenId, "");
    }

    function claimYield(uint256 _tokenId) public {
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
        address mintTo_,
        uint256 tokenId_,
        uint256 slot_,
        uint256 value_
    ) internal override {
        // aggiornare l' accounting del tot value per slot prima di mintare
        // @audit-info questo aggiornamento va fatto dentro _beforeValueTransfer o _afterValueTransfer? va valutato se è necessario distinguere tra mint, burn e transfer
        super._mint(mintTo_, tokenId_, slot_, value_);
    }

    function _claimYield(uint256 _tokenId) internal {
        // 1. Recupera lo slot, il valore del token e calcola gli interessi maturati in base al tempo trascorso
        // 2. Trasferisci gli interessi maturati in USDC al possessore del token
        // si può usare la func public che avrà un intervallo di tempo minimo tra due claim per evitare abusi
        // questa funzione viene usata anche durante i transfer
        // emette l' evento di interesse maturato
    }

    function _beforeValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal override {
        // se mint skip compliance sul sender
        // se burn skip compliance sul receiver
        // se transfer compliance su entrambi
    }

    /**
     * @notice Hook that is called after any transfer of value. This includes minting and burning.
     * @dev This function can be used to implement custom logic that needs to run after value transfers.
     * @param from_ The address which previously owned the token (zero address if minting).
     * @param to_ The address which will receive the token (zero address if burning).
     * @param fromTokenId_ The token ID from which value is being transferred (zero if minting).
     * @param toTokenId_ The token ID to which value is being transferred (zero if burning).
     * @param slot_ The slot of the token being transferred.
     * @param value_ The amount of value being transferred.
     */
    function _afterValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal override {}

    function _calculateEntryFees(
        uint256 _amount
    ) internal returns (uint256 netAmount, uint256 feeCollected) {
        feeCollected = (_amount * PERCENTAGE_ENTRY_FEE) / PERCENTAGE_PRECISION;
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
            _slot != SLOT_2Y &&
            _slot != SLOT_5Y &&
            _slot != SLOT_10Y &&
            _slot != SLOT_30Y
        ) {
            revert TreasuryBondToken__InvalidSlot();
        }
    }

    function _notAcceptEther() internal view {
        if (msg.value > 0) {
            revert TreasuryBondToken__EtherNotAccepted();
        }
    }

    function getTotalValuePerSlot(
        uint256 _slot
    ) external view onlyValidSlot(_slot) returns (uint256) {
        return s_totalValuePerSlot[_slot];
    }

    function getTotalFeesCollected() external view returns (uint256) {
        return s_totalFeesCollected;
    }
}
