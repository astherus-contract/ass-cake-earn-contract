// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { RewardDistributionScheduler } from "../src/RewardDistributionScheduler.sol";

contract RewardDistributionSchedulerScript is Script {
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: %s", deployer);
    address admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);
    address manager = vm.envOr("MANAGER", admin);
    console.log("Manager: %s", manager);
    address minter = vm.envOr("MINTER", admin);
    console.log("Minter: %s", minter);

    // token
    address token = vm.envAddress("TOKEN");
    require(token != address(0), "Token address cannot be null");
    console.log("Token: %s", token);

    vm.startBroadcast(deployerPrivateKey);
    address proxy = Upgrades.deployUUPSProxy(
      "RewardDistributionScheduler.sol",
      abi.encodeCall(RewardDistributionScheduler.initialize, (admin, token, minter, manager))
    );
    vm.stopBroadcast();
    console.log("RewardDistributionScheduler proxy address: %s", proxy);
    address implAddress = Upgrades.getImplementationAddress(proxy);
    console.log("RewardDistributionScheduler impl. address: %s", implAddress);
  }
}
