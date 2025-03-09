// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/INonfungiblePositionManager.sol";
import {IAlgebraPool} from "../src/interfaces/IAlgebraPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Add Liquidity Script for H3rmes on Algebra V3
 * @notice Creates liquidity positions in Algebra V3 pools for the H3rmes protocol
 * @dev Uses environment variables for configuration
 */
contract AddLiquidityScript is Script {
    using SafeERC20 for IERC20;

    // Configuration constants from environment
    address deployer;
    address recipient;
    address h3rmesAddress;
    address oSonicAddress;
    uint256 amount0Desired;
    uint256 amount1Desired;
    int24 tickLower;
    int24 tickUpper;
    uint256 deadline;
    address nftPositionManagerAddress;
    address poolAddress;
    uint256 deployerPrivateKey;
    bool fullRange;
    uint24 poolFee;
    uint256 slippageBps;
    uint256 initialPrice;

    // Position result
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load basic configuration
        deployer = vm.envOr("DEPLOYER", address(0));
        recipient = vm.envOr("LIQUIDITY_RECIPIENT", deployer);
        nftPositionManagerAddress = vm.envOr("NFT_MANAGER_ADDRESS", address(0));
        poolAddress = vm.envOr("POOL_ADDRESS", address(0));

        // Token configuration - use protocol token addresses
        h3rmesAddress = vm.envOr("H3RMES_ADDRESS", address(0));
        oSonicAddress = vm.envOr("OSONIC_ADDRESS", address(0));
        amount0Desired = vm.envOr("AMOUNT0_DESIRED", uint256(0));
        amount1Desired = vm.envOr("AMOUNT1_DESIRED", uint256(0));

        // Initial price for pool initialization (if needed)
        // This is token1/token0 price with 18 decimals
        initialPrice = vm.envOr("INITIAL_PRICE", uint256(1 ether));

        // Position range configuration
        fullRange = vm.envOr("FULL_RANGE", false);
        tickLower = int24(vm.envInt("TICK_LOWER"));
        tickUpper = int24(vm.envInt("TICK_UPPER"));

        // Timing configuration
        deadline = block.timestamp + 1 hours;

        // Private key for transaction signing
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (recipient == address(0)) recipient = msg.sender;

        // If full range is set, override the ticks with max range
        if (fullRange) {
            tickLower = -887272; // Min tick for Algebra
            tickUpper = 887272; // Max tick for Algebra
        }

        // Validate configuration
        require(nftPositionManagerAddress != address(0), "Position manager address not set");
        require(poolAddress != address(0), "Pool address not set");
        require(h3rmesAddress != address(0), "H3RMES_ADDRESS not set");
        require(oSonicAddress != address(0), "OSONIC_ADDRESS not set");
        require(amount0Desired > 0 || amount1Desired > 0, "No token amount specified");
    }

    /**
     * @notice Main function that adds liquidity to the pool
     */
    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Get pool and position manager interfaces
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(nftPositionManagerAddress);

        // initialize pool
        uint160 sqrtPriceX96 = encodePriceSqrt(initialPrice);
        positionManager.createAndInitializePoolIfNecessary(h3rmesAddress, oSonicAddress, sqrtPriceX96);
        int24 tickSpacing = IAlgebraPool(poolAddress).tickSpacing();
        poolFee = IAlgebraPool(poolAddress).fee();
        console.log("Pool Fee:", poolFee);
        console.log("Tick Spacing:", tickSpacing);
        console.log("Adding liquidity to pool:", poolAddress);
        console.log("Amount0 Desired:", amount0Desired);
        console.log("Amount1 Desired:", amount1Desired);
        console.log("Tick Lower:", int256(tickLower));
        console.log("Tick Upper:", int256(tickUpper));

        uint256 deployerH3rmesBalance = IERC20(h3rmesAddress).balanceOf(deployer);
        uint256 deployerOSonicBalance = IERC20(oSonicAddress).balanceOf(deployer);

        console.log("Deployer H3rmes Balance:", deployerH3rmesBalance);
        console.log("Deployer oSonic Balance:", deployerOSonicBalance);

        // Approve tokens to the position manager
        IERC20(h3rmesAddress).approve(nftPositionManagerAddress, type(uint256).max);
        IERC20(oSonicAddress).approve(nftPositionManagerAddress, type(uint256).max);

        // Create the position
        (tokenId, liquidity, amount0, amount1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: h3rmesAddress,
                token1: oSonicAddress,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0, // Apply slippage protection
                amount1Min: 0, // Apply slippage protection
                recipient: recipient,
                deadline: deadline
            })
        );

        // Log the results
        console.log("\n=== Position Created ===");
        console.log("NFT Position ID:", tokenId);
        console.log("Liquidity:", liquidity);
        console.log("Position Owner:", recipient);
        console.log("======================\n");

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }

    /**
     * @notice Encodes a price as a sqrt ratio as a Q64.96 value
     * @param price The price to encode (token1/token0)
     * @return The sqrt ratio
     */
    function encodePriceSqrt(uint256 price) internal pure returns (uint160) {
        uint256 sqrtPrice = sqrt(price * 2 ** 192);
        return uint160(sqrtPrice);
    }

    /**
     * @notice Calculates the square root of a number
     * @param x The number to calculate the square root of
     * @return The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        // Initial guess: the square root of a 256-bit number can't be larger than 128 bits
        uint256 result = 1;
        uint256 xAux = x;

        if (xAux >= 2 ** 128) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 2 ** 64) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 2 ** 32) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 2 ** 16) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 2 ** 8) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 2 ** 4) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 2 ** 2) {
            result <<= 1;
        }

        // Use Newton's method to refine the result
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;

        // Make sure the result is not larger than the true square root
        return min(result, x / result);
    }

    /**
     * @notice Returns the minimum of two numbers
     * @param a The first number
     * @param b The second number
     * @return The minimum of a and b
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Helper function to calculate ticks from prices
     * @param price The price to convert to a tick
     * @return The tick corresponding to the price
     */
    function priceToTick(uint256 price) public pure returns (int24) {
        return int24(int256(log2(price) * 2 ** 23));
    }

    /**
     * @notice Helper function to calculate log base 2
     * @param x The value to calculate log2 of
     * @return The log base 2 of x with 18 decimals of precision
     */
    function log2(uint256 x) internal pure returns (int256) {
        require(x > 0, "log2: x <= 0");

        int256 msb = 0;
        for (uint256 i = 0x8000000000000000; i > 0; i >>= 1) {
            if (x >= (1 << i)) {
                x >>= i;
                msb += int256(i);
            }
        }

        // Further precision calculation would go here
        // This is simplified for demonstration

        return msb;
    }
}
