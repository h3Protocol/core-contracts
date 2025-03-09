// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {H3rmesContractDeployer} from "../src/H3rmesContractDeployer.sol";

/**
 * @title Deploy H3rmesContractDeployer Script
 * @notice Deploys the contract deployer used by all H3rmes protocol contracts
 * @dev Uses environment variables for configuration
 */
contract DeployH3rmesDeployerScript is Script {
    // Config Constants from environment
    address deployer;
    address admin;
    address operator;
    uint256 deployerPrivateKey;

    // Deployed contract
    H3rmesContractDeployer public h3rmesDeployer;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load config from environment
        deployer = vm.envOr("DEPLOYER", address(0));
        admin = vm.envOr("ADMIN", address(0));
        operator = vm.envOr("OPERATOR", address(0));

        // Only load private keys if deploying
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (admin == address(0)) admin = msg.sender;
        if (operator == address(0)) operator = msg.sender;
    }

    /**
     * @notice Main deployment function
     */
    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the H3rmesContractDeployer
        console.log("Deploying H3rmesContractDeployer...");
        h3rmesDeployer = new H3rmesContractDeployer(admin, operator);

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("H3rmesContractDeployer:", address(h3rmesDeployer));
        console.log("Admin:", admin);
        console.log("Operator:", operator);
        console.log("========================\n");

        vm.stopBroadcast();
    }
}
