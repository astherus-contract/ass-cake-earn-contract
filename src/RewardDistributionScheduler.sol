// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IRewardDistributionScheduler.sol";
import "./interfaces/IMinter.sol";

contract RewardDistributionScheduler is
  IRewardDistributionScheduler,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  // bot role
  bytes32 public constant BOT = keccak256("BOT");
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");

  /* ============ State Variables ============ */
  // token address
  IERC20 public token;
  address public minter;
  mapping(uint256 => mapping(IMinter.RewardsType => uint256)) public epochs;
  //last time to distribute rewards
  uint256 public lastDistributeRewardsTimestamp;

  /* ============ Events ============ */
  event RewardsScheduleAdded(
    address sender,
    IMinter.RewardsType rewardsType,
    uint256 amount,
    uint256 epochs,
    uint256 startTime
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _token - Address of the token
   * @param _minter - Address of the minter
   * @param _manager - Address of the manager
   */
  function initialize(
    address _admin,
    address _token,
    address _minter,
    address _manager,
    address _pauser
  ) external override initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_token != address(0), "Invalid token address");
    require(_minter != address(0), "Invalid minter address");
    require(_manager != address(0), "Invalid manager address");
    require(_pauser != address(0), "Invalid pauser address");

    __Pausable_init();
    __ReentrancyGuard_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);

    token = IERC20(_token);
    minter = _minter;
    lastDistributeRewardsTimestamp = (block.timestamp / 1 days) * 1 days;
  }

  // /* ============ External Functions ============ */

  /**
   * @dev addRewardsSchedule
   * @param _rewardsType - rewards type
   * @param _amount - rewards amount
   * @param _epochs - rewards epochs eg:7;14
   * @param _startTime - rewards startTime timestamp
   */
  function addRewardsSchedule(
    IMinter.RewardsType _rewardsType,
    uint256 _amount,
    uint256 _epochs,
    uint256 _startTime
  ) external override onlyRole(MANAGER) nonReentrant whenNotPaused {
    require(_amount > 0, "Invalid amount");
    require(_epochs > 0, "Invalid epochs");
    require(_startTime > 0, "Invalid startTime");

    require(
      IMinter.RewardsType.VeTokenRewards == _rewardsType ||
        IMinter.RewardsType.VoteRewards == _rewardsType ||
        IMinter.RewardsType.Donate == _rewardsType,
      "Invalid rewardsType"
    );

    uint256 startTime = (_startTime / 1 days) * 1 days;

    if (startTime < lastDistributeRewardsTimestamp) {
      lastDistributeRewardsTimestamp = startTime;
    }

    token.safeTransferFrom(msg.sender, address(this), _amount);
    uint256 amountPerDay = _amount / _epochs;
    for (uint256 i; i < _epochs; i++) {
      epochs[startTime + i * 1 days][_rewardsType] += amountPerDay;
    }
    emit RewardsScheduleAdded(msg.sender, _rewardsType, _amount, _epochs, startTime);
  }

  /**
   * @dev executeRewardSchedules per day
   */
  function executeRewardSchedules() external override onlyRole(BOT) nonReentrant whenNotPaused {
    uint256 currentTimestamp = (block.timestamp / 1 days) * 1 days;
    uint max = (uint)(type(IMinter.RewardsType).max);

    while (lastDistributeRewardsTimestamp <= currentTimestamp) {
      for (uint j; j < max; j++) {
        if (epochs[lastDistributeRewardsTimestamp][IMinter.RewardsType(j)] != 0) {
          uint256 amount = epochs[lastDistributeRewardsTimestamp][IMinter.RewardsType(j)];
          IERC20(token).safeIncreaseAllowance(minter, amount);

          delete epochs[lastDistributeRewardsTimestamp][IMinter.RewardsType(j)];
          IMinter(minter).compoundRewards(IMinter.RewardsType(j), amount);
        }
      }
      lastDistributeRewardsTimestamp += 1 days;
    }
  }

  /**
   * @dev unpause the contract
   */
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  // /* ============ Internal Functions ============ */

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
