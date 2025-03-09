// filepath: /home/oxgab/h3rmes-finance-contracts/src/H3rmesExchange.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {H3rmes} from "./H3rmes.sol";
import {XH3rmes} from "./XH3rmes.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract H3rmesExchange is Owned, Pausable, ReentrancyGuard {
    H3rmes public h3rmes;
    XH3rmes public xH3rmes;

    uint256 public pendingForfeits;

    uint256 public constant BASIS = 10_000;

    struct VestPosition {
        uint256 amount;
        uint256 start;
        uint256 maxEnd;
        uint256 vestID;
    }

    struct ExchangeConfig {
        uint256 slashingPenalty;
        uint256 minVest;
        uint256 maxVest;
    }

    ExchangeConfig public exchangeConfig;

    mapping(address => VestPosition[]) public vestInfo;

    event H3rmesDeposited(address indexed user, uint256 amount);
    event H3rmesWithdrawn(address indexed user, uint256 amount, uint256 penalty);
    event PenaltyRateUpdated(uint256 oldRate, uint256 newRate);
    event NewVest(address indexed user, uint256 vestID, uint256 amount);
    event ExitVesting(address indexed user, uint256 vestID, uint256 amount);
    event CancelVesting(address indexed user, uint256 vestID, uint256 amount);

    error ZERO();
    error NO_VEST();

    constructor(address _h3rmes, address _xH3rmes, address _owner, ExchangeConfig memory _exchangeConfig)
        Owned(_owner)
    {
        h3rmes = H3rmes(payable(_h3rmes));
        xH3rmes = XH3rmes(_xH3rmes);
        exchangeConfig = _exchangeConfig;
    }

    function depositH3rmes(uint256 amount) external whenNotPaused {
        h3rmes.debit(msg.sender, amount);
        xH3rmes.credit(msg.sender, amount); // 1:1 mint
    }

    function createVest(uint256 _amount) external whenNotPaused {
        /// @dev ensure not 0
        require(_amount != 0, ZERO());
        /// @dev preemptive burn
        xH3rmes.debit(msg.sender, _amount);
        /// @dev fetch total length of vests
        uint256 vestLength = vestInfo[msg.sender].length;
        /// @dev push new position
        vestInfo[msg.sender].push(
            VestPosition(_amount, block.timestamp, block.timestamp + exchangeConfig.maxVest, vestLength)
        );
        emit NewVest(msg.sender, vestLength, _amount);
    }

    function exitVest(uint256 _vestID) external whenNotPaused {
        VestPosition storage _vest = vestInfo[msg.sender][_vestID];
        require(_vest.amount != 0, NO_VEST());

        /// @dev store amount in the vest and start time
        uint256 _amount = _vest.amount;
        uint256 _start = _vest.start;
        /// @dev zero out the amount before anything else as a safety measure
        _vest.amount = 0;

        /// @dev case: vest has not crossed the minimum vesting threshold
        /// @dev mint cancelled xShadow back to msg.sender
        if (block.timestamp < _start + exchangeConfig.minVest) {
            xH3rmes.credit(msg.sender, _amount);
            emit CancelVesting(msg.sender, _vestID, _amount);
        }
        /// @dev case: vest is complete
        /// @dev send liquid Shadow to msg.sender
        else if (_vest.maxEnd <= block.timestamp) {
            h3rmes.credit(msg.sender, _amount);
            emit ExitVesting(msg.sender, _vestID, _amount);
        }
        /// @dev case: vest is in progress
        /// @dev calculate % earned based on length of time that has vested
        /// @dev linear calculations
        else {
            /// @dev the base to start at (50%)
            uint256 base = (_amount * (exchangeConfig.slashingPenalty)) / BASIS;
            /// @dev calculate the extra earned via vesting
            uint256 vestEarned = (
                (_amount * (BASIS - exchangeConfig.slashingPenalty) * (block.timestamp - _start))
                    / exchangeConfig.maxVest
            ) / BASIS;

            uint256 exitedAmount = base + vestEarned;
            /// @dev add to the existing pendingForfeits
            pendingForfeits += (_amount - exitedAmount);
            /// @dev transfer underlying to the sender after penalties removed
            h3rmes.credit(msg.sender, exitedAmount);
            emit ExitVesting(msg.sender, _vestID, _amount);
        }
    }
}
