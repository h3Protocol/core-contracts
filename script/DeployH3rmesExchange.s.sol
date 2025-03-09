// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {H3rmesExchange} from "../src/H3rmesExchange.sol";
import {H3rmesContractDeployer} from "../src/H3rmesContractDeployer.sol";
import {H3rmes} from "../src/H3rmes.sol";
import {XH3rmes} from "../src/XH3rmes.sol";

/**
 * @title Deploy H3rmesExchange Script
 * @notice Deploys the H3rmesExchange contract for converting between H3rmes and XH3rmes
 * @dev Uses environment variables for configuration
 */
contract DeployH3rmesExchangeScript is Script {
    // Config Constants from environment
    address deployer;
    address owner;
    uint256 deployerPrivateKey;
    bool useExistingDeployer;
    address existingDeployerAddress;
    address h3rmesAddress;
    address xh3rmesAddress;
    string version;

    // Exchange configuration
    uint256 slashingPenalty;
    uint256 minVestDays;
    uint256 maxVestDays;

    // Deployed contracts
    H3rmesContractDeployer public h3rmesDeployer;
    H3rmesExchange public exchange;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load config from environment
        deployer = vm.envOr("DEPLOYER", address(0));
        owner = vm.envOr("EXCHANGE_OWNER", deployer);
        h3rmesAddress = vm.envOr("H3RMES_ADDRESS", address(0));
        xh3rmesAddress = vm.envOr("XH3RMES_ADDRESS", address(0));

        // Exchange configuration params
        slashingPenalty = vm.envOr("EXCHANGE_SLASHING_PENALTY", uint256(5000)); // Default: 50%
        minVestDays = vm.envOr("EXCHANGE_MIN_VEST_DAYS", uint256(7)); // Default: 7 days
        maxVestDays = vm.envOr("EXCHANGE_MAX_VEST_DAYS", uint256(30)); // Default: 30 days

        // Only load private keys if deploying
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        useExistingDeployer = vm.envOr("USE_EXISTING_DEPLOYER", false);
        existingDeployerAddress = vm.envOr("EXISTING_DEPLOYER_ADDRESS", address(0));
        version = vm.envOr("EXCHANGE_VERSION", string("v1.0"));

        // If using real deployment, ensure required addresses are set
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            require(deployer != address(0), "DEPLOYER must be set");
            require(owner != address(0), "EXCHANGE_OWNER must be set");
            require(h3rmesAddress != address(0), "H3RMES_ADDRESS must be set");
            require(xh3rmesAddress != address(0), "XH3RMES_ADDRESS must be set");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (owner == address(0)) owner = msg.sender;
        if (h3rmesAddress == address(0)) {
            console.log("Warning: H3RMES_ADDRESS not set, deployment will fail");
        }
        if (xh3rmesAddress == address(0)) {
            console.log("Warning: XH3RMES_ADDRESS not set, deployment will fail");
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
            h3rmesDeployer = new H3rmesContractDeployer(owner, deployer);
            console.log("H3rmesContractDeployer deployed at:", address(h3rmesDeployer));
        }

        // Convert vest times from days to seconds
        uint256 minVestSeconds = minVestDays * 1 days;
        uint256 maxVestSeconds = maxVestDays * 1 days;

        // Create exchange config struct
        H3rmesExchange.ExchangeConfig memory exchangeConfig = H3rmesExchange.ExchangeConfig({
            slashingPenalty: slashingPenalty,
            minVest: minVestSeconds,
            maxVest: maxVestSeconds
        });

        // Step 2: Prepare H3rmesExchange bytecode with constructor arguments
        bytes memory exchangeBytecode = abi.encodePacked(
            type(H3rmesExchange).creationCode, abi.encode(h3rmesAddress, xh3rmesAddress, owner, exchangeConfig)
        );

        // Step 3: Deploy H3rmesExchange using the deployer
        address exchangeAddress = h3rmesDeployer.deploy(exchangeBytecode, "H3rmesExchange", version);
        exchange = H3rmesExchange(exchangeAddress);
        console.log("H3rmesExchange deployed at:", exchangeAddress);

        // Step 4: Add exchange role to the H3rmesExchange contract
        H3rmes h3rmes = H3rmes(payable(h3rmesAddress));
        XH3rmes xh3rmes = XH3rmes(xh3rmesAddress);

        // Grant necessary roles if the deployer has permission
        if (h3rmes.hasRole(h3rmes.OPERATOR_ROLE(), deployer)) {
            h3rmes.setExchange(exchangeAddress);
            console.log("Exchange role granted to H3rmesExchange in H3rmes contract");
        } else {
            console.log("WARNING: Deployer does not have OPERATOR_ROLE on H3rmes contract");
            // console.log("To grant exchange role, call h3rmes.setExchange(" + vm.toString(exchangeAddress) + ")");
        }

        if (xh3rmes.hasRole(xh3rmes.OPERATOR_ROLE(), deployer)) {
            xh3rmes.setExchange(exchangeAddress);
            console.log("Exchange role granted to H3rmesExchange in XH3rmes contract");
        } else {
            console.log("WARNING: Deployer does not have OPERATOR_ROLE on XH3rmes contract");
            // console.log("To grant exchange role, call xh3rmes.setExchange(" + vm.toString(exchangeAddress) + ")");
        }

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("H3rmesContractDeployer:", address(h3rmesDeployer));
        console.log("H3rmesExchange:", exchangeAddress);
        console.log("H3rmes Token:", h3rmesAddress);
        console.log("XH3rmes Token:", xh3rmesAddress);
        console.log("Owner:", owner);
        console.log("Version:", version);
        console.log("Slashing Penalty:", slashingPenalty / 100, "%");
        console.log("Minimum Vest Time:", minVestDays, "days");
        console.log("Maximum Vest Time:", maxVestDays, "days");
        console.log("Exchange Config:");
        console.log("  - Slashing Penalty: ", slashingPenalty);
        console.log("  - Min Vest: ", minVestSeconds);
        console.log("  - Max Vest: ", maxVestSeconds);
        console.log("========================\n");

        vm.stopBroadcast();
    }
}
