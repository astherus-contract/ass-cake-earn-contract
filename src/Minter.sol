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
import "./interfaces/pancakeswap/IPancakeStableSwapPool.sol";
import "./interfaces/pancakeswap/IPancakeStableSwapRouter.sol";
import "./interfaces/IUniversalProxy.sol";

contract Minter is
  IMinter,
  Initializable,
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
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");
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
  // total donate rewards
  uint256 public donateRewards;
  // veToken rewards fee rate in percentage (10_000 = 100%)
  uint256 public veTokenRewardsFeeRate;
  // vote rewards fee rate in percentage (10_000 = 100%)
  uint256 public voteRewardsFeeRate;
  // donate rewards fee rate in percentage (10_000 = 100%)
  uint256 public donateRewardsFeeRate;
  // total totalFee
  uint256 public totalFee;
  // swap router
  address public swapRouter;
  // swap pool
  address public swapPool;
  // max swap ratio
  uint256 public maxSwapRatio;
  //universal Proxy
  address public universalProxy;

  /* ============ Events ============ */
  event SmartMinted(address user, uint256 cakeInput, uint256 obtainedAssCake);
  event RewardsCompounded(
    address sender,
    RewardsType rewardsType,
    uint256 amountIn,
    uint256 lockAmount,
    uint256 fee
  );
  event FeeRateUpdated(
    address sender,
    RewardsType rewardsType,
    uint256 oldFeeRate,
    uint256 newFeeRate
  );
  event FeeWithdrawn(address sender, address receipt, uint256 amountIn);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _token - Address of the token
   * @param _assToken - Address of the assToken
   * @param _universalProxy - Address of the universalProxy
   * @param _swapRouter - Address of swap router
   * @param _swapPool - Address of swap pool
   * @param _maxSwapRatio - Max swap ratio
   */
  function initialize(
    address _admin,
    address _manager,
    address _token,
    address _assToken,
    address _universalProxy,
    address _swapRouter,
    address _swapPool,
    uint256 _maxSwapRatio
  ) external override initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_token != address(0), "Invalid token address");
    require(_assToken != address(0), "Invalid AssToken address");
    require(_universalProxy != address(0), "Invalid universalProxy address");
    require(_swapRouter != address(0), "Invalid swap router address");
    require(_swapPool != address(0), "Invalid swap pool address");
    require(_maxSwapRatio <= DENOMINATOR, "Invalid max swap ratio");

    __Pausable_init();
    __ReentrancyGuard_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);

    token = IERC20(_token);
    assToken = IAssToken(_assToken);
    universalProxy = _universalProxy;
    swapRouter = _swapRouter;
    swapPool = _swapPool;
    maxSwapRatio = _maxSwapRatio;
  }

  /* ============ External Getters ============ */

  function estimateTotalOut(
    uint256 _amountIn,
    uint256 _mintRatio
  ) public view returns (uint256 minimumEstimatedTotal) {
    require(_mintRatio <= DENOMINATOR, "Incorrect Ratio");

    uint256 buybackAmount = _amountIn -
      ((_amountIn * _mintRatio) / DENOMINATOR);
    uint256 mintAmount = _amountIn - buybackAmount;
    uint256 amountOut = 0;

    if (buybackAmount > 0) {
      amountOut += IPancakeStableSwapPool(swapPool).get_dy(0, 1, buybackAmount);
    }

    if (mintAmount > 0) {
      amountOut += convertToAssTokens(mintAmount);
    }

    return amountOut;
  }

  function currentSwapRatio() public view returns (uint256) {
    // 1 assCAKE=currentSwapRatio CAKE
    uint256 amountOut = IPancakeStableSwapPool(swapPool).get_dy(1, 0, 1e18);
    return (amountOut * DENOMINATOR) / 1e18;
  }

  function convertToTokens(uint256 assTokens) public view returns (uint256) {
    uint256 totalSupply = assToken.totalSupply();
    if (totalSupply == 0 || totalTokens == 0) {
      return assTokens;
    }
    return (assTokens * totalTokens) / totalSupply;
  }

  function convertToAssTokens(uint256 tokens) public view returns (uint256) {
    uint256 totalSupply = assToken.totalSupply();
    if (totalSupply == 0 || totalTokens == 0) {
      return tokens;
    }
    return (tokens * totalSupply) / totalTokens;
  }

  // /* ============ External Functions ============ */

  /**
   * @dev smart mint assToken
   * @param _amountIn - amount of token
   * @param _mintRatio - mint ratio
   * @param _minOut - minimum output
   */
  function smartMint(
    uint256 _amountIn,
    uint256 _mintRatio,
    uint256 _minOut
  ) external override whenNotPaused nonReentrant returns (uint256) {
    return _smartMint(_amountIn, _mintRatio, _minOut);
  }

  function compoundRewards(
    IMinter.RewardsType _rewardsType,
    uint256 _amountIn
  ) external override onlyRole(COMPOUNDER) whenNotPaused nonReentrant {
    require(_amountIn > 0, "Invalid amount");

    IERC20(token).safeTransferFrom(msg.sender, address(this), _amountIn);

    uint256 lockAmount = 0;
    uint256 fee = 0;
    if (_rewardsType == RewardsType.VeTokenRewards) {
      fee = (_amountIn * veTokenRewardsFeeRate) / DENOMINATOR;
      lockAmount = _amountIn - fee;
      totalVeTokenRewards += lockAmount;
    } else if (_rewardsType == RewardsType.VoteRewards) {
      fee = (_amountIn * voteRewardsFeeRate) / DENOMINATOR;
      lockAmount = _amountIn - fee;
      totalVoteRewards += lockAmount;
    } else {
      fee = (_amountIn * donateRewardsFeeRate) / DENOMINATOR;
      lockAmount = _amountIn - fee;
      donateRewards += lockAmount;
    }
    totalFee += fee;
    totalTokens += lockAmount;

    IERC20(token).safeIncreaseAllowance(universalProxy, lockAmount);
    IUniversalProxy(universalProxy).lock(lockAmount);

    emit RewardsCompounded(
      msg.sender,
      _rewardsType,
      _amountIn,
      lockAmount,
      fee
    );
  }

  /**
   * @dev mint assToken
   * @param _amountIn - amount of token
   */
  function _mint(uint256 _amountIn) private returns (uint256) {
    IERC20(token).safeIncreaseAllowance(universalProxy, _amountIn);
    IUniversalProxy(universalProxy).lock(_amountIn);

    uint256 assTokens = convertToAssTokens(_amountIn);

    assToken.mint(address(this), assTokens);

    return assTokens;
  }

  /**
   * @dev buyback assToken
   * @param _amountIn - amount of token
   */
  function _buyback(uint256 _amountIn) private returns (uint256) {
    address[] memory tokenPath = new address[](2);
    tokenPath[0] = address(token);
    tokenPath[1] = address(assToken);
    uint256[] memory flag = new uint256[](1);
    flag[0] = 2;

    token.safeIncreaseAllowance(swapRouter, _amountIn);

    uint256 oldBalance = assToken.balanceOf(address(this));
    IPancakeStableSwapRouter(swapRouter).exactInputStableSwap(
      tokenPath,
      flag,
      _amountIn,
      _amountIn,
      address(this)
    );
    uint256 newBalance = assToken.balanceOf(address(this));

    return (newBalance - oldBalance);
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

  /* ============ Admin Functions ============ */

  function updateFeeRate(
    RewardsType _rewardsType,
    uint256 _feeRate
  ) external nonReentrant onlyRole(MANAGER) {
    require(_feeRate <= DENOMINATOR, "Incorrect Fee Ratio");

    uint256 oldFeeRate = 0;
    if (_rewardsType == RewardsType.VeTokenRewards) {
      require(
        veTokenRewardsFeeRate != _feeRate,
        "newFeeRate can not be equal oldFeeRate"
      );

      oldFeeRate = veTokenRewardsFeeRate;
      veTokenRewardsFeeRate = _feeRate;
    } else if (_rewardsType == RewardsType.VoteRewards) {
      require(
        veTokenRewardsFeeRate != _feeRate,
        "newFeeRate can not be equal oldFeeRate"
      );

      oldFeeRate = voteRewardsFeeRate;
      voteRewardsFeeRate = _feeRate;
    } else {
      require(
        veTokenRewardsFeeRate != _feeRate,
        "newFeeRate can not be equal oldFeeRate"
      );

      oldFeeRate = donateRewardsFeeRate;
      donateRewardsFeeRate = _feeRate;
    }
    emit FeeRateUpdated(msg.sender, _rewardsType, oldFeeRate, _feeRate);
  }

  function withdrawFee(
    address receipt,
    uint256 amountIn
  ) external nonReentrant onlyRole(MANAGER) {
    require(receipt != address(0), "Invalid address");
    require(amountIn > 0, "Invalid amount");
    require(amountIn <= totalFee, "Invalid amount");

    IERC20(token).safeTransfer(receipt, amountIn);
    totalFee -= amountIn;
    emit FeeWithdrawn(msg.sender, receipt, amountIn);
  }

  // /* ============ Internal Functions ============ */

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  function _smartMint(
    uint256 _amountIn,
    uint256 _mintRatio,
    uint256 _minOut
  ) internal returns (uint256) {
    require(_amountIn > 0, "Invalid amount");
    require(_mintRatio <= DENOMINATOR, "Incorrect Ratio");

    token.safeTransferFrom(msg.sender, address(this), _amountIn);

    uint256 buybackAmount = _amountIn -
      ((_amountIn * _mintRatio) / DENOMINATOR);
    uint256 mintAmount = _amountIn - buybackAmount;
    uint256 amountRec = 0;

    if (buybackAmount > 0) {
      amountRec += _buyback(buybackAmount);
    }

    if (mintAmount > 0) {
      amountRec += _mint(mintAmount);
      totalTokens += mintAmount;
    }

    require(amountRec >= _minOut, "MinOut not match");

    IERC20(assToken).safeTransfer(msg.sender, amountRec);

    emit SmartMinted(msg.sender, _amountIn, amountRec);

    return amountRec;
  }
}
