// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Minter } from "../src/Minter.sol";
import { AssToken } from "../src/AssToken.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import { MockPancakeStableSwapRouter } from "../src/mock/MockPancakeStableSwapRouter.sol";
import { MockPancakeStableSwapPool } from "../src/mock/MockPancakeStableSwapPool.sol";

contract MinterTest is Test {
  Minter public minter;
  MockERC20 public token;
  AssToken public assToken;
  MockPancakeStableSwapRouter public swapRouter;
  MockPancakeStableSwapPool public swapPool;
  address manager = makeAddr("MANAGER");
  address public admin = address(0xACC0);
  address public user1 = address(0xACC1);
  address public user2 = address(0xACC2);
  address public user3 = address(0xACC3);

  function setUp() public {
    token = new MockERC20("CAKE", "CAKE");
    console.log("token address: %s", address(token));
    token.mint(user1, 10000 ether);
    console.log("user1: %s", user1);

    vm.startPrank(user1);
    // deploy assToken
    address assTokenProxy = Upgrades.deployUUPSProxy(
      "AssToken.sol",
      abi.encodeCall(AssToken.initialize, ("AssCAKE", "AssCAKE", admin, admin))
    );
    console.log("AssTokenProxy address: %", assTokenProxy);
    assToken = AssToken(assTokenProxy);
    console.log("AssToken proxy address: %s", assTokenProxy);
    // deploy mock swap router
    swapRouter = new MockPancakeStableSwapRouter();
    // deploy mock swap contract
    swapPool = new MockPancakeStableSwapPool(address(token), assTokenProxy);
    // transfer token to swap contract
    token.transfer(address(swapPool), 1000 ether);
    vm.stopPrank();

    vm.startPrank(admin);
    // mint assToken to swap contract
    assToken.mint(address(swapPool), 1000 ether);
    // mint assToken to swapRouter
    assToken.mint(address(swapRouter), 2000 ether);
    vm.stopPrank();

    vm.startPrank(user1);
    uint256 maxSwapRatio = 10000;

    // deploy minter with user1
    address minterProxy = Upgrades.deployUUPSProxy(
      "Minter.sol",
      abi.encodeCall(
        Minter.initialize,
        (
          admin,
          manager,
          address(token),
          assTokenProxy,
          address(swapRouter),
          address(swapRouter),
          address(swapPool),
          maxSwapRatio
        )
      )
    );
    minter = Minter(minterProxy);
    console.log("minter proxy address: %s", minterProxy);
    vm.stopPrank();

    // set minter for assToken
    vm.prank(admin);
    assToken.setMinter(minterProxy);
    require(assToken.minter() == minterProxy, "minter not set");
    vm.stopPrank();
  }

  //  function testSmartMint() public {
  //    vm.startPrank(user1);
  //    uint256 amountIn = 100 ether;
  //    uint256 mintRatio = 1000;
  //    uint256 minOut = 100 ether;
  //    uint256 result = minter.smartMint(amountIn, mintRatio, minOut);
  //    console.log("result: %s", result);
  //    vm.stopPrank();
  //  }

  /*  function testMint() public {
    vm.startPrank(user1);
    uint256 amountIn = 100 ether;
    uint256 result = minter.mint(amountIn);
    console.log("result: %s", result);
    vm.stopPrank();
  }*/

  //  function testBuyback() public {
  //    vm.startPrank(user1);
  //    uint256 amountIn = 100 ether;
  //    uint256 minOut = 100 ether;
  //    uint256 result = minter.buyback(amountIn, minOut);
  //    console.log("result: %s", result);
  //    vm.stopPrank();
  //  }

  /**
   * @dev test upgrade
   */
  function testUpgrade() public {
    address proxyAddress = address(minter);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "Minter.sol", "", msg.sender);

    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "Minter.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }
}
