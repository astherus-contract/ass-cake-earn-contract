// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Minter } from "../src/Minter.sol";
import { IMinter } from "../src/interfaces/IMinter.sol";

import { AssToken } from "../src/AssToken.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import { MockPancakeStableSwapRouter } from "../src/mock/pancakeswap/MockPancakeStableSwapRouter.sol";
import { MockPancakeStableSwapPool } from "../src/mock/pancakeswap/MockPancakeStableSwapPool.sol";
import { MockVeCake } from "../src/mock/pancakeswap/MockVeCake.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MinterTest is Test {
  using SafeERC20 for IERC20;
  Minter public minter;
  UniversalProxy universalProxy;
  MockERC20 public token;
  AssToken public assToken;
  MockPancakeStableSwapRouter public pancakeSwapRouter;
  MockPancakeStableSwapPool public pancakeSwapPool;
  MockVeCake public veToken;
  address manager = makeAddr("MANAGER");
  address pauser = makeAddr("PAUSER");
  address bot = makeAddr("BOT");
  address compounder = makeAddr("COMPOUNDER");

  address public admin = address(0xACC0);
  address public user1 = address(0xACC1);
  address public user2 = address(0xACC2);
  address public user3 = address(0xACC3);

  function setUp() public {
    // fork mainnet
    vm.createSelectFork("https://rpc.ankr.com/bsc");

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
    // deploy mock pancake swap contract
    pancakeSwapPool = new MockPancakeStableSwapPool(
      address(token),
      assTokenProxy,
      1e5
    );
    console.log("pancakeSwapPool address: %s", address(pancakeSwapPool));
    // deploy mock pancake swap router
    pancakeSwapRouter = new MockPancakeStableSwapRouter(
      address(pancakeSwapPool)
    );
    console.log("pancakeSwapRouter address: %s", address(pancakeSwapRouter));
    // transfer cake to swap contract
    token.transfer(address(pancakeSwapPool), 1000 ether);
    // deploy VeCake
    veToken = new MockVeCake(address(token));
    console.log("VeCake address: %s", address(veToken));
    vm.stopPrank();

    vm.startPrank(admin);
    // mint assToken to swap contract
    assToken.mint(address(pancakeSwapPool), 1000 ether);
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
          address(pancakeSwapRouter),
          address(pancakeSwapPool),
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

    // set compounder role for compounder
    minter.grantRole(minter.COMPOUNDER(), compounder);

    vm.stopPrank();
  }

  /**
   * @dev test smartMint  assToken/token=1
   */
  function testSmartMintSuccess_assToken_vs_token_eq_1() public {
    // first totalTokens=0;assTokenTotalSupply=1000 ether
    //(tokens * assTokenTotalSupply) / totalTokens;
    //so assToken/token=1
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    uint256 convertToTokens = minter.convertToTokens(convertToAssTokens);
    assertEq(convertToAssTokens, 1 ether);
    assertEq(convertToTokens, 1 ether);
    smartMintSuccess();
  }

  /**
   * @dev test smartMint assToken/token>1
   */
  function testSmartMintSuccess_assToken_vs_token_gt_1() public {
    //default assTokenTotalSupply=1000 ether
    //prepare totalTokens=90
    compoundVeTokenRewardsSuccess(100 ether);

    //(tokens * assTokenTotalSupply) / totalTokens;
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    assertNotEq(convertToAssTokens, 1 ether);
    smartMintSuccess();
  }

  /**
   * @dev test smartMint assToken/token<1
   */
  function testSmartMintSuccess_assToken_vs_token_lt_1() public {
    //default assTokenTotalSupply=1000 ether
    //prepare totalTokens=99990
    compoundVeTokenRewardsSuccess(100000 ether);

    //(tokens * assTokenTotalSupply) / totalTokens;
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    assertNotEq(convertToAssTokens, 1 ether);
    smartMintSuccess();
  }

  /**
   * @dev test smartMint
   */
  function smartMintSuccess() public {
    //(tokens * assTokenTotalSupply) / totalTokens;
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    console.log("convertToAssTokens:%s", convertToAssTokens);

    vm.startPrank(user1);
    uint256 amountIn = 1 ether;
    uint256 mintRatio = 1_000;
    uint256 mintAssTokenAmount = (((convertToAssTokens * amountIn) / 1 ether) *
      mintRatio) / minter.DENOMINATOR();
    uint256 buybackAssTokenAmount = amountIn -
      (amountIn * mintRatio) /
      minter.DENOMINATOR();
    uint256 userReceiveAssTokenAmount = mintAssTokenAmount +
      buybackAssTokenAmount;
    uint256 minOut = userReceiveAssTokenAmount;
    uint256 estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, minOut);
    token.approve(address(minter), amountIn);

    uint256 beforeTotalTokens = minter.totalTokens();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 beforeUserTokenBalance = IERC20(token).balanceOf(user1);
    uint256 beforeTotalSupply = IERC20(assToken).totalSupply();
    uint256 beforeUserAssTokenBalance = IERC20(assToken).balanceOf(user1);

    uint256 result = minter.smartMint(amountIn, mintRatio, minOut);

    uint256 afterTotalTokens = minter.totalTokens();
    uint256 afterMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 afterUserTokenBalance = IERC20(token).balanceOf(user1);
    uint256 afterTotalSupply = IERC20(assToken).totalSupply();
    uint256 afterUserAssTokenBalance = IERC20(assToken).balanceOf(user1);

    assertEq(
      afterTotalTokens - beforeTotalTokens,
      (amountIn * mintRatio) / minter.DENOMINATOR()
    );
    assertEq(afterMinterBalance - beforeMinterBalance, 0);
    assertEq(afterTotalSupply - beforeTotalSupply, mintAssTokenAmount);
    assertEq(beforeUserTokenBalance - afterUserTokenBalance, amountIn);
    assertEq(
      afterUserAssTokenBalance - beforeUserAssTokenBalance,
      userReceiveAssTokenAmount
    );
    assertEq(result, userReceiveAssTokenAmount);

    uint256 assTokenTotalSupply = IERC20(assToken).totalSupply();

    //(tokens * totalSupply) / totalTokens
    assertEq(
      (1 ether * assTokenTotalSupply) / afterTotalTokens,
      minter.convertToAssTokens(1 ether)
    );

    //(assTokens * totalTokens) / totalSupply
    assertEq(
      (1 ether * afterTotalTokens) / assTokenTotalSupply,
      minter.convertToTokens(1 ether)
    );

    vm.stopPrank();
  }

  /**
   * @dev test estimateTotalOut
   */
  function testEstimateTotalOut() public {
    //default assTokenTotalSupply=1000 ether

    //Incorrect Ratio
    uint256 amountIn = 100 ether;
    uint256 estimateTotalOut = 0;
    vm.expectRevert("Incorrect Ratio");
    estimateTotalOut = minter.estimateTotalOut(amountIn, 10_0000);

    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    uint256 convertToTokens = minter.convertToTokens(convertToAssTokens);
    assertEq(convertToTokens, 1 ether);
    console.log("convertToAssTokens:%s", convertToAssTokens);

    vm.startPrank(user1);

    uint256 mintRatio = 0;
    uint256 mintAssTokenAmount = (((convertToAssTokens * amountIn) / 1 ether) *
      mintRatio) / minter.DENOMINATOR();
    uint256 buybackAssTokenAmount = amountIn -
      (amountIn * mintRatio) /
      minter.DENOMINATOR();

    //_mintRatio=0
    estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, mintAssTokenAmount + buybackAssTokenAmount);

    //_mintRatio=1_0000
    mintRatio = 1_0000;
    mintAssTokenAmount =
      (((convertToAssTokens * amountIn) / 1 ether) * mintRatio) /
      minter.DENOMINATOR();
    buybackAssTokenAmount =
      amountIn -
      (amountIn * mintRatio) /
      minter.DENOMINATOR();
    estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, mintAssTokenAmount + buybackAssTokenAmount);

    //_mintRatio=5000
    mintRatio = 5000;
    mintAssTokenAmount =
      (((convertToAssTokens * amountIn) / 1 ether) * mintRatio) /
      minter.DENOMINATOR();
    buybackAssTokenAmount =
      amountIn -
      (amountIn * mintRatio) /
      minter.DENOMINATOR();
    estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, mintAssTokenAmount + buybackAssTokenAmount);
  }

  /**
   * @dev test swapToAssTokens
   */
  function testSwapToAssTokens() public {
    uint256 swapToAssTokens = minter.swapToAssTokens(1 ether);
    assertEq(swapToAssTokens, 1 ether);
  }

  /**
   * @dev test convertToTokens
   */
  function testConvertToTokens() public {
    //default assTokenTotalSupply=1000 ether
    uint256 convertToTokens = minter.convertToTokens(1 ether);
    assertEq(convertToTokens, 1 ether);
  }

  /**
   * @dev test compoundRewards
   */
  function testCompoundVeTokenRewardsSuccess() public {
    compoundVeTokenRewardsSuccess(100 ether);
  }

  /**
   * @dev  compoundRewards
   */
  function compoundVeTokenRewardsSuccess(uint256 amountIn) public {
    // Prepare Fee Ratio
    // (10_000 = 100%)
    uint256 veTokenRewardsFeeRate = 1000;

    vm.startPrank(manager);
    minter.updateFeeRate(
      IMinter.RewardsType.VeTokenRewards,
      veTokenRewardsFeeRate
    );
    vm.stopPrank();

    //compound VeTokenRewards success
    //uint256 amountIn = 100 ether;

    vm.startPrank(compounder);
    deal(address(token), compounder, amountIn);
    uint256 beforeTotalFee = minter.totalFee();
    uint256 beforeTotalTokens = minter.totalTokens();
    uint256 beforeTotalRewards = minter.totalVeTokenRewards();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 beforeCompounderBalance = IERC20(token).balanceOf(compounder);

    IERC20(token).safeIncreaseAllowance(address(minter), amountIn);
    minter.compoundRewards(IMinter.RewardsType.VeTokenRewards, amountIn);

    uint256 afterTotalFee = minter.totalFee();
    uint256 afterTotalTokens = minter.totalTokens();
    uint256 afterTotalRewards = minter.totalVeTokenRewards();
    uint256 afterMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 afterCompounderBalance = IERC20(token).balanceOf(compounder);

    uint256 fee = (amountIn * veTokenRewardsFeeRate) / minter.DENOMINATOR();
    assertEq(afterTotalFee - beforeTotalFee, fee);
    assertEq(afterTotalTokens - beforeTotalTokens, amountIn - fee);
    assertEq(afterTotalRewards - beforeTotalRewards, amountIn - fee);
    console.log("afterMinterBalance %s", afterMinterBalance);
    console.log("beforeMinterBalance %s", beforeMinterBalance);
    assertEq(afterMinterBalance - beforeMinterBalance, fee);
    assertEq(beforeCompounderBalance - afterCompounderBalance, amountIn);

    uint256 assTokenTotalSupply = IERC20(assToken).totalSupply();

    //(tokens * totalSupply) / totalTokens
    assertEq(
      (1 ether * assTokenTotalSupply) / afterTotalTokens,
      minter.convertToAssTokens(1 ether)
    );

    //(assTokens * totalTokens) / totalSupply
    assertEq(
      (1 ether * afterTotalTokens) / assTokenTotalSupply,
      minter.convertToTokens(1 ether)
    );

    vm.stopPrank();
  }

  /**
   * @dev test compoundRewards
   */
  function testCompoundVoteRewardsSuccess() public {
    // Prepare Fee Ratio
    // (10_000 = 100%)
    uint256 voteRewardsFeeRate = 2000;

    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, voteRewardsFeeRate);
    vm.stopPrank();

    //compound VeTokenRewards success
    uint256 amountIn = 100 ether;

    //compound VoteRewards success
    vm.startPrank(compounder);
    deal(address(token), compounder, amountIn);
    uint256 beforeTotalFee = minter.totalFee();
    uint256 beforeTotalTokens = minter.totalTokens();
    uint256 beforeTotalRewards = minter.totalVoteRewards();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 beforeCompounderBalance = IERC20(token).balanceOf(compounder);

    IERC20(token).safeIncreaseAllowance(address(minter), amountIn);
    minter.compoundRewards(IMinter.RewardsType.VoteRewards, amountIn);

    uint256 afterTotalFee = minter.totalFee();
    uint256 afterTotalTokens = minter.totalTokens();
    uint256 afterTotalRewards = minter.totalVoteRewards();
    uint256 afterMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 afterCompounderBalance = IERC20(token).balanceOf(compounder);

    uint256 fee = (amountIn * voteRewardsFeeRate) / minter.DENOMINATOR();
    assertEq(afterTotalFee - beforeTotalFee, fee);
    assertEq(afterTotalTokens - beforeTotalTokens, amountIn - fee);
    assertEq(afterTotalRewards - beforeTotalRewards, amountIn - fee);
    assertEq(afterMinterBalance - beforeMinterBalance, fee);
    assertEq(beforeCompounderBalance - afterCompounderBalance, amountIn);

    uint256 assTokenTotalSupply = IERC20(assToken).totalSupply();
    //(tokens * totalSupply) / totalTokens
    assertEq(
      (1 ether * assTokenTotalSupply) / afterTotalTokens,
      minter.convertToAssTokens(1 ether)
    );

    //(assTokens * totalTokens) / totalSupply
    assertEq(
      (1 ether * afterTotalTokens) / assTokenTotalSupply,
      minter.convertToTokens(1 ether)
    );

    vm.stopPrank();
  }

  /**
   * @dev test compoundRewards
   */
  function testCompoundDonateRewardsSuccess() public {
    // Prepare Fee Ratio
    // (10_000 = 100%)
    uint256 donateRewardsFeeRate = 3000;

    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.Donate, donateRewardsFeeRate);
    vm.stopPrank();

    //compound VeTokenRewards success
    uint256 amountIn = 100 ether;

    //compound donateRewards success
    vm.startPrank(compounder);
    deal(address(token), compounder, amountIn);
    uint256 beforeTotalFee = minter.totalFee();
    uint256 beforeTotalTokens = minter.totalTokens();
    uint256 beforeTotalRewards = minter.totalDonateRewards();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 beforeCompounderBalance = IERC20(token).balanceOf(compounder);

    IERC20(token).safeIncreaseAllowance(address(minter), amountIn);
    minter.compoundRewards(IMinter.RewardsType.Donate, amountIn);

    uint256 afterTotalFee = minter.totalFee();
    uint256 afterTotalTokens = minter.totalTokens();
    uint256 afterTotalRewards = minter.totalDonateRewards();
    uint256 afterMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 afterCompounderBalance = IERC20(token).balanceOf(compounder);

    uint256 fee = (amountIn * donateRewardsFeeRate) / minter.DENOMINATOR();
    assertEq(afterTotalFee - beforeTotalFee, fee);
    assertEq(afterTotalTokens - beforeTotalTokens, amountIn - fee);
    assertEq(afterTotalRewards - beforeTotalRewards, amountIn - fee);
    assertEq(afterMinterBalance - beforeMinterBalance, fee);
    assertEq(beforeCompounderBalance - afterCompounderBalance, amountIn);

    uint256 assTokenTotalSupply = IERC20(assToken).totalSupply();
    //(tokens * totalSupply) / totalTokens
    assertEq(
      (1 ether * assTokenTotalSupply) / afterTotalTokens,
      minter.convertToAssTokens(1 ether)
    );

    //(assTokens * totalTokens) / totalSupply
    assertEq(
      (1 ether * afterTotalTokens) / assTokenTotalSupply,
      minter.convertToTokens(1 ether)
    );

    vm.stopPrank();
  }

  /**
   * @dev test compoundRewards
   */
  function testCompoundRewardsFail() public {
    //user no access
    vm.expectRevert();
    minter.compoundRewards(IMinter.RewardsType.VeTokenRewards, 1 ether);

    //Invalid amount
    vm.startPrank(compounder);
    vm.expectRevert("Invalid amount");
    minter.compoundRewards(IMinter.RewardsType.VeTokenRewards, 0);
    vm.stopPrank();
  }

  /**
   * @dev test updateFeeRate
   */
  function testUpdateFeeRate() public {
    //user no access
    vm.expectRevert();
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 1000);

    //Incorrect Fee Ratio
    vm.startPrank(manager);
    vm.expectRevert("Incorrect Fee Ratio");
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 10_0000);
    vm.stopPrank();

    //update VoteRewards(newFeeRate can not be equal oldFeeRate)
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 1_0000);
    vm.expectRevert("newFeeRate can not be equal oldFeeRate");
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 1_0000);
    vm.stopPrank();

    //update VeTokenRewards(newFeeRate can not be equal oldFeeRate)
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, 1_0000);
    vm.expectRevert("newFeeRate can not be equal oldFeeRate");
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, 1_0000);
    vm.stopPrank();

    //update Donate(newFeeRate can not be equal oldFeeRate)
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.Donate, 1_0000);
    vm.expectRevert("newFeeRate can not be equal oldFeeRate");
    minter.updateFeeRate(IMinter.RewardsType.Donate, 1_0000);
    vm.stopPrank();

    //update VoteRewards success
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 1000);
    assertEq(minter.voteRewardsFeeRate(), 1000);
    vm.stopPrank();

    //update VeTokenRewards success
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, 2000);
    assertEq(minter.veTokenRewardsFeeRate(), 2000);
    vm.stopPrank();

    //update Donate success
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.Donate, 3000);
    assertEq(minter.donateRewardsFeeRate(), 3000);
    vm.stopPrank();
  }

  /**
   * @dev test withdrawFee
   */
  function testWithdrawFee() public {
    address receipt = makeAddr("receipt");
    uint256 amountIn = 1 ether;
    //user no access
    vm.expectRevert();
    minter.withdrawFee(receipt, amountIn);

    //receipt is null
    vm.startPrank(manager);
    vm.expectRevert("Invalid address");
    minter.withdrawFee(address(0), amountIn);
    vm.stopPrank();

    //amountIn=0
    vm.startPrank(manager);
    vm.expectRevert("Invalid amount");
    minter.withdrawFee(receipt, 0);
    vm.stopPrank();

    //amountIn > totalFee
    vm.startPrank(manager);
    uint256 totalFee = minter.totalFee();
    vm.expectRevert("Invalid amount");
    minter.withdrawFee(receipt, totalFee + 1);
    vm.stopPrank();

    //withdrawFee success
    //prepare fee
    testCompoundVoteRewardsSuccess();
    vm.startPrank(manager);

    uint256 beforeTotalFee = minter.totalFee();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 beforeReceiptBalance = IERC20(token).balanceOf(receipt);

    amountIn = beforeTotalFee;
    minter.withdrawFee(receipt, amountIn);

    uint256 afterTotalFee = minter.totalFee();
    uint256 afterMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 afterReceiptBalance = IERC20(token).balanceOf(receipt);

    assertEq(beforeTotalFee - afterTotalFee, amountIn);
    assertEq(beforeMinterBalance - afterMinterBalance, amountIn);
    assertEq(afterReceiptBalance - beforeReceiptBalance, amountIn);

    vm.stopPrank();
  }

  /**
   * @dev test changePancakeSwapRouter
   */
  function testChangePancakeSwapRouter() public {
    address pancakeSwapRouterAddress = makeAddr("PancakeSwapRouter");
    //user no access
    vm.expectRevert();
    minter.changePancakeSwapRouter(pancakeSwapRouterAddress);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_pancakeSwapRouter is the zero address");
    minter.changePancakeSwapRouter(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    minter.changePancakeSwapRouter(pancakeSwapRouterAddress);
    assertEq(minter.pancakeSwapRouter(), pancakeSwapRouterAddress);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(minter.pancakeSwapRouter(), pancakeSwapRouterAddress);
    vm.expectRevert("_pancakeSwapRouter is the same");
    minter.changePancakeSwapRouter(pancakeSwapRouterAddress);
    vm.stopPrank();
  }

  /**
   * @dev test changePancakeSwapPool
   */
  function testChangePancakeSwapPool() public {
    address pancakeSwapPoolAddress = makeAddr("PancakeSwapPool");
    //user no access
    vm.expectRevert();
    minter.changePancakeSwapPool(pancakeSwapPoolAddress);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_pancakeSwapPool is the zero address");
    minter.changePancakeSwapPool(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    minter.changePancakeSwapPool(pancakeSwapPoolAddress);
    assertEq(minter.pancakeSwapPool(), pancakeSwapPoolAddress);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(minter.pancakeSwapPool(), pancakeSwapPoolAddress);
    vm.expectRevert("_pancakeSwapPool is the same");
    minter.changePancakeSwapPool(pancakeSwapPoolAddress);
    vm.stopPrank();
  }

  /**
   * @dev test testChangeMaxSwapRatio
   */
  function testChangeMaxSwapRatio() public {
    uint256 maxSwapRatio = 99;
    //user no access
    vm.expectRevert();
    minter.changeMaxSwapRatio(maxSwapRatio);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("Invalid max swap ratio");
    minter.changeMaxSwapRatio(10_0000);
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    minter.changeMaxSwapRatio(maxSwapRatio);
    assertEq(minter.maxSwapRatio(), maxSwapRatio);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    if (minter.maxSwapRatio() != maxSwapRatio) {
      minter.changeMaxSwapRatio(maxSwapRatio);
    }
    assertEq(minter.maxSwapRatio(), maxSwapRatio);

    vm.expectRevert("_maxSwapRatio is the same");
    minter.changeMaxSwapRatio(maxSwapRatio);
    vm.stopPrank();
  }

  /**
   * @dev test Flips the pause state
   */
  function testTogglePause() public {
    //user no access
    vm.expectRevert();
    minter.togglePause();

    //togglePause success
    vm.startPrank(admin);
    bool paused = minter.paused();
    minter.togglePause();
    assertEq(minter.paused(), !paused);
    vm.stopPrank();
  }

  /**
   * @dev test pause the contract
   */
  function testPause() public {
    //user no access
    vm.expectRevert();
    minter.pause();

    //pauser no access
    vm.startPrank(pauser);
    vm.expectRevert();
    minter.togglePause();
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    minter.grantRole(minter.DEFAULT_ADMIN_ROLE(), pauser);
    vm.stopPrank();

    //togglePause success
    vm.startPrank(pauser);
    minter.togglePause();
    assertEq(minter.paused(), true);
    vm.stopPrank();
  }

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
