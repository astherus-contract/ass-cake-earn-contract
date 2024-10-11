// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Buyback } from "../src/Buyback.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IBuyback.sol";

contract BuybackTest is Test {
  Buyback public buyback;
  address public manager = makeAddr("MANAGER");
  address public admin = makeAddr("ADMIN");
  address public pauser = makeAddr("PAUSER");
  address public bot = makeAddr("BOT");

  address public receiver = 0xf4903f4544558515b26ec4C6D6e91D2293b27275;
  address public oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;
  address public swapDstToken = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
  address public user1 = address(0xACC4);

  bytes public swapData =
    hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000ba2ae424d960c26247dd6c32edc70b295c744c430000000000000000000000000e09fabb73bd3ade0a17ecc321fd13a19e81ce82000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000f4903f4544558515b26ec4c6d6e91d2293b272750000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000003e0aa077cc0ab20217f7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000b24000000000000000000000000000000000000000000000b06000ad8000a8e00a0c9e75c4800000000000000000901000000000000000000000000000000000000000000000000000a600004b500a007e5c0d200000000000000000000000000000000000000000000000000049100034a00a0c9e75c48000000000012110a030200000000000000000000000000000000031c0002a10002260001ab00007b0c20ba2ae424d960c26247dd6c32edc70b295c744c43dcbc1d9d48016b8d5f3b0f9045eb3b72f38e6b936ae4071118000f4240dcbc1d9d48016b8d5f3b0f9045eb3b72f38e6b9300000000000000000000000000000000000000000000008041c203cbc6e13805ba2ae424d960c26247dd6c32edc70b295c744c435106c9a0f685f39d05d835c369036251ee3aeaaf3c47ba2ae424d960c26247dd6c32edc70b295c744c43000438ed1739000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009c7b525d150f0fd41c00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000670f77250000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ba2ae424d960c26247dd6c32edc70b295c744c4300000000000000000000000055d398326f99059ff775485246999027b31979550c20ba2ae424d960c26247dd6c32edc70b295c744c435784425c93f264ef667a0695317196a3bb457c556ae4071118001e84805784425c93f264ef667a0695317196a3bb457c550000000000000000000000000000000000000000000002096543210e5b740b07ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c430fa119e6a12e3540c2412f9eda0221ffd16a79346ae4071118002625a00fa119e6a12e3540c2412f9eda0221ffd16a793400000000000000000000000000000000000000000000039ffc06f3982d4cf3aeba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c43f8e9b725e0de8a9546916861c2904b0eb8805b966ae4071118002dc6c0f8e9b725e0de8a9546916861c2904b0eb8805b960000000000000000000000000000000000000000000003b30d6d308d8e643207ba2ae424d960c26247dd6c32edc70b295c744c4300a0c9e75c48000000000000002c04020000000000000000000000000000000000000000000001190000ca00007b0c2055d398326f99059ff775485246999027b3197955a39af17ce4a8eb807e076805da1e2b8ea7d0755b6ae4071118002625a0a39af17ce4a8eb807e076805da1e2b8ea7d0755b00000000000000000000000000000000000000000000003afe307df03b6808d655d398326f99059ff775485246999027b319795502a000000000000000000000000000000000000000000000007614a28b5e0be24f42ee63c1e500e04d921d6ab7c3ef2eee14dd7a95be5706a1ea9355d398326f99059ff775485246999027b319795502a000000000000000000000000000000000000000000000051170fa7a95ad56de0bee63c1e5007f51c8aaa6b0599abd16674e2b17fec7a9f674a155d398326f99059ff775485246999027b319795500a007e5c0d20000000000000000000000000000000000000000000000000005870003c500a0c9e75c480000000028050201010100000000000000000000000000039700031c0002a10002260001ab00007b0c20ba2ae424d960c26247dd6c32edc70b295c744c43b8b20a1e5595bfeb21df0e162be2744a7ed325816ae4071198001e8480b8b20a1e5595bfeb21df0e162be2744a7ed3258100000000000000000000000000000000000000000000000054f0a6a26eb8aa1fba2ae424d960c26247dd6c32edc70b295c744c435106c9a0f685f39d05d835c369036251ee3aeaaf3c47ba2ae424d960c26247dd6c32edc70b295c744c43000438ed173900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b2ea12c0c20a7d600000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000670f77250000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ba2ae424d960c26247dd6c32edc70b295c744c43000000000000000000000000bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0c20ba2ae424d960c26247dd6c32edc70b295c744c43b3432500334e8b08f12a66916912456aad1c78c96ae40711d8002dc6c0b3432500334e8b08f12a66916912456aad1c78c90000000000000000000000000000000000000000000000002427b225e7211347ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c43fd1ef328a17a8e8eeaf7e4ea1ed8a108e1f2d0966ae4071198001e8480fd1ef328a17a8e8eeaf7e4ea1ed8a108e1f2d09600000000000000000000000000000000000000000000000239f64d4ec9951deeba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c431ef315fa08e0e1b116d97e3dfe0af292ed8b7f026ae4071198001e84801ef315fa08e0e1b116d97e3dfe0af292ed8b7f0200000000000000000000000000000000000000000000000531816aade6883cc7ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c43ac109c8025f272414fd9e2faa805a583708a017f6ae4071198002625a0ac109c8025f272414fd9e2faa805a583708a017f000000000000000000000000000000000000000000000026e6a953fb96f28470ba2ae424d960c26247dd6c32edc70b295c744c4300a0c9e75c480000000000001b1402010000000000000000000000000000000000000001940001450000ca00007b0c20bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095ca527a61703d82139f8a06bc30097cc9caa2df5a66ae4071118001e8480a527a61703d82139f8a06bc30097cc9caa2df5a600000000000000000000000000000000000000000000011fbdb6baefd65fb35ebb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c02a000000000000000000000000000000000000000000000023f9369e2ade4a2964cee63c1e500afb2da14056725e3ba3a30dd846b6bbbd7886c56bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0c20bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0ed7e52944161450477ee417de9cd3a859b14fd06ae4071118002625a00ed7e52944161450477ee417de9cd3a859b14fd000000000000000000000000000000000000000000000168379a7078a3cdb5151bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c02a0000000000000000000000000000000000000000000001e6551e2a2fec58346d5ee63c1e500133b3d95bad5405d14d53473671200e9342896bfbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00a0f2fa6b660e09fabb73bd3ade0a17ecc321fd13a19e81ce82000000000000000000000000000000000000000000003eab0eb1e56022ff87670000000000000000266b5f6d69c9b75280a06c4eca270e09fabb73bd3ade0a17ecc321fd13a19e81ce82111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000000000000000000000000000b3276493";

  function setUp() public {
    // fork mainnet
    vm.createSelectFork("https://rpc.ankr.com/bsc");

    vm.startPrank(user1);

    // deploy buyback with user1
    address buybackProxy = Upgrades.deployUUPSProxy(
      "Buyback.sol",
      abi.encodeCall(
        Buyback.initialize,
        (
          admin,
          manager,
          address(swapDstToken),
          address(receiver),
          address(oneInchRouter)
        )
      )
    );
    buyback = Buyback(buybackProxy);
    console.log("buyback proxy address: %s", buybackProxy);
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    buyback.grantRole(buyback.BOT(), bot);
    vm.stopPrank();

    // add swapSrcToken
    vm.startPrank(manager);
    address swapSrcToken = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43;
    deal(address(swapSrcToken), buybackProxy, 10000 ether);
    buyback.addSwapSrcTokenWhitelist(swapSrcToken);
    assertEq(buyback.swapSrcTokenWhitelist(swapSrcToken), true);
    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackFail() public {
    //user no access
    vm.expectRevert();
    buyback.buyback(oneInchRouter, "");

    //contract pause
    vm.startPrank(admin);
    if (buyback.paused() != true) {
      buyback.togglePause();
    }
    assertEq(buyback.paused(), true);
    vm.stopPrank();

    vm.startPrank(bot);
    vm.expectRevert();
    buyback.buyback(oneInchRouter, "");
    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackSuccess() public {
    //contract no pause
    vm.startPrank(admin);
    if (buyback.paused() == true) {
      buyback.togglePause();
      assertEq(buyback.paused(), false);
    }
    vm.stopPrank();

    vm.startPrank(bot);

    uint256 beforeTotalBought = buyback.totalBought();
    uint256 beforeReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);

    buyback.buyback(oneInchRouter, swapData);

    uint256 afterTotalBought = buyback.totalBought();
    uint256 afterReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 diffTotalBought = afterTotalBought - beforeTotalBought;
    uint256 diffReceiverBalance = afterReceiverBalance - beforeReceiverBalance;
    assertEq(diffTotalBought, diffReceiverBalance);

    vm.stopPrank();
  }

  /**
   * @dev test changeReceiver
   */
  function testChangeReceiver() public {
    address swapReceiver = makeAddr("receiver");
    //user no access
    vm.expectRevert();
    buyback.changeReceiver(swapReceiver);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_receiver is the zero address");
    buyback.changeReceiver(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    buyback.changeReceiver(swapReceiver);
    assertEq(buyback.receiver(), swapReceiver);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(buyback.receiver(), swapReceiver);
    vm.expectRevert("_receiver is the same");
    buyback.changeReceiver(swapReceiver);
    vm.stopPrank();
  }

  /**
   * @dev test Add1InchRouterWhitelist
   */
  function testAdd1InchRouterWhitelist() public {
    address router = makeAddr("oneInchRouter");
    //user no access
    vm.expectRevert();
    buyback.add1InchRouterWhitelist(router);

    //add success
    vm.startPrank(manager);
    buyback.add1InchRouterWhitelist(router);
    assertEq(buyback.oneInchRouterWhitelist(router), true);
    vm.stopPrank();

    //duplicate add
    vm.startPrank(manager);
    assertEq(buyback.oneInchRouterWhitelist(router), true);
    vm.expectRevert("oneInchRouter already whitelisted");
    buyback.add1InchRouterWhitelist(router);
    vm.stopPrank();
  }

  /**
   * @dev test Remove1InchRouterWhitelist
   */
  function testRemove1InchRouterWhitelist() public {
    address router = makeAddr("oneInchRouter");
    //user no access
    vm.expectRevert();
    buyback.remove1InchRouterWhitelist(router);

    //no oneInchRouter in whitelisted
    vm.startPrank(manager);
    assertEq(buyback.oneInchRouterWhitelist(router), false);
    vm.expectRevert("oneInchRouter not whitelisted");
    buyback.remove1InchRouterWhitelist(router);
    vm.stopPrank();

    //remove success
    vm.startPrank(manager);
    buyback.add1InchRouterWhitelist(router);
    assertEq(buyback.oneInchRouterWhitelist(router), true);
    buyback.remove1InchRouterWhitelist(router);
    assertEq(buyback.oneInchRouterWhitelist(router), false);
    vm.stopPrank();
  }

  /**
   * @dev test AddSwapSrcTokenWhitelist
   */
  function testAddSwapSrcTokenWhitelist() public {
    address srcToken = makeAddr("srcToken1");
    //user no access
    vm.expectRevert();
    buyback.addSwapSrcTokenWhitelist(srcToken);

    //add success
    vm.startPrank(manager);
    buyback.addSwapSrcTokenWhitelist(srcToken);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), true);
    vm.stopPrank();

    //duplicate add
    vm.startPrank(manager);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), true);
    vm.expectRevert("srcToken already whitelisted");
    buyback.addSwapSrcTokenWhitelist(srcToken);
    vm.stopPrank();
  }

  /**
   * @dev test RemoveSwapSrcTokenWhitelist
   */
  function testRemoveSwapSrcTokenWhitelist() public {
    address srcToken = makeAddr("srcToken1");
    //user no access
    vm.expectRevert();
    buyback.removeSwapSrcTokenWhitelist(srcToken);

    //no srcToken in whitelisted
    vm.startPrank(manager);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), false);
    vm.expectRevert("srcToken not whitelisted");
    buyback.removeSwapSrcTokenWhitelist(srcToken);
    vm.stopPrank();

    //remove success
    vm.startPrank(manager);
    buyback.addSwapSrcTokenWhitelist(srcToken);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), true);
    buyback.removeSwapSrcTokenWhitelist(srcToken);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), false);
    vm.stopPrank();
  }

  /**
   * @dev test Flips the pause state
   */
  function testTogglePause() public {
    //user no access
    vm.expectRevert();
    buyback.togglePause();

    //togglePause success
    vm.startPrank(admin);
    bool paused = buyback.paused();
    buyback.togglePause();
    assertEq(buyback.paused(), !paused);
    vm.stopPrank();
  }

  /**
   * @dev test pause the contract
   */
  function testPause() public {
    //user no access
    vm.expectRevert();
    buyback.pause();

    //pauser no access
    vm.startPrank(pauser);
    vm.expectRevert();
    buyback.togglePause();
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    buyback.grantRole(buyback.DEFAULT_ADMIN_ROLE(), pauser);
    vm.stopPrank();

    //togglePause success
    vm.startPrank(pauser);
    buyback.togglePause();
    assertEq(buyback.paused(), true);
    vm.stopPrank();
  }

  /**
   * @dev test upgrade
   */
  function testUpgrade() public {
    address proxyAddress = address(buyback);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    //no access
    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "Buyback.sol", "", msg.sender);

    //upgradeProxy success
    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "Buyback.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }
}
