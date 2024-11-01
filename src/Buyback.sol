// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IBuyback.sol";

contract Buyback is
  IBuyback,
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

  uint256 internal constant DAY = 1 days;

  bytes4 public constant SWAP_SELECTOR =
    bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)"));

  address public constant SWAP_NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /* ============ State Variables ============ */
  // buyback receiver address
  address public receiver;
  // eg:CAKE
  address public swapDstToken;
  // oneInchRouter Whitelist
  mapping(address => bool) public oneInchRouterWhitelist;
  // swap source token Whitelist
  mapping(address => bool) public swapSrcTokenWhitelist;
  // daily Bought
  mapping(uint256 => uint256) public dailyBought;
  // total bought
  uint256 public totalBought;

  /* ============ Events ============ */
  event BoughtBack(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
  event ReceiverChanged(address indexed receiver);
  event OneInchRouterChanged(address indexed oneInchRouter, bool added);
  event SwapSrcTokenChanged(address indexed srcToken, bool added);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _manager - Address of the manager
   * @param _swapDstToken - Address of the swapDstToken
   * @param _receiver - Address of the receiver
   * @param _oneInchRouter - Address of swap oneInchRouter
   */
  function initialize(
    address _admin,
    address _manager,
    address _swapDstToken,
    address _receiver,
    address _oneInchRouter
  ) external override initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid _manager address");
    require(_swapDstToken != address(0), "Invalid swapDstToken address");
    require(_receiver != address(0), "Invalid receiver address");
    require(_oneInchRouter != address(0), "Invalid oneInchRouter address");

    __Pausable_init();
    __ReentrancyGuard_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);

    swapDstToken = _swapDstToken;
    receiver = _receiver;
    oneInchRouterWhitelist[_oneInchRouter] = true;
  }

  // /* ============ External Functions ============ */

  /**
   * @dev buyback
   * @param _1inchRouter - Address of the 1inchRouter
   * @param swapData - swap data
   */
  function buyback(
    address _1inchRouter,
    bytes calldata swapData
  ) external override onlyRole(BOT) nonReentrant whenNotPaused {
    require(oneInchRouterWhitelist[_1inchRouter], "1inchRouter not whitelisted");

    // Get data (swapData) from https://api.1inch.dev/swap/v6.0/56/swap without making any changes and pass it to the contract method
    require(bytes4(swapData[0:4]) == SWAP_SELECTOR, "invalid 1Inch function selector");

    (, SwapDescription memory swapDesc, ) = abi.decode(swapData[4:], (address, SwapDescription, bytes));

    require(swapSrcTokenWhitelist[address(swapDesc.srcToken)], "srcToken not whitelisted");
    require(address(swapDesc.dstToken) == swapDstToken, "invalid dstToken");
    require(swapDesc.dstReceiver == receiver, "invalid dstReceiver");
    require(swapDesc.amount > 0, "invalid amount");

    bool isNativeSrcToken = address(swapDesc.srcToken) == SWAP_NATIVE_ADDRESS ? true : false;
    uint256 srcTokenBalance = isNativeSrcToken ? address(this).balance : swapDesc.srcToken.balanceOf(address(this));
    require(srcTokenBalance >= swapDesc.amount, "insufficient balance");

    if (!isNativeSrcToken) {
      swapDesc.srcToken.safeIncreaseAllowance(_1inchRouter, swapDesc.amount);
    }
    uint256 beforeBalance = swapDesc.dstToken.balanceOf(receiver);

    bool succ;
    bytes memory _data;
    if (isNativeSrcToken) {
      (succ, _data) = address(_1inchRouter).call{ value: swapDesc.amount }(swapData);
    } else {
      (succ, _data) = address(_1inchRouter).call(swapData);
    }

    require(succ, "1inch call failed");

    uint256 afterBalance = swapDesc.dstToken.balanceOf(receiver);
    (uint256 amountOut, ) = abi.decode(_data, (uint256, uint256));
    uint256 diff = afterBalance - beforeBalance;

    require(amountOut == diff, "received incorrect token amount");
    require(amountOut >= swapDesc.minReturnAmount, "less than minReturnAmount");

    totalBought += amountOut;
    uint256 today = (block.timestamp / DAY) * DAY;
    dailyBought[today] = dailyBought[today] + amountOut;

    emit BoughtBack(address(swapDesc.srcToken), address(swapDesc.dstToken), swapDesc.amount, amountOut);
  }

  /**
   * @dev changeReceiver
   * @param _receiver - Address of the receiver
   */
  function changeReceiver(address _receiver) external onlyRole(MANAGER) {
    require(_receiver != address(0), "_receiver is the zero address");
    require(_receiver != receiver, "_receiver is the same");

    receiver = _receiver;
    emit ReceiverChanged(_receiver);
  }

  /**
   * @dev add1InchRouterWhitelist
   * @param oneInchRouter - Address of the oneInchRouter
   */
  function add1InchRouterWhitelist(address oneInchRouter) external onlyRole(MANAGER) {
    require(!oneInchRouterWhitelist[oneInchRouter], "oneInchRouter already whitelisted");

    oneInchRouterWhitelist[oneInchRouter] = true;
    emit OneInchRouterChanged(oneInchRouter, true);
  }

  /**
   * @dev remove1InchRouterWhitelist
   * @param oneInchRouter - Address of the oneInchRouter
   */
  function remove1InchRouterWhitelist(address oneInchRouter) external onlyRole(MANAGER) {
    require(oneInchRouterWhitelist[oneInchRouter], "oneInchRouter not whitelisted");

    delete oneInchRouterWhitelist[oneInchRouter];
    emit OneInchRouterChanged(oneInchRouter, false);
  }

  /**
   * @dev addSwapSrcTokenWhitelist
   * @param srcToken - Address of the srcToken
   */
  function addSwapSrcTokenWhitelist(address srcToken) external onlyRole(MANAGER) {
    require(!swapSrcTokenWhitelist[srcToken], "srcToken already whitelisted");

    swapSrcTokenWhitelist[srcToken] = true;
    emit SwapSrcTokenChanged(srcToken, true);
  }

  /**
   * @dev removeSwapSrcTokenWhitelist
   * @param srcToken - Address of the srcToken
   */
  function removeSwapSrcTokenWhitelist(address srcToken) external onlyRole(MANAGER) {
    require(swapSrcTokenWhitelist[srcToken], "srcToken not whitelisted");

    delete swapSrcTokenWhitelist[srcToken];
    emit SwapSrcTokenChanged(srcToken, false);
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
