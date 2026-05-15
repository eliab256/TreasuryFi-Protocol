//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BondYieldsResponse} from "../types.sol";

interface IBondOracle {
    error BondOracle__DataIsStale();
    error BondOracle__InvalidSlot();
    error BondOracle__ZeroAddress();
    error BondOracle__IncompleteResponse(uint256 length);
    error BondOracle__ConsumerAlreadySet();

    event YieldUpdated(
        uint256 twoYearYield,
        uint256 fiveYearYield,
        uint256 tenYearYield,
        uint256 thirtyYearYield,
        uint256 timestamp
    );
    event YieldUpdateFailed(bytes err);
    event ConsumerSet(address indexed consumer);

    /**
     * @notice Returns the yield for a given slot (1=2Y, 2=5Y, 3=10Y, 4=30Y)
     * @dev Reverts if data is stale or slot is invalid
     * @param slot The slot for which to return the yield
     * @return The yield for the given slot
     */ 
    function getYield(uint256 slot) external view returns (uint256);

    /**
     * @notice Function to retrive all the yields at once
     * @dev Reverts if data is stale
     * @return The yields for all slots and the timestamp of the last update
     */
    function getAllYields() external view returns (BondYieldsResponse memory);

    /**
     * @notice Function to update the yields for all slots at once
     * @dev Only callable by the authorized FunctionsConsumer contract. 
     * @dev Emits YieldUpdated event on success or YieldUpdateFailed on failure.
     * @param values An array containing the new yields for the 2Y, 5Y, 10Y, and 30Y bonds in that order.
     * @param timestamp The timestamp of when the data was fetched.
     * @param err The error message if the update failed.
     */
    function updateYields(uint256[] memory values, uint256 timestamp, bytes memory err) external;

    /**
     * @notice Returns true if the stored data is stale
     * @return True if the data is stale, false otherwise
     */
    function isStale() external view returns (bool);

    /**
     * @notice Returns the last update timestamp
     * @return The timestamp of the last update
     */
    function getLastUpdatedTimestamp() external view returns (uint256);

    /**
     * @notice Returns the address of the FunctionsConsumer contract authorized to update yields
     * @return The address of the FunctionsConsumer contract
     */ 
    function getFunctionsConsumer() external view returns (address);

    /**
     * @notice Sets the FunctionsConsumer contract address (one-shot, post-deploy).
     * @dev Can only be called once by DEFAULT_ADMIN_ROLE.
     * @param _consumer The address of the BondFunctionsConsumer contract.
     */
    function setFunctionsConsumer(address _consumer) external;

}
