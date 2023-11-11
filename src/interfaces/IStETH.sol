//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IStETH {
    function getBeaconStat() external view returns (uint256 depositedValidators, uint256 beaconValidators, uint256 beaconBalance);
    function getTotalShares() external view returns (uint256);
    function getFee() external view returns (uint16);
    function getBufferedEther() external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function getDepositableEther() external view returns (uint256);
    function getTotalELRewardsCollected() external view returns (uint256);
}