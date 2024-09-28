// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPancakeStableSwapPool} from "../interfaces/pancakeswap/IPancakeStableSwapPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPancakeStableSwapPool is IPancakeStableSwapPool {
  using SafeERC20 for IERC20;
  IERC20 public token0ERC20;
  IERC20 public token1ERC20;

  constructor(address _token0, address _token1){
    token0ERC20 = IERC20(_token0);
    token1ERC20 = IERC20(_token1);
  }

  function balances(uint256) external view returns (uint256) {
    return token1ERC20.balanceOf(address(this));
  }

  function get_dy(
    uint256 token0,
    uint256 token1,
    uint256 inputAmount
  ) external view returns (uint256 outputAmount) {
    return  token1ERC20.balanceOf(address(this)) / token0ERC20.balanceOf(address(this)) * inputAmount;
  }
}
