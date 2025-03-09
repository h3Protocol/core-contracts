// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {XH3rmes} from "../src/XH3rmes.sol";
import {H3rmesContractDeployer} from "../src/H3rmesContractDeployer.sol";

/**
 * @title Deploy XH3rmes Script
 * @notice Deploys XH3rmes governance token and initializes it
 * @dev Uses environment variables for configuration
 */
contract DeployXH3rmesScript is Script {
    // Config Constants from environment
    address deployer;
    address admin;
    address devFund;
    address operator;
    uint256 deployerPrivateKey;
    bool useExistingDeployer;
    address existingDeployerAddress;
    string version;
    uint256 startTime;
    bool distributeInitialRewards;
    address rewardPool;

    // Deployed contracts
    H3rmesContractDeployer public h3rmesDeployer;
    XH3rmes public xh3rmes;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load config from environment
        deployer = vm.envOr("DEPLOYER", address(0));
        admin = vm.envOr("ADMIN", address(0));
        devFund = vm.envOr("DEV_FUND", address(0));
        operator = vm.envOr("OPERATOR", address(0));

        // Start time can be specified or defaults to current timestamp
        startTime = vm.envOr("XH3RMES_START_TIME", block.timestamp);

        // Only load private keys if deploying
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        useExistingDeployer = vm.envOr("USE_EXISTING_DEPLOYER", false);
        existingDeployerAddress = vm.envOr("EXISTING_DEPLOYER_ADDRESS", address(0));
        version = vm.envOr("XH3RMES_VERSION", string("v1.0"));

        distributeInitialRewards = vm.envOr("DISTRIBUTE_INITIAL_REWARDS", false);
        rewardPool = vm.envOr("REWARD_POOL_ADDRESS", address(0));

        // If using real deployment, ensure required addresses are set
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            require(deployer != address(0), "DEPLOYER must be set");
            require(devFund != address(0), "DEV_FUND must be set");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (admin == address(0)) admin = msg.sender;
        if (devFund == address(0)) devFund = msg.sender;
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
            h3rmesDeployer = new H3rmesContractDeployer(admin, deployer);
            console.log("H3rmesContractDeployer deployed at:", address(h3rmesDeployer));
        }

        // Step 2: Prepare XH3rmes bytecode with constructor arguments
        bytes memory xh3rmesBytecode =
            abi.encodePacked(type(XH3rmes).creationCode, abi.encode(startTime, devFund, operator));

        // Step 3: Deploy XH3rmes using the deployer
        address xh3rmesAddress = h3rmesDeployer.deploy(xh3rmesBytecode, "XH3rmes", version);
        xh3rmes = XH3rmes(xh3rmesAddress);
        console.log("XH3rmes deployed at:", xh3rmesAddress);

        // Optional: Distribute initial rewards to reward pool
        if (distributeInitialRewards) {
            if (rewardPool != address(0)) {
                xh3rmes.distributeReward(rewardPool);
                console.log("Initial rewards distributed to rewardPool:", rewardPool);
            } else {
                console.log("WARNING: Initial rewards distribution enabled but REWARD_POOL_ADDRESS not set");
                console.log("To distribute rewards later, call xh3rmes.distributeReward(rewardPoolAddress)");
            }
        }

        // Log vesting schedule info
        uint256 endTime = xh3rmes.endTime();
        uint256 vestingDuration = (endTime - startTime) / 1 days; // Convert to days for readable output

        // Log deployed contract info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("H3rmesContractDeployer:", address(h3rmesDeployer));
        console.log("XH3rmes:", xh3rmesAddress);
        console.log("Admin:", admin);
        console.log("Dev Fund:", devFund);
        console.log("Version:", version);
        console.log("Vesting Start:", startTime);
        console.log("Vesting End:", endTime);
        console.log("Vesting Duration:", vestingDuration, "days");
        console.log("Rewards Distribution Enabled:", distributeInitialRewards);

        if (distributeInitialRewards && rewardPool != address(0)) {
            console.log("Reward Pool:", rewardPool);
            console.log("Initial Rewards Distributed:", xh3rmes.REWARD_POOL_ALLOCATION() / 1e18, "XH3RMES");
        }

        console.log("Rewards Already Distributed:", xh3rmes.rewardsDistributed());
        console.log("Dev Fund Reward Rate:", xh3rmes.devFundRewardRate() / 1e18, "XH3RMES per second");
        console.log("Dev Fund Total Allocation:", xh3rmes.DEV_FUND_POOL_ALLOCATION() / 1e18, "XH3RMES");
        console.log("========================\n");

        vm.stopBroadcast();
    }
}
