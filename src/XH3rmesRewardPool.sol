// SPDX-License-Identifier: BUSL-1.1

// XH3rmesRewardPool --> visit https://h3rmes.finance/ for full experience
// Made by Kell

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IAlgebraPool} from "./interfaces/IAlgebraPool.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {XH3rmes} from "./XH3rmes.sol";

/**
 * @title XH3rmesRewardPool
 * @notice Contract for managing liquidity positions and distributing XH3rmes rewards
 * @dev Handles fractionalizing NFT positions and calculating rewards based on allocation points
 */
contract XH3rmesRewardPool is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    enum PoolType {
        FullRange,
        SingleSided
    }

    struct UniquePosition {
        uint256 tokenId;
        uint256 fractionalizedAmount;
    }

    struct UserInfo {
        UniquePosition[] positions;
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        PoolType poolType;
        IAlgebraPool token;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accXH3rmesPerShare;
        bool isStarted;
        uint256 fractionalizedBalance;
    }

    struct UIUserInfo {
        UniquePosition[] positions;
        uint256 amount;
        uint256 rewardDebt;
        uint256 pending;
    }

    XH3rmes public xH3rmes;
    INonfungiblePositionManager public nftManager;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint = 0;
    uint256 public poolStartTime;
    uint256 public xh3rmesPerSecond;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event XH3rmesPerSecondUpdated(uint256 oldRate, uint256 newRate);

    error OutOfRange(uint256 _tokenId);
    error InvalidToken(uint256 _tokenId);
    error InvalidPool(uint256 _pid);

    /**
     * @notice Initializes the XH3rmesRewardPool contract
     * @param _xH3rmes Address of the XH3rmes token contract
     * @param _poolStartTime Timestamp when reward distribution starts
     * @param _xh3rmesPerSecond Rate of XH3rmes distribution per second
     * @param _nftManager Address of the Nonfungible Position Manager
     * @param _operator Address that will receive admin permissions
     */
    constructor(
        address _xH3rmes,
        uint256 _poolStartTime,
        uint256 _xh3rmesPerSecond,
        address _nftManager,
        address _operator
    ) {
        require(block.timestamp < _poolStartTime, "late");
        if (_xH3rmes != address(0)) xH3rmes = XH3rmes(_xH3rmes);
        poolStartTime = _poolStartTime;
        xh3rmesPerSecond = _xh3rmesPerSecond;
        nftManager = INonfungiblePositionManager(_nftManager);
        _grantRole(DEFAULT_ADMIN_ROLE, _operator);
        _grantRole(POOL_MANAGER_ROLE, _operator);
    }

    /**
     * @notice Checks if a pool with the same token and type already exists
     * @param _token The token address to check
     * @param _poolType The type of pool to check (FullRange or SingleSided)
     * @dev Reverts if duplicate pool exists
     */
    function checkPoolDuplicate(IAlgebraPool _token, PoolType _poolType) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (address(poolInfo[pid].token) == address(_token)) {
                if (poolInfo[pid].poolType == _poolType) {
                    revert InvalidPool(pid);
                }
            }
        }
    }

    /**
     * @notice Adds a new liquidity pool to the system
     * @param _poolType The type of the pool (FullRange or SingleSided)
     * @param _allocPoint Allocation points assigned to this pool
     * @param _token Address of the Algebra pool
     * @param _withUpdate Whether to update all pools before adding
     * @param _lastRewardTime Last time rewards were calculated for this pool
     * @dev Can only be called by accounts with POOL_MANAGER_ROLE
     */
    function add(
        PoolType _poolType,
        uint256 _allocPoint,
        IAlgebraPool _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyRole(POOL_MANAGER_ROLE) {
        checkPoolDuplicate(_token, _poolType);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
                poolType: _poolType,
                token: _token,
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accXH3rmesPerShare: 0,
                isStarted: _isStarted,
                fractionalizedBalance: 0
            })
        );
        if (_isStarted) {
            totalAllocPoint += _allocPoint;
        }
    }

    /**
     * @notice Updates the allocation points for a specific pool
     * @param _pid Pool ID to update
     * @param _allocPoint New allocation points for the pool
     * @dev Can only be called by accounts with POOL_MANAGER_ROLE
     */
    function set(uint256 _pid, uint256 _allocPoint) public onlyRole(POOL_MANAGER_ROLE) {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint - pool.allocPoint + _allocPoint;
        }
        pool.allocPoint = _allocPoint;
    }

    /**
     * @notice Deposits an NFT position into the specified pool
     * @param _pid Pool ID to deposit into
     * @param _tokenId TokenId of the NFT position to deposit
     * @dev Transfers the NFT to this contract and updates rewards
     */
    function deposit(uint256 _pid, uint256 _tokenId) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = (user.amount * pool.accXH3rmesPerShare) / 1e18 - user.rewardDebt;
            if (_pending > 0) {
                safeXH3rmestokenTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        uint256 _amount;
        if (pool.poolType == PoolType.FullRange) {
            _amount = fractionalizeFullRange(_pid, _tokenId);
        } else {
            _amount = fractionalizeSingleSided(_pid, _tokenId);
        }
        if (_amount > 0) {
            nftManager.safeTransferFrom(_sender, address(this), _tokenId, bytes(""));
            user.positions.push(UniquePosition({tokenId: _tokenId, fractionalizedAmount: _amount}));
            user.amount += _amount;
            pool.fractionalizedBalance += _amount;
        }
        user.rewardDebt = (user.amount * pool.accXH3rmesPerShare) / 1e18;
        emit Deposit(_sender, _pid, _amount);
    }

    /**
     * @notice Allows a user to withdraw a specific position from a pool
     * @param _pid Pool ID from which to withdraw
     * @param _amount TokenId of the NFT to withdraw
     * @dev Transfers the NFT back to the user and updates rewards
     */
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        _withdraw(_pid, _amount, msg.sender);
    }

    /**
     * @notice Internal function to handle position withdrawals
     * @param _pid Pool ID from which to withdraw
     * @param _tokenId TokenId of the NFT to withdraw
     * @param _sender Address of the user making the withdrawal
     * @dev Handles reward distribution and NFT transfer
     */
    function _withdraw(uint256 _pid, uint256 _tokenId, address _sender) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        uint256 _tokenIdIndex = findTokenId(user.positions, _tokenId);
        if (_tokenIdIndex == type(uint256).max) revert InvalidToken(_tokenId);
        updatePool(_pid);
        uint256 _pending = (user.amount * pool.accXH3rmesPerShare) / 1e18 - user.rewardDebt;
        if (_pending > 0) {
            safeXH3rmestokenTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        uint256 _amount = user.positions[_tokenIdIndex].fractionalizedAmount;
        if (_amount > 0) {
            user.amount -= _amount;
            nftManager.safeTransferFrom(address(this), _sender, _tokenId, bytes(""));
        }
        user.rewardDebt = (user.amount * pool.accXH3rmesPerShare) / 1e18;
        emit Withdraw(_sender, _pid, _amount);
    }

    /**
     * @notice Claims all pending rewards across all pools for the caller
     * @dev Iterates through pools and calls _withdraw for each
     */
    function claimAll() external nonReentrant {
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            UserInfo storage user = userInfo[pid][msg.sender];
            if (user.amount > 0) {
                _withdraw(pid, 0, msg.sender);
            }
        }
    }
    
    /**
     * @notice Safely transfers XH3rmes tokens to the specified recipient
     * @param _to Address receiving the tokens
     * @param _amount Amount of tokens to transfer
     * @dev Uses SafeERC20 to handle the transfer
     */
    function safeXH3rmestokenTransfer(address _to, uint256 _amount) internal {
        SafeERC20.safeTransfer(xH3rmes, _to, _amount);
    }

    /**
     * @notice Calculates the reward amount generated between two timestamps
     * @param _fromTime Start timestamp
     * @param _toTime End timestamp
     * @return Amount of XH3rmes tokens generated in the time period
     * @dev Returns 0 if _fromTime >= _toTime or if both are before poolStartTime
     */
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime <= poolStartTime) return 0;
        if (_fromTime <= poolStartTime) {
            return (_toTime - poolStartTime) * xh3rmesPerSecond;
        }
        return (_toTime - _fromTime) * xh3rmesPerSecond;
    }

    /**
     * @notice Returns the amount of XH3rmes tokens pending for a user in a pool
     * @param _pid Pool ID to check
     * @param _user User address to check
     * @return Pending reward amount
     * @dev Calculates rewards based on user's share and time elapsed
     */
    function pendingShare(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accXH3rmesPerShare = pool.accXH3rmesPerShare;
        uint256 tokenSupply = pool.fractionalizedBalance; // pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _xH3rmesReward = (_generatedReward * pool.allocPoint) / totalAllocPoint;
            accXH3rmesPerShare = accXH3rmesPerShare + (_xH3rmesReward * 1e18) / tokenSupply;
        }
        return (user.amount * accXH3rmesPerShare) / 1e18 - user.rewardDebt;
    }

    /**
     * @notice Returns the total pending rewards for a user across all pools
     * @param _user Address of the user
     * @return totalPending Total pending rewards across all pools
     * @dev Iterates through all pools and sums the pending rewards
     */
    function pendingAll(address _user) external view returns (uint256 totalPending) {
        totalPending = 0;
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_user];
            uint256 accXH3rmesPerShare = pool.accXH3rmesPerShare;
            uint256 tokenSupply = pool.fractionalizedBalance; // pool.token.balanceOf(address(this));
            if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
                uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
                uint256 _xH3rmesReward = (_generatedReward * pool.allocPoint) / totalAllocPoint;
                accXH3rmesPerShare = accXH3rmesPerShare + (_xH3rmesReward * 1e18) / tokenSupply;
            }
            uint256 pending = (user.amount * accXH3rmesPerShare) / 1e18 - user.rewardDebt;
            totalPending += pending;
        }
    }

    /**
     * @notice Updates all pools by calling updatePool for each
     * @dev Used to ensure all pools have current reward calculations
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @notice Updates reward variables for a specific pool
     * @param _pid Pool ID to update
     * @dev Calculates and updates the accumulated rewards per share
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.fractionalizedBalance;
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint += pool.allocPoint;
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _xH3rmesReward = (_generatedReward * pool.allocPoint) / totalAllocPoint;
            pool.accXH3rmesPerShare += (_xH3rmesReward * 1e18) / tokenSupply;
        }
        pool.lastRewardTime = block.timestamp;
    }

    /**
     * @notice Updates the XH3rmes tokens distributed per second
     * @param _xh3rmesPerSecond New rate of tokens per second
     * @dev Can only be called by accounts with POOL_MANAGER_ROLE
     */
    function setXH3rmesPerSecond(uint256 _xh3rmesPerSecond) external onlyRole(POOL_MANAGER_ROLE) {
        require(_xh3rmesPerSecond > 0, "setXH3rmesPerSecond: value must be greater than 0");
        emit XH3rmesPerSecondUpdated(xh3rmesPerSecond, _xh3rmesPerSecond);
        xh3rmesPerSecond = _xh3rmesPerSecond;
    }

    /**
     * @notice Calculates the fractionalized amount for a full-range position
     * @param _pid Pool ID for which the position is being fractionalized
     * @param _tokenId NFT token ID to fractionalize
     * @return The fractionalized liquidity amount
     * @dev Reverts if position is not valid for the pool or not full-range
     */
    function fractionalizeFullRange(uint256 _pid, uint256 _tokenId) internal view returns (uint256) {
        (,, address token0, address token1, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            nftManager.positions(_tokenId);
        if (token0 != address(poolInfo[_pid].token) && token1 != address(poolInfo[_pid].token)) {
            revert InvalidToken(_tokenId);
        }
        if (liquidity == 0) revert InvalidToken(_tokenId);
        if (tickLower != -887272 || tickUpper != 887272) {
            revert OutOfRange(_tokenId);
        }
        return liquidity;
    }

    /**
     * @notice Calculates the fractionalized amount for a single-sided position
     * @param _pid Pool ID for which the position is being fractionalized
     * @param _tokenId NFT token ID to fractionalize
     * @return The fractionalized liquidity amount based on position characteristics
     * @dev Applies a weighting factor based on the tick distance from current price
     */
    function fractionalizeSingleSided(uint256 _pid, uint256 _tokenId) internal view returns (uint256) {
        (,, address token0, address token1, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            nftManager.positions(_tokenId);
        if (liquidity == 0) revert InvalidToken(_tokenId);
        if (token0 != address(poolInfo[_pid].token) && token1 != address(poolInfo[_pid].token)) {
            revert InvalidToken(_tokenId);
        }
        PoolInfo storage pool = poolInfo[_pid];
        (, int24 tick,,,,) = pool.token.globalState();
        if (tickUpper > tick || tickLower > tick) revert OutOfRange(_tokenId);
        uint256 diff = uint256(int256(tick - tickLower));
        if (diff > 5000) revert OutOfRange(_tokenId); // -5000 is the max tick difference (-5000 = 1.0001^-5000 = 60.654%)
        uint256 factor = uint256(1e14 / (1e7 + (diff ** 2)));
        return (liquidity * factor) / 1e7;
    }

    /**
     * @notice Finds the index of a specific token ID in a user's positions array
     * @param _positions Array of UniquePosition structs to search
     * @param _tokenId Token ID to find
     * @return Index of the token in the array, or max uint256 if not found
     */
    function findTokenId(UniquePosition[] storage _positions, uint256 _tokenId) internal view returns (uint256) {
        for (uint256 i = 0; i < _positions.length; i++) {
            if (_positions[i].tokenId == _tokenId) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @notice Returns detailed user information for a specific pool
     * @param _pid Pool ID to query
     * @param _user Address of the user
     * @return User information including positions, amounts, and pending rewards
     * @dev Formats data for UI presentation
     */
    function getUserView(uint256 _pid, address _user) public view returns (UIUserInfo memory) {
        UserInfo storage user = userInfo[_pid][_user];
        UniquePosition[] memory positions = user.positions;
        uint256 pending = pendingShare(_pid, _user);
        return UIUserInfo({positions: positions, amount: user.amount, rewardDebt: user.rewardDebt, pending: pending});
    }

    /**
     * @notice Returns detailed user information across all pools
     * @param _user Address of the user
     * @return Array of UIUserInfo structs, one for each pool
     * @dev Used for frontend display of user positions and rewards
     */
    function getUserViews(address _user) public view returns (UIUserInfo[] memory) {
        uint256 length = poolInfo.length;
        UIUserInfo[] memory userInfos = new UIUserInfo[](length);
        for (uint256 pid = 0; pid < length; pid++) {
            userInfos[pid] = getUserView(pid, _user);
        }
        return userInfos;
    }

    /**
     * @notice Returns information about all pools in the system
     * @return Array of PoolInfo structs containing pool details
     * @dev Used for frontend display of all available pools
     */
    function getPools() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }
}