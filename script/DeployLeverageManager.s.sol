// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DeployH3rmesScript} from "./DeployH3rmes.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Deploy H3rmes on Tenderly Sonic RPC
 * @notice Specialized deployment for Tenderly environment
 */
contract DeployH3rmesTenderlyScript is Script {
    DeployH3rmesScript public deployScript;

    function setUp() public {
        // Create the main deploy script
        deployScript = new DeployH3rmesScript();

        // Configure for Tenderly
        vm.setEnv("NETWORK", "tenderly_sonic");

        // Default values if not set in .env
        if (vm.envOr("OSONIC_ADDRESS", address(0)) == address(0)) {
            vm.setEnv("OSONIC_ADDRESS", vm.toString(address(0xb1e25689D55734FD3ffFc939c4C3Eb52DFf8A794)));
        }
        if (vm.envOr("OSONIC_ZAPPER_ADDRESS", address(0)) == address(0)) {
            vm.setEnv("OSONIC_ZAPPER_ADDRESS", vm.toString(address(0xe25A2B256ffb3AD73678d5e80DE8d2F6022fAb21)));
        }

        deployScript.setUp();
    }

    function run() public {
        console.log("Deploying H3rmes on Tenderly Sonic Network");
        console.log("RPC URL: https://virtual.sonic.rpc.tenderly.co/aeb15215-2c9d-4b08-b96c-ec909043c708");

        // Check if we have gas info from network
        uint256 gasPrice;
        try vm.rpc("eth_gasPrice", "") returns (bytes memory result) {
            gasPrice = abi.decode(result, (uint256));
            console.log("Current gas price:", gasPrice);
        } catch {
            console.log("Couldn't fetch gas price. Using default.");
        }

        // Run the deployment
        deployScript.run();
    }
}
