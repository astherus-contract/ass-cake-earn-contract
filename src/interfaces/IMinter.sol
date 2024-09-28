// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minter interface
interface IMinter {
  function initialize(address _admin, address _token, address _assToken, address _swapRouter, address _swapPool, uint256 _maxSwapRatio) external;

  function smartMint(uint256 _amountIn, uint256 mintRatio, uint256 _minOut) external returns (uint256);

  function mint(uint256 _amountIn) external returns (uint256);

  function buyback(uint256 _amountIn, uint256 _minOut) external returns (uint256);
}
