// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {H3rmesContractDeployer} from "../src/H3rmesContractDeployer.sol";
import {H3rmes} from "../src/H3rmes.sol";
import {INonfungiblePositionManager} from "../src/interfaces/INonfungiblePositionManager.sol";
import {NativePositionManager} from "../src/NativePositionManager.sol";

/**
 * @title Deploy NativePositionManager Script
 * @notice Deploys the NativePositionManager contract that helps manage protocol liquidity positions
 * @dev Uses environment variables for configuration
 */
contract DeployNativePositionManagerScript is Script {
    // Config Constants from environment
    address deployer;
    address admin;
    address operator;
    uint256 deployerPrivateKey;
    bool useExistingDeployer;
    address existingDeployerAddress;
    address h3rmesAddress;
    address swapRouterAddress;
    address oSonicAddress;
    string version;

    // Deployed contracts
    H3rmesContractDeployer public h3rmesDeployer;
    NativePositionManager public positionManager;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load config from environment
        deployer = vm.envOr("DEPLOYER", address(0));
        operator = vm.envOr("OPERATOR", deployer);
        h3rmesAddress = vm.envOr("H3RMES_ADDRESS", address(0));
        swapRouterAddress = vm.envOr("SWAP_ROUTER_ADDRESS", address(0));
        oSonicAddress = vm.envOr("OSONIC_ADDRESS", address(0));

        // Only load private keys if deploying
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        useExistingDeployer = vm.envOr("USE_EXISTING_DEPLOYER", false);
        existingDeployerAddress = vm.envOr("EXISTING_DEPLOYER_ADDRESS", address(0));
        version = vm.envOr("NATIVE_POSITION_MANAGER_VERSION", string("v1.0"));

        // If using real deployment, ensure required addresses are set
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            require(deployer != address(0), "DEPLOYER must be set");
            require(h3rmesAddress != address(0), "H3RMES_ADDRESS must be set");
            require(swapRouterAddress != address(0), "SWAP_ROUTER_ADDRESS must be set");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (admin == address(0)) admin = msg.sender;
        if (h3rmesAddress == address(0)) {
            console.log("Warning: H3RMES_ADDRESS not set, deployment will fail");
        }
        if (swapRouterAddress == address(0)) {
            console.log("Warning: SWAP_ROUTER_ADDRESS not set, deployment will fail");
        }
    }

    /**
     * @notice Main deployment function
     */
    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy or connect to existing H3rmesContractDeployer
        if (useExistingDeployer) {
            console.log("Using existing deployer at:", existingDeployerAddress);
            h3rmesDeployer = H3rmesContractDeployer(existingDeployerAddress);
        } else {
            console.log("Deploying new H3rmesContractDeployer");
            h3rmesDeployer = new H3rmesContractDeployer(admin, admin);
            console.log("H3rmesContractDeployer deployed at:", address(h3rmesDeployer));
        }

        // Step 2: Prepare NativePositionManager bytecode with constructor arguments
        NativePositionManager.NativePositionManagerConfig memory config = NativePositionManager
            .NativePositionManagerConfig({
            h3rmes: h3rmesAddress,
            swapRouter: swapRouterAddress,
            wrappedSonic: 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38,
            oSonic: oSonicAddress,
            minSlippage: 50 // 0.5% slippage
        });
        bytes memory positionManagerBytecode =
            abi.encodePacked(type(NativePositionManager).creationCode, abi.encode(config, operator));

        // Step 3: Deploy NativePositionManager using the deployer
        address positionManagerAddress =
            h3rmesDeployer.deploy(positionManagerBytecode, "NativePositionManager", version);
        positionManager = NativePositionManager(positionManagerAddress);
        console.log("NativePositionManager deployed at:", positionManagerAddress);

        // Step 4: Grant POSITION_MANAGER_ROLE to the position manager in H3rmes contract
        H3rmes h3rmes = H3rmes(payable(h3rmesAddress));
        if (h3rmes.hasRole(h3rmes.OPERATOR_ROLE(), deployer)) {
            h3rmes.addPositionManagerContract(positionManagerAddress);
            console.log("Position manager role granted to NativePositionManager in H3rmes contract");
        } else {
            console.log("WARNING: Deployer does not have OPERATOR_ROLE on H3rmes contract");
            console.log(
                "To grant position manager role, call h3rmes.addPositionManagerContract(", positionManagerAddress, ")"
            );
        }

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("H3rmesContractDeployer:", address(h3rmesDeployer));
        console.log("NativePositionManager:", positionManagerAddress);
        console.log("H3rmes Token:", h3rmesAddress);
        console.log("Admin:", admin);
        console.log("Operator:", operator);
        console.log("Version:", version);
        console.log("========================\n");

        vm.stopBroadcast();
    }
}
