// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IMinter.sol";
import "./interfaces/IAssToken.sol";

contract Minter is
  IMinter,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  // compounder role
  bytes32 public constant COMPOUNDER = keccak256("COMPOUNDER");
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // denominator
  uint256 public constant DENOMINATOR = 10000;

  /* ============ State Variables ============ */
  // token address
  IERC20 public token;
  // assToken address
  IAssToken public assToken;
  // total tokens
  uint256 public totalTokens;
  // total veToken rewards
  uint256 public totalVeTokenRewards;
  // total vote rewards
  uint256 public totalVoteRewards;
  // swap router
  address public swapRouter;
  // swap pool
  address public swapPool;
  // max swap ratio
  uint256 public maxSwapRatio;

  /* ============ Events ============ */

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _token - Address of the token
   * @param _assToken - Address of the assToken
   * @param _swapRouter - Address of swap router
   * @param _swapPool - Address of swap pool
   * @param _maxSwapRatio - Max swap ratio
   */
  function initialize(
    address _admin,
    address _token,
    address _assToken,
    address _swapRouter,
    address _swapPool,
    uint256 _maxSwapRatio
  ) external override initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_token != address(0), "Invalid token address");
    require(_assToken != address(0), "Invalid AssToken address");
    require(_swapRouter != address(0), "Invalid swap router address");
    require(_swapPool != address(0), "Invalid swap pool address");
    require(_maxSwapRatio <= DENOMINATOR, "Invalid max swap ratio");

    __Pausable_init();
    __ReentrancyGuard_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);

    token = IERC20(_token);
    assToken = IAssToken(_assToken);
    swapRouter = _swapRouter;
    swapPool = _swapPool;
    maxSwapRatio = _maxSwapRatio;
  }

  /**
   * @dev smart mint assToken
   * @param _amountIn - amount of token
   * @param mintRatio - mint ratio
   * @param _minOut - minimum output
   */
  function smartMint(
    uint256 _amountIn,
    uint256 mintRatio,
    uint256 _minOut
  ) external override returns (uint256) {
    return 0;
  }

  /**
   * @dev mint assToken
   * @param _amountIn - amount of token
   */
  function mint(
    uint256 _amountIn
  ) public override whenNotPaused returns (uint256) {
    return 0;
  }

  /**
   * @dev buyback assToken
   * @param _amountIn - amount of token
   * @param _minOut - minimum output of assToken
   */
  function buyback(
    uint256 _amountIn,
    uint256 _minOut
  ) public whenNotPaused nonReentrant returns (uint256) {
    return 0;
  }

  /**
   * @dev Flips the pause state
   */
  function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    paused() ? _unpause() : _pause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
