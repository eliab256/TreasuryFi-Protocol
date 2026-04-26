//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BondYieldsResponse} from "../types.sol";

interface IBondOracle {
    error BondOracle__DataIsStale();
    error BondOracle__InvalidSlot();

    event YieldUpdated(
        uint64 twoYearYield,
        uint64 fiveYearYield,
        uint64 tenYearYield,
        uint64 thirtyYearYield,
        uint256 indexed timestamp
    );

    event YieldUpdateFailed(bytes err);

    /// @notice Returns the yield for a given slot (1=2Y, 2=5Y, 3=10Y, 4=30Y)
    /// @dev Reverts if data is stale or slot is invalid
    function getYield(uint256 slot) external view returns (uint64);

    /// @notice Returns true if the stored data is stale
    function isStale() external view returns (bool);

    /// @notice Returns the last update timestamp
    function getLastUpdatedTimestamp() external view returns (uint256);

    function getFunctionsConsumer() external view returns (address);

    /// @notice Called by BondFunctionsConsumer to push new yield data
    function updateYield(bytes memory response, bytes memory err) external;
}
