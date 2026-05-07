//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "../tokens/TokenConstants.sol";

library YieldsMath {
 
    function calculateNetYieldAndFee(uint256 _baseAmount,uint256 _grossYield, uint256 _percentageOnYield) internal pure returns (uint256 netYieldAmount, uint256 yieldFeeAmount) {
        uint256 totalYield = _baseAmount * _grossYield / C.MAX_PERCENTAGE; 
        yieldFeeAmount = totalYield * _percentageOnYield / C.MAX_PERCENTAGE;
        netYieldAmount = totalYield - yieldFeeAmount;
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
