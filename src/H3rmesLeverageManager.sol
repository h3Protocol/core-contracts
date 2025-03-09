// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {H3rmes} from "./H3rmes.sol";

// WIP
/**
 * @title H3rmesLeverageManager
 * @notice Handles recursive leverage positions on the H3rmes protocol
 * @dev Must be granted LEVERAGE_Manager_ROLE on H3rmes contract
 */
contract H3rmesLeverageManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for ERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    H3rmes public immutable h3rmes;
    ERC20 public immutable oSonic;

    // Configurable parameters
    uint256 public maxLoops = 5;
    uint256 public minCollateralAmount = 0.01 ether;

    event LoopedLeverageCreated(
        address indexed user, uint256 initialCollateral, uint256 totalBorrowed, uint256 loops, uint256 duration
    );

    /**
     * @param _h3rmes Address of the H3rmes contract
     * @param _operator Address of the operator
     */
    constructor(address _h3rmes, address _operator) {
        h3rmes = H3rmes(_h3rmes);
        oSonic = ERC20(h3rmes.oSonic());

        oSonic.approve(_h3rmes, type(uint256).max);

        _setupRole(DEFAULT_ADMIN_ROLE, _operator);
        _setupRole(OPERATOR_ROLE, _operator);
    }

    /**
     * @notice Creates a looped leverage position
     * @param initialCollateral Initial oSonic collateral amount
     * @param loops Number of borrowing loops to perform
     * @param leverage Leverage factor per loop (percentage, e.g. 150 = 1.5x)
     * @param numberOfDays Loan duration in days
     */
    function createLoopedLeverage(uint256 initialCollateral, uint256 loops, uint256 leverage, uint256 numberOfDays)
        external
        nonReentrant
    {
        require(initialCollateral >= minCollateralAmount, "Collateral below minimum");
        require(loops > 0 && loops <= maxLoops, "Invalid loop count");
        require(leverage > 100 && leverage <= 200, "Leverage must be between 1x and 2x");
        require(numberOfDays > 0 && numberOfDays <= 365, "Duration must be between 1 and 365 days");

        oSonic.safeTransferFrom(msg.sender, address(this), initialCollateral);
        uint256 returnedSonic = h3rmes.borrowFor(msg.sender, initialCollateral, numberOfDays, 0);
        // WIP: Implement looped leverage
    }

    /**
     * @notice Configure loop parameters
     * @param _maxLoops Maximum number of loops allowed
     * @param _minCollateralAmount Minimum collateral amount
     */
    function configureParameters(uint256 _maxLoops, uint256 _minCollateralAmount) external onlyRole(OPERATOR_ROLE) {
        require(_maxLoops > 0 && _maxLoops <= 10, "Invalid max loops");
        maxLoops = _maxLoops;
        minCollateralAmount = _minCollateralAmount;
    }

    /**
     * @notice Emergency function to rescue tokens
     * @param token Address of token to rescue
     * @param to Address to send tokens to
     * @param amount Amount to rescue
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        ERC20(token).safeTransfer(to, amount);
    }
}
