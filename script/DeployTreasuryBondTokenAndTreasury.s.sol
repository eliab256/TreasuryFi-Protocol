//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {TreasuryBondToken} from "../src/tokens/TreasuryBondToken.sol";
import {Treasury} from "../src/tokens/Treasury.sol";
import {TreasuryBondTokenConstructorParams} from "../src/types.sol";

contract DeployTreasuryBondTokenAndTreasury is Script {
    function run(address _identityRegistry,
        address _bondAutomation, 
        address _reservesAutomation, 
        address _reservesOracle, 
        address _bondOracle
        ) external returns(TreasuryBondToken, Treasury) { 

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast(config.deployer);
        // Deploy treasury contract
        Treasury treasury = deployTreasury(config);

        // Deploy token contract, passing treasury address in the constructor
        TreasuryBondToken treasuryBondToken = deployToken(helperConfig, _identityRegistry, _bondAutomation, _reservesAutomation, 
          _reservesOracle, _bondOracle, address(treasury));

        // After deploying token contract, set token contract address on treasury
        setTokenContractOnTreasury(address(treasury), address(treasuryBondToken));

        vm.stopBroadcast();

        return (treasuryBondToken, treasury);
    }

    function deployTreasury(HelperConfig.NetworkConfig memory config) public returns (Treasury) {
    
        console.log('======================= Treasury Deployment =================');

        Treasury treasury = new Treasury(config.usdcAddress, config.feesCollector, config.deployer);

        console.log('Treasury deployed at:', address(treasury));
        console.log('==============================================================');
        console.log('');

        return treasury;
    }

    /**
     * @notice Sets the token contract address on the treasury.
     * @dev This function needs to be called after deploying the Treasury and TreasuryBondToken contracts. 
     * @param _treasury The address of the treasury contract.
     * @param _tokenContract The address of the token contract to be set.
     */
    function setTokenContractOnTreasury(address _treasury, address _tokenContract) public {
        console.log('======================= Setting Token Contract on Treasury =================');
        Treasury treasury = Treasury(_treasury);
        treasury.setTokenContract(_tokenContract);
        console.log('Token contract set on Treasury: ', _tokenContract);
        console.log('==============================================================');
        console.log('');
    }

    function deployToken(HelperConfig helperConfig, 
        address _identityRegistry,
        address _bondAutomation, 
        address _reservesAutomation, 
        address _reservesOracle, 
        address _bondOracle, 
        address _treasury) public returns (TreasuryBondToken) {
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        console.log('================== Building TreasuryBondToken Deployment Params ==============');

        TreasuryBondTokenConstructorParams memory params = TreasuryBondTokenConstructorParams({
            decimalsStandard: config.decimals,
            usdcAddress: config.usdcAddress,
            usdcPriceFeedAddress: config.usdcPriceFeedAddress,
            identityRegistry: _identityRegistry,
            bondAutomation: _bondAutomation,
            reservesAutomation: _reservesAutomation,
            reservesOracle: _reservesOracle,
            bondOracle: _bondOracle,
            feesCollector: config.feesCollector,
            treasury: _treasury
        });

        console.log('======================= TreasuryBondToken Deployment =================');

        TreasuryBondToken treasuryBondToken = new TreasuryBondToken(params);

        console.log('TreasuryBondToken deployed at:', address(treasuryBondToken));
        console.log('==============================================================');
        console.log('');

        return treasuryBondToken;
    }
}