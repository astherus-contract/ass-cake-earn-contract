// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPancakeStableSwapRouter} from "../interfaces/pancakeswap/IPancakeStableSwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPancakeStableSwapRouter is IPancakeStableSwapRouter {
  using SafeERC20 for IERC20;

  constructor(){}

  function exactInputStableSwap(
    address[] calldata path,
    uint256[] calldata flag,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
  ) external payable override returns (uint256 amountOut) {
    IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(path[1]).safeTransferFrom(address(this), to, amountOutMin);
    return amountOutMin;
  }
}
