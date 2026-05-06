//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {TokenConstants as C} from "../tokens/TokenConstants.sol";

library YieldsMath {
 
    function calculateNetYieldAndFee(uint256 _baseAmount,uint256 _grossYield, uint256 _percentageOnYield) internal pure returns (uint256 netYieldAmount, uint256 yieldFeeAmount) {
        uint256 totalYield = _baseAmount * _grossYield / C.MAX_PERCENTAGE; 
        yieldFeeAmount = totalYield * _percentageOnYield / C.MAX_PERCENTAGE;
        netYieldAmount = totalYield - yieldFeeAmount;
    }
}
