// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {H3rmes} from "../src/H3rmes.sol";
import {XH3rmes} from "../src/XH3rmes.sol";
import {XH3rmesRewardPool} from "../src/XH3rmesRewardPool.sol";
import {DeployH3rmesScript} from "./DeployH3rmes.s.sol";
import {DeployXH3rmesScript} from "./DeployXH3rmes.s.sol";
import {DeployXH3rmesRewardPoolScript} from "./DeployXH3rmesRewardPool.s.sol";
import {DeployH3rmesExchangeScript} from "./DeployH3rmesExchange.s.sol";
import {DeployNativePositionManagerScript} from "./DeployNativePositionManager.s.sol";
import {AddLiquidityScript} from "./AddLiquidity.s.sol";

contract DeployFullProtocolScript is Script {
    function setUp() public {}

    function run() public {
        // Deploy H3rmes
        DeployH3rmesScript deployH3rmesScript = new DeployH3rmesScript();
        deployH3rmesScript.setUp();
        deployH3rmesScript.run();

        // Deploy XH3rmes
        DeployXH3rmesScript deployXH3rmesScript = new DeployXH3rmesScript();
        deployXH3rmesScript.setUp();
        deployXH3rmesScript.run();

        // Deploy XH3rmesRewardPool
        DeployXH3rmesRewardPoolScript deployXH3rmesRewardPoolScript = new DeployXH3rmesRewardPoolScript();
        deployXH3rmesRewardPoolScript.setUp();
        deployXH3rmesRewardPoolScript.run();

        // Deploy H3rmesExchange
        DeployH3rmesExchangeScript deployH3rmesExchangeScript = new DeployH3rmesExchangeScript();
        deployH3rmesExchangeScript.setUp();
        deployH3rmesExchangeScript.run();

        // Deploy NativePositionManager
        DeployNativePositionManagerScript deployNativePositionManagerScript = new DeployNativePositionManagerScript();
        deployNativePositionManagerScript.setUp();
        deployNativePositionManagerScript.run();

        // Add liquidity to H3rmes pool
        AddLiquidityScript addLiquidityScript = new AddLiquidityScript();
        addLiquidityScript.setUp();
        addLiquidityScript.run();
    }
}
