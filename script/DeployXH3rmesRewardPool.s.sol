// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {XH3rmesRewardPool} from "../src/XH3rmesRewardPool.sol";
import {H3rmesContractDeployer} from "../src/H3rmesContractDeployer.sol";
import {IAlgebraPool} from "../src/interfaces/IAlgebraPool.sol";
import {INonfungiblePositionManager} from "../src/interfaces/INonfungiblePositionManager.sol";
import {XH3rmes} from "../src/XH3rmes.sol";

/**
 * @title Deploy XH3rmesRewardPool Script
 * @notice Deploys the XH3rmesRewardPool contract and initializes it
 * @dev Uses environment variables for configuration
 */
contract DeployXH3rmesRewardPoolScript is Script {
    // Config Constants from environment
    address deployer;
    address admin;
    address operator;
    uint256 deployerPrivateKey;
    bool useExistingDeployer;
    address existingDeployerAddress;
    address xh3rmesAddress;
    address nftManagerAddress;
    string version;
    uint256 poolStartTime;
    uint256 xh3rmesPerSecond;
    bool addInitialPools;

    // Deployed contracts
    H3rmesContractDeployer public h3rmesDeployer;
    XH3rmesRewardPool public rewardPool;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load config from environment
        deployer = vm.envOr("DEPLOYER", address(0));
        admin = vm.envOr("ADMIN", deployer);
        operator = vm.envOr("OPERATOR", deployer);
        xh3rmesAddress = vm.envOr("XH3RMES_ADDRESS", address(0));
        nftManagerAddress = vm.envOr("NFT_MANAGER_ADDRESS", address(0));

        // Pool parameters
        poolStartTime = vm.envOr("POOL_START_TIME", block.timestamp + 1 days);
        xh3rmesPerSecond = vm.envOr("XH3RMES_PER_SECOND", uint256(0.01 ether)); // Default 0.01 tokens per second

        // Only load private keys if deploying
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        useExistingDeployer = vm.envOr("USE_EXISTING_DEPLOYER", false);
        existingDeployerAddress = vm.envOr("EXISTING_DEPLOYER_ADDRESS", address(0));
        version = vm.envOr("REWARD_POOL_VERSION", string("v1.0"));

        addInitialPools = vm.envOr("ADD_INITIAL_POOLS", false);

        // If using real deployment, ensure required addresses are set
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            require(deployer != address(0), "DEPLOYER must be set");
            require(admin != address(0), "ADMIN must be set");
            require(xh3rmesAddress != address(0), "XH3RMES_ADDRESS must be set");
            require(nftManagerAddress != address(0), "NFT_MANAGER_ADDRESS must be set");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (admin == address(0)) admin = msg.sender;
        if (xh3rmesAddress == address(0)) {
            console.log("Warning: XH3RMES_ADDRESS not set, deployment will fail or use zero address");
        }
        if (nftManagerAddress == address(0)) {
            console.log("Warning: NFT_MANAGER_ADDRESS not set, deployment will fail when setting position manager");
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

        // Ensure NFT manager address exists, use zero address as fallback
        if (nftManagerAddress == address(0)) {
            console.log("WARNING: NFT_MANAGER_ADDRESS not set, using zero address");
        }

        // Step 2: Prepare XH3rmesRewardPool bytecode with constructor arguments
        bytes memory rewardPoolBytecode = abi.encodePacked(
            type(XH3rmesRewardPool).creationCode,
            abi.encode(xh3rmesAddress, poolStartTime, xh3rmesPerSecond, nftManagerAddress, operator)
        );

        // Step 3: Deploy XH3rmesRewardPool using the deployer
        address rewardPoolAddress = h3rmesDeployer.deploy(rewardPoolBytecode, "XH3rmesRewardPool", version);
        rewardPool = XH3rmesRewardPool(rewardPoolAddress);
        console.log("XH3rmesRewardPool deployed at:", rewardPoolAddress);

        // NFT Manager is now set in constructor, no need for separate setting
        console.log("NFT Position Manager set to:", nftManagerAddress);

        // Step 5: Optional - Add initial pools if configured
        if (addInitialPools) {
            addPools();
        }

        // Calculate rewards data for logging
        uint256 dailyRewards = xh3rmesPerSecond * 86400; // Rewards per day
        uint256 startToNow = block.timestamp < poolStartTime ? 0 : (block.timestamp - poolStartTime);

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("H3rmesContractDeployer:", address(h3rmesDeployer));
        console.log("XH3rmesRewardPool:", rewardPoolAddress);
        console.log("XH3rmes Token:", xh3rmesAddress);
        console.log("NFT Position Manager:", nftManagerAddress);
        console.log("Admin:", admin);
        console.log("Version:", version);
        console.log("Pool Start Time:", poolStartTime);
        console.log("Current Time:", block.timestamp);
        console.log("Time Until Start:", block.timestamp < poolStartTime ? poolStartTime - block.timestamp : 0);
        console.log("Time Since Start:", startToNow);
        console.log("XH3rmes Per Second:", xh3rmesPerSecond / 1e18);
        console.log("Daily Rewards:", dailyRewards / 1e18);
        console.log("Initial Pools Added:", addInitialPools);
        console.log("========================\n");

        vm.stopBroadcast();
    }

    /**
     * @notice Private function to add initial liquidity pools
     * @dev Configure pools in the .env file with comma-separated values
     */
    function addPools() private {
        // Get pool addresses from environment
        string memory poolAddressesStr = vm.envOr("POOL_ADDRESSES", string(""));
        string memory poolTypesStr = vm.envOr("POOL_TYPES", string(""));
        string memory allocPointsStr = vm.envOr("ALLOC_POINTS", string(""));

        // Skip if no pools configured
        if (bytes(poolAddressesStr).length == 0) {
            console.log("No initial pools configured");
            return;
        }

        // Parse pool addresses
        string[] memory poolAddressesArray = splitString(poolAddressesStr, ",");
        string[] memory poolTypesArray = splitString(poolTypesStr, ",");
        string[] memory allocPointsArray = splitString(allocPointsStr, ",");

        // Validate arrays
        require(
            poolAddressesArray.length == poolTypesArray.length && poolTypesArray.length == allocPointsArray.length,
            "Array lengths mismatch"
        );

        console.log("Adding", poolAddressesArray.length, "initial pools");

        // Add each pool
        for (uint256 i = 0; i < poolAddressesArray.length; i++) {
            address poolAddress = 0x85c72DC1DD9b297Bb67BAfA09521E9D3F80703f1;
            uint256 allocPoint = parseUint(allocPointsArray[i]);
            XH3rmesRewardPool.PoolType poolType = keccak256(abi.encodePacked(poolTypesArray[i]))
                == keccak256(abi.encodePacked("0"))
                ? XH3rmesRewardPool.PoolType.FullRange
                : XH3rmesRewardPool.PoolType.SingleSided;

            // Add the pool
            rewardPool.add(
                poolType,
                allocPoint,
                IAlgebraPool(poolAddress),
                true, // Update all pools
                poolStartTime // Use the same start time
            );

            console.log("Added pool:", poolAddress);
            console.log("  Type:", uint256(poolType));
            console.log("  Allocation Points:", allocPoint);
        }

        console.log("Total allocation points:", rewardPool.totalAllocPoint());
    }

    /**
     * @notice Helper to split a string by delimiter
     */
    function splitString(string memory _str, string memory _delimiter) private pure returns (string[] memory) {
        // Count delimiters to determine array size
        uint256 count = 1;
        for (uint256 i = 0; i < bytes(_str).length; i++) {
            if (keccak256(abi.encodePacked(bytes(_str)[i])) == keccak256(abi.encodePacked(bytes(_delimiter)[0]))) {
                count++;
            }
        }

        // Split the string
        string[] memory parts = new string[](count);
        uint256 partIndex = 0;
        string memory part;

        for (uint256 i = 0; i < bytes(_str).length; i++) {
            if (keccak256(abi.encodePacked(bytes(_str)[i])) == keccak256(abi.encodePacked(bytes(_delimiter)[0]))) {
                parts[partIndex] = part;
                part = "";
                partIndex++;
            } else {
                part = string(abi.encodePacked(part, bytes(_str)[i]));
            }
        }

        // Add the last part
        if (bytes(part).length > 0) {
            parts[partIndex] = part;
        }

        return parts;
    }

    /**
     * @notice Helper to parse address from string
     */
    function parseAddress(string memory _addressString) private pure returns (address) {
        return address(uint160(parseUint(_addressString)));
    }

    /**
     * @notice Helper to parse uint from string
     */
    function parseUint(string memory _uintString) private pure returns (uint256) {
        bytes memory b = bytes(_uintString);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }
        return result;
    }
}
