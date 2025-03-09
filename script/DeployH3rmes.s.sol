// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {H3rmes} from "../src/H3rmes.sol";
import {H3rmesContractDeployer} from "../src/H3rmesContractDeployer.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {H3rmesHelper} from "../src/H3rmesHelper.sol";

/**
 * @title Deploy H3rmes Script
 * @notice Deploys H3rmes contracts and initializes them
 * @dev Uses environment variables for configuration
 */
contract DeployH3rmesScript is Script {
    // Config Constants from environment
    address deployer;
    address admin;
    address operator;
    address feeAddress;
    address oSonicAddress;
    address oSonicZapperAddress;
    uint256 deployerPrivateKey;
    uint256 operatorPrivateKey;
    bool useExistingDeployer;
    address existingDeployerAddress;
    string version;

    // Deployed contracts
    H3rmesContractDeployer public h3rmesDeployer;
    H3rmes public h3rmes;

    /**
     * @notice Sets up configuration from environment variables
     */
    function setUp() public {
        // Load config from environment
        deployer = vm.envOr("DEPLOYER", address(0));
        admin = vm.envOr("ADMIN", address(0));
        operator = vm.envOr("OPERATOR", address(0));
        feeAddress = vm.envOr("FEE_ADDRESS", address(0));
        oSonicAddress = vm.envOr("OSONIC_ADDRESS", address(0xb1e25689D55734FD3ffFc939c4C3Eb52DFf8A794));
        oSonicZapperAddress = vm.envOr("OSONIC_ZAPPER_ADDRESS", address(0xe25A2B256ffb3AD73678d5e80DE8d2F6022fAb21));

        // Only load private keys if deploying
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            operatorPrivateKey = vm.envUint("OPERATOR_PRIVATE_KEY");
        }

        useExistingDeployer = vm.envOr("USE_EXISTING_DEPLOYER", false);
        existingDeployerAddress = vm.envOr("EXISTING_DEPLOYER_ADDRESS", address(0));
        version = vm.envOr("H3RMES_VERSION", string("v1.0"));

        // Validate required addresses
        require(oSonicAddress != address(0), "OSONIC_ADDRESS must be set");
        require(oSonicZapperAddress != address(0), "OSONIC_ZAPPER_ADDRESS must be set");

        // If using real deployment, ensure all addresses are set
        if (vm.envOr("DEPLOY_ENABLED", false)) {
            require(deployer != address(0), "DEPLOYER must be set");
            require(admin != address(0), "ADMIN must be set");
            require(operator != address(0), "OPERATOR must be set");
            require(feeAddress != address(0), "FEE_ADDRESS must be set");
        }

        // Use msg.sender as default for local testing
        if (deployer == address(0)) deployer = msg.sender;
        if (admin == address(0)) admin = msg.sender;
        if (operator == address(0)) operator = msg.sender;
        if (feeAddress == address(0)) feeAddress = msg.sender;
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
            h3rmesDeployer = new H3rmesContractDeployer(admin, operator);
            console.log("H3rmesContractDeployer deployed at:", address(h3rmesDeployer));
        }

        // Step 2: Prepare H3rmes bytecode with constructor arguments
        bytes memory h3rmesBytecode = abi.encodePacked(
            type(H3rmes).creationCode, abi.encode(operator, oSonicAddress, oSonicZapperAddress, feeAddress)
        );

        // Step 3: Deploy H3rmes using the deployer
        address h3rmesAddress = h3rmesDeployer.deploy(h3rmesBytecode, "H3rmes", version);
        h3rmes = H3rmes(payable(h3rmesAddress));
        console.log("H3rmes deployed at:", h3rmesAddress);

        // Get oSonic token
        ERC20 oSonic = ERC20(oSonicAddress);
        uint256 oSonicDecimals = oSonic.decimals();
        uint256 oneOSonic = 10 ** oSonicDecimals;

        // Approve oSonic for H3rmes contract
        oSonic.approve(h3rmesAddress, type(uint256).max);
        console.log("Approved 1 oSonic for H3rmes contract");

        // Initialize H3rmes by starting trading with 1 oSonic
        h3rmes.setStart(oneOSonic);
        console.log("H3rmes trading started with 1 oSonic");

        h3rmes.buyWithNative{value: 1 ether}(deployer);

        // Deploy Helper
        bytes memory h3rmesHelperBytecode =
            abi.encodePacked(type(H3rmesHelper).creationCode, abi.encode(h3rmesAddress));
        address h3rmesHelperAddress = h3rmesDeployer.deploy(h3rmesHelperBytecode, "H3rmesHelper", version);
        console.log("H3rmesHelper deployed at:", h3rmesHelperAddress);

        // Log deployed contract info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("H3rmesContractDeployer:", address(h3rmesDeployer));
        console.log("H3rmes:", h3rmesAddress);
        console.log("oSonic:", oSonicAddress);
        console.log("oSonicZapper:", oSonicZapperAddress);
        console.log("Admin:", admin);
        console.log("Operator:", operator);
        console.log("Fee Address:", feeAddress);
        console.log("Version:", version);
        console.log("Started:", h3rmes.start());
        console.log("========================\n");

        vm.stopBroadcast();
    }
}
