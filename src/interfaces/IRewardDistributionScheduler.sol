// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RewardDistributionScheduler interface
interface IRewardDistributionScheduler {
    function addRewardsSchedule(uint16 _type, uint16 _amount, uint256 _epochs, uint256 _startTime) external;

    function executeRewardSchedules() external;
}
