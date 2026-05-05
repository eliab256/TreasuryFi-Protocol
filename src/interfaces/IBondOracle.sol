//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BondYieldsResponse} from "../types.sol";

interface IBondOracle {
    error BondOracle__DataIsStale();
    error BondOracle__InvalidSlot();
    error BondOracle__ZeroAddress();
    error BondOracle__IncompleteResponse(uint256 length);

    event YieldUpdated(
        uint256 twoYearYield,
        uint256 fiveYearYield,
        uint256 tenYearYield,
        uint256 thirtyYearYield,
        uint256 timestamp
    );
    event YieldUpdateFailed(bytes err);

    /// @notice Returns the yield for a given slot (1=2Y, 2=5Y, 3=10Y, 4=30Y)
    /// @dev Reverts if data is stale or slot is invalid
    function getYield(uint256 slot) external view returns (uint256);
    function getAllYields() external view returns (BondYieldsResponse memory);
    function updateYields(uint256[] memory values, uint256 timestamp, bytes memory err) external;

    /// @notice Returns true if the stored data is stale
    function isStale() external view returns (bool);

    /// @notice Returns the last update timestamp
    function getLastUpdatedTimestamp() external view returns (uint256);

    /// @notice Returns the address of the FunctionsConsumer contract authorized to update yields
    function getFunctionsConsumer() external view returns (address);

}
