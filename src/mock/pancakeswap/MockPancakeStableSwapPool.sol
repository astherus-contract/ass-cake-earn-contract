// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPancakeStableSwapRouter} from "../../interfaces/pancakeswap/IPancakeStableSwapRouter.sol";
import {IPancakeStableSwapPool} from "../../interfaces/pancakeswap/IPancakeStableSwapPool.sol";

contract MockPancakeStableSwapPool is IPancakeStableSwapPool, IPancakeStableSwapRouter {
  using SafeERC20 for IERC20;
  IERC20 public token0ERC20;
  IERC20 public token1ERC20;
  uint256 public exchangeRate;

  constructor(address _token0, address _token1, uint256 _exchangeRate) {
    token0ERC20 = IERC20(_token0);
    token1ERC20 = IERC20(_token1);
    exchangeRate = _exchangeRate;
  }

  /**
    * @dev set the exchange rate between token0 and token1
    * @param _exchangeRate the exchange rate between token0 and token1
    */
  function setExchangeRate(uint256 _exchangeRate) external {
    exchangeRate = _exchangeRate;
  }

  function balances(uint256 idx) external view returns (uint256) {
    if (idx == 0) {
      return token0ERC20.balanceOf(address(this));
    } else if (idx == 1) {
      return token1ERC20.balanceOf(address(this));
    }
    revert("MockPancakeStableSwapPool: INVALID_INDEX");
  }

  function get_dy(
    uint256 i,
    uint256 j,
    uint256 inputAmount
  ) public view returns (uint256 outputAmount) {
    if (i == 0 && j == 1) {
      return inputAmount * exchangeRate / 1e5;
    } else if (i == 1 && j == 0) {
      return inputAmount / exchangeRate * 1e5;
    }
    revert("MockPancakeStableSwapPool: INVALID_INDEX");
  }

  function exactInputStableSwap(
    address[] calldata path,
    uint256[] calldata flag,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
  ) external payable override returns (uint256 amountOut) {
    IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
    uint256 amountOut = get_dy(flag[0], flag[1], amountIn);
    require(amountOut >= amountOutMin, "MockPancakeStableSwapPool: INSUFFICIENT_OUTPUT_AMOUNT");
    IERC20(path[1]).safeTransferFrom(address(this), to, amountOut);
    return amountOut;
  }
}
