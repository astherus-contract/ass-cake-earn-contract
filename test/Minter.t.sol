// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Minter } from "../src/Minter.sol";
import { AssToken } from "../src/AssToken.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import { MockPancakeStableSwapRouter } from "../src/mock/pancakeswap/MockPancakeStableSwapRouter.sol";
import { MockPancakeStableSwapPool } from "../src/mock/pancakeswap/MockPancakeStableSwapPool.sol";
import { MockVeCake } from "../src/mock/pancakeswap/MockVeCake.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";

contract MinterTest is Test {
  Minter public minter;
  UniversalProxy universalProxy;
  MockERC20 public token;
  AssToken public assToken;
  MockPancakeStableSwapRouter public swapRouter;
  MockPancakeStableSwapPool public swapPool;
  MockVeCake public veToken;
  address manager = makeAddr("MANAGER");
  address pauser = makeAddr("PAUSER");
  address bot = makeAddr("BOT");
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
    // deploy mock swap contract
    swapPool = new MockPancakeStableSwapPool(
      address(token),
      assTokenProxy,
      1e5
    );
    console.log("swapPool address: %s", address(swapPool));
    // deploy mock swap router
    swapRouter = new MockPancakeStableSwapRouter(address(swapPool));
    console.log("swapRouter address: %s", address(swapRouter));
    // transfer cake to swap contract
    token.transfer(address(swapPool), 1000 ether);
    // deploy VeCake
    veToken = new MockVeCake(address(token));
    console.log("VeCake address: %s", address(veToken));
    vm.stopPrank();

    vm.startPrank(admin);
    // mint assToken to swap contract
    assToken.mint(address(swapPool), 1000 ether);
    vm.stopPrank();

    vm.startPrank(user1);
    // deploy UniversalProxy's Proxy
    address[] memory revenueSharingPools = new address[](1);
    revenueSharingPools[0] = address(token);
    address upProxy = Upgrades.deployUUPSProxy(
      "UniversalProxy.sol",
      abi.encodeCall(
        UniversalProxy.initialize,
        (
          admin,
          pauser,
          admin,
          bot,
          manager,
          address(token),
          address(veToken),
          address(token),
          address(token),
          address(token),
          revenueSharingPools,
          address(token)
        )
      )
    );
    console.log("UniversalProxy address: %s", upProxy);
    universalProxy = UniversalProxy(upProxy);

    uint256 maxSwapRatio = 10000;

    // deploy minter with user1
    address minterProxy = Upgrades.deployUUPSProxy(
      "Minter.sol",
      abi.encodeCall(
        Minter.initialize,
        (
          admin,
          manager,
          pauser,
          address(token),
          assTokenProxy,
          address(upProxy),
          address(swapRouter),
          address(swapPool),
          maxSwapRatio
        )
      )
    );
    minter = Minter(minterProxy);
    console.log("minter proxy address: %s", minterProxy);
    vm.stopPrank();

    vm.startPrank(admin);
    // set minter for assToken
    assToken.setMinter(minterProxy);
    require(assToken.minter() == minterProxy, "minter not set");

    // set minter role for UniversalProxy
    universalProxy.grantRole(universalProxy.MINTER(), minterProxy);
    vm.stopPrank();
  }

  function testSmartMint() public {
    vm.startPrank(user1);
    uint256 amountIn = 100 ether;
    uint256 mintRatio = 1000;
    uint256 minOut = 100 ether;
    token.approve(address(minter), amountIn);
    uint256 result = minter.smartMint(amountIn, mintRatio, minOut);
    console.log("result: %s", result);
    vm.stopPrank();
  }

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
