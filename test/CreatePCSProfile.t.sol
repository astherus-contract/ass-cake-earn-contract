// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";

/** cmd:
 forge clean && \
 forge build --via-ir && \
 forge test -vvvv --match-contract CreatePCSProfileTest --via-ir
*/

interface IPancakeProfile {
  function createProfile(uint256 _teamId, address _nftAddress, uint256 _tokenId) external;

  function getUserProfile(
    address _userAddress
  )
    external
    view
    returns (uint256 userId, uint256 numberPoints, uint256 teamId, address nftAddress, uint256 tokenId, bool isActive);
}

contract CreatePCSProfileTest is Test {
  using SafeERC20 for IERC20;

  address manager = 0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f;
  address timelock = 0xB83446F74CaD1E9F9A367F9222c0785DD670434b;
  address deployer = 0x5b634EdF9d2A83Aa2FfA82b33dEa4750A32451E1;
  address nftAddress = 0xDf7952B35f24aCF7fC0487D01c8d5690a60DBa07;
  address pancakeProfile = 0xDf4dBf6536201370F95e06A0F8a7a70fE40E388a;
  address CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

  // production universal proxy
  UniversalProxy universalProxy = UniversalProxy(address(0x8E6Ce60cbC6402B8b780AdCfc069A00c177D2B18));

  function setUp() public {
    // fork mainnet
    vm.createSelectFork("https://bsc-mainnet.nodereal.io/v1/1f16d77226f44d7680a25a1ed4c534e0");
  }

  function test_createProfile() public {
    // back to block 45820778
    vm.roll(45814301);

    // upgrade universal proxy
    vm.startPrank(timelock);

    address _newImpl = address(new UniversalProxy());
    address proxyAddress = address(universalProxy);
    universalProxy.upgradeToAndCall(_newImpl, "");
    vm.stopPrank();

    // set pancakeProfile
    vm.prank(manager);
    universalProxy.setPancakeProfile(pancakeProfile);

    // transfer NFT
    vm.prank(deployer);
    IERC721(nftAddress).safeTransferFrom(deployer, address(universalProxy), 994670);

    // setup profile
    vm.prank(manager);
    universalProxy.createProfile(3, nftAddress, 994670);

    (
      uint256 userId,
      uint256 numberPoints,
      uint256 teamId,
      address _nftAddress,
      uint256 tokenId,
      bool isActive
    ) = IPancakeProfile(pancakeProfile).getUserProfile(address(universalProxy));
    console.log("userId: %d", userId);
    console.log("numberPoints: %d", numberPoints);
    console.log("teamId: %d", teamId);
    console.log("nftAddress: %s", _nftAddress);
    console.log("tokenId: %d", tokenId);
    console.log("isActive: %s", isActive);

    /*
    // will not work as point won't update during mock

    // IFO start
    vm.roll(45957443);
    // set IFO address
    vm.prank(manager);
    universalProxy.setIFO(0x4F045CD0C3293845e0A0460fA64caC5d59b4Dc37);

    // give manager 1000 CAKE
    deal(CAKE, manager, 1000 ether);

    bytes4 err = bytes4(keccak256(bytes("MustHaveAnActiveProfile()")));
    console.logBytes4(err);
    bytes4 err1 = bytes4(keccak256(bytes("PoolNotSet()")));
    console.logBytes4(err1);
    bytes4 err2 = bytes4(keccak256(bytes("TooEarly()")));
    console.logBytes4(err2);
    bytes4 err3 = bytes4(keccak256(bytes("TooLate()")));
    console.logBytes4(err3);
    bytes4 err4 = bytes4(keccak256(bytes("AmountMustExceedZero()")));
    console.logBytes4(err4);


    // join IFO with 1000 CAKE
    vm.startPrank(manager);
    IERC20(CAKE).safeIncreaseAllowance(address(universalProxy), 1000 ether);
    vm.roll(45957443);
    vm.warp(1737453608);
    // log timestamp
    console.log("timestamp: %d", block.timestamp);
    universalProxy.depositIFO(1, 1000 ether);
    vm.stopPrank();
    */
  }
}
