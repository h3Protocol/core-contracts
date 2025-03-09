// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract XH3rmes is ERC20Burnable, AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");

    uint256 public constant REWARD_POOL_ALLOCATION = 60000 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 10000 ether;

    bool public rewardsDistributed = false;

    uint256 public constant VESTING_DURATION = 730 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public devFundRewardRate;
    address public devFund;
    uint256 public devFundLastClaimed;

    constructor(uint256 _startTime, address _devFund, address _operator) ERC20("XH3rmes", "xH3") {
        _mint(_operator, 10 ether); // mint 10 Gh3rmes for initial pools deployment
        _setupRole(DEFAULT_ADMIN_ROLE, _operator);
        _setupRole(OPERATOR_ROLE, _operator);

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        devFundLastClaimed = startTime;

        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;
    }

    function setExchange(address _address) external onlyRole(OPERATOR_ROLE) {
        _setupRole(EXCHANGE_ROLE, _address);
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _rewardPool) external onlyRole(OPERATOR_ROLE) {
        require(_rewardPool != address(0), "!_rewardPool");
        require(!rewardsDistributed, "only can distribute once");
        rewardsDistributed = true;
        _mint(_rewardPool, REWARD_POOL_ALLOCATION);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function credit(address to, uint256 amount) public onlyRole(EXCHANGE_ROLE) {
        _mint(to, amount);
    }

    function debit(address account, uint256 amount) external onlyRole(EXCHANGE_ROLE) {
        _burn(account, amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to)
        external
        onlyRole(OPERATOR_ROLE)
    {
        _token.safeTransfer(_to, _amount);
    }
}
