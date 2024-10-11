// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Buyback interface
interface IBuyback {

  struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  function initialize(
    address _admin,
    address _manager,
    address _token,
    address _receiver,
    address _oneInchRouter
  ) external;


  function buyback(address _1inchRouter, bytes calldata swapData) external;

  function changeReceiver(address _receiver) external;

  function add1InchRouterWhitelist(address oneInchRouter) external;

  function remove1InchRouterWhitelist(address oneInchRouter) external;

}
