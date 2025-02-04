// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PancakeProfile Contract interface
/// @notice for user to register profile on PancakeSwap
interface IPancakeProfile {
  function createProfile(
    uint256 _teamId,
    address _nftAddress,
    uint256 _tokenId
  ) external;
}
