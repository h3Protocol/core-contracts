// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {CREATE3} from "solmate/utils/CREATE3.sol";

/**
 * @title H3rmesContractDeployer
 * @notice Deploys contracts to deterministic addresses using CREATE3
 * @dev Uses AccessControlEnumerable for permission management
 */
contract H3rmesContractDeployer is AccessControlEnumerable {
    /// @notice Role identifier for addresses permitted to deploy contracts
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /**
     * @notice Information about a deployed contract
     * @param name The identifier name of the contract
     * @param version The version string of the contract
     * @param contractAddress The address where the contract was deployed
     */
    struct H3rmesContractDeployment {
        string name;
        string version;
        address contractAddress;
    }

    /// @notice Array storing all contracts deployed through this deployer
    H3rmesContractDeployment[] public h3rmesContractDeployments;

    /**
     * @notice Emitted when a contract is successfully deployed
     * @param name Name identifier of the deployed contract
     * @param version Version identifier of the deployed contract
     * @param contractAddress The address where the contract was deployed
     */
    event ContractDeployed(string name, string version, address indexed contractAddress);

    /**
     * @notice Configures the contract with initial roles
     * @param admin Address that will have admin privileges
     * @param deployer Address that will have deployment privileges
     */
    constructor(address admin, address deployer) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEPLOYER_ROLE, deployer);
    }

    /**
     * @notice Deploys a contract using CREATE3
     * @dev Creates a deterministic address based on name and version
     * @param bytecode The initialization bytecode for the contract
     * @param name Name identifier for the contract
     * @param version Version identifier for the contract
     * @return contractAddress The address where the contract was deployed
     */
    function deploy(bytes memory bytecode, string memory name, string memory version)
        public
        payable
        onlyRole(DEPLOYER_ROLE)
        returns (address contractAddress)
    {
        // Generate salt from name and version
        bytes32 salt = keccak256(abi.encodePacked(name, version));

        contractAddress = CREATE3.deploy(salt, bytecode, msg.value);
        require(contractAddress != address(0), "H3rmesContractDeployer: deployment failed");

        h3rmesContractDeployments.push(
            H3rmesContractDeployment({name: name, version: version, contractAddress: contractAddress})
        );

        emit ContractDeployed(name, version, contractAddress);
    }

    /**
     * @notice Deploys multiple contracts with the same bytecode
     * @dev Batched deployment using different name/version identifiers
     * @param bytecode The initialization bytecode for the contracts
     * @param names Array of name identifiers for each contract
     * @param versions Array of version identifiers for each contract
     * @return contractAddresses Array of addresses where contracts were deployed
     */
    function deployMany(bytes memory bytecode, string[] memory names, string[] memory versions)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address[] memory contractAddresses)
    {
        require(names.length == versions.length, "H3rmesContractDeployer: arrays length mismatch");

        contractAddresses = new address[](names.length);
        for (uint256 i; i < names.length; ++i) {
            contractAddresses[i] = deploy(bytecode, names[i], versions[i]);
        }
    }

    /**
     * @notice Returns the total number of deployed contracts
     * @return The length of the deployments array
     */
    function deployedContractsLength() external view returns (uint256) {
        return h3rmesContractDeployments.length;
    }

    /**
     * @notice Retrieves all deployed contract information
     * @return Array of all contract deployment records
     */
    function getDeployedContracts() external view returns (H3rmesContractDeployment[] memory) {
        return h3rmesContractDeployments;
    }

    /**
     * @notice Computes the address of a contract based on name and version
     * @dev Does not deploy the contract, only computes the address
     * @param name Name identifier for the contract
     * @param version Version identifier for the contract
     * @return The computed address of the contract
     */
    function computeAddress(string memory name, string memory version) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(name, version));
        return CREATE3.getDeployed(salt);
    }

    function execute(address target, bytes memory data) public payable onlyRole(EXECUTOR_ROLE) returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call{value: msg.value}(data);
        require(success, "H3rmesContractDeployer: execution failed");
        return returnData;
    }

    /**
     * @notice Grants or revokes the executor role from an address
     * @param executor Address to grant or revoke the executor role
     */
    function toggleExecutorRole(address executor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(EXECUTOR_ROLE, executor)) {
            revokeRole(EXECUTOR_ROLE, executor);
        } else {
            grantRole(EXECUTOR_ROLE, executor);
        }
    }

    /**
     * @notice Grants or revokes the deployer role from an address
     * @param deployer Address to grant or revoke the deployer role
     */
    function toggleDeployerRole(address deployer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(DEPLOYER_ROLE, deployer)) {
            revokeRole(DEPLOYER_ROLE, deployer);
        } else {
            grantRole(DEPLOYER_ROLE, deployer);
        }
    }
}
