//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BondYieldsResponse} from "../types.sol";

interface IBondOracle {
    /// @notice Returns the yield for a given slot (1=2Y, 2=5Y, 3=10Y, 4=30Y)
    /// @dev Reverts if data is stale or slot is invalid
    function getYield(uint256 slot) external view returns (uint64);

    /// @notice Returns true if the stored data is stale
    function isStale() external view returns (bool);

    /// @notice Returns the last update timestamp
    function getLastUpdatedTimestamp() external view returns (uint256);

    function getFunctionsConsumer() external view returns (address);
}
