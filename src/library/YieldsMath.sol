//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "../tokens/TokenConstants.sol";

library YieldsMath {
    
    function calculatePrincipalUsd(uint256 _tokenBalance, uint256 _entryNAV, uint256 _parValue) internal pure returns (uint256 principalUsd) {
        principalUsd = (_tokenBalance * _entryNAV) / _parValue;
    }
    


   function calculateCurrentNAV(
    uint256 _parValue,
    uint256 _entryYield,
    uint256 _currentYield,
    uint256 _dMod
    ) internal pure returns (uint256 currentNAV) {
        uint256 yieldDifference;
        if (_currentYield > _entryYield) {
             yieldDifference = _currentYield - _entryYield;
            uint256 navDiscount = (_dMod * yieldDifference) / C.PERCENTAGE_PRECISION;

            if (navDiscount >= C.MAX_PERCENTAGE) { return 0; }
            return (_parValue * (C.MAX_PERCENTAGE - navDiscount)) / C.MAX_PERCENTAGE;
        }
         
        yieldDifference = _entryYield - _currentYield;
        uint256 navPremium = (_dMod * yieldDifference) / C.PERCENTAGE_PRECISION;
        return (_parValue * (C.MAX_PERCENTAGE + navPremium)) / C.MAX_PERCENTAGE;
    }
}
