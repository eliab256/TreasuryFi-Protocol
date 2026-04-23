//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct BondYieldsResponse {
    uint64 twoYearYield;
    uint64 fiveYearYield;
    uint64 tenYearYield;
    uint64 thirtyYearYield;
    uint256 timestamp;
}

struct SpvNavsResponse {
    uint256 twoYearNav;
    uint256 fiveYearNav;
    uint256 tenYearNav;
    uint256 thirtyYearNav;
    uint256 timestamp;
}
