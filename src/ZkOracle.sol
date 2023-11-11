// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

/**
 * @title Lido wstETH zkOracle Testnet Version
 * @dev This is a trustless oracle proof-of-concept that implements  L1 state queries and consensus layer queries via
 * Succinct Labs' Telepathy client to calculate the price of wstETH and compare it against the internally reported rate.
 * 
 * @author Unstable Team, Succinct Labs Team, UnshETH Team
 */

import {ILightClient} from "./interfaces/ILightClient.sol";
import {IFunctionGateway} from "./interfaces/IFunctionGateway.sol";
import {IMulticall3} from "./interfaces/IMulticall3.sol";
import {IStETH} from "./interfaces/IStETH.sol";

contract ZkOracle {

    mapping(uint256 => uint256) public requestBlockTimestamps;
    mapping(uint256 => uint256) public updateBlockTimestamps;
    mapping(uint256 => uint256) public nonceRequestIds;
    mapping(uint256 => uint64) public requestResults;
    mapping(uint256 => uint64) public exitedValidators;
    mapping(uint256 => uint64) public blockNumbers;

    struct LidoState {
        uint256 totalPooledEther;
        uint256 bufferedEther;
        uint256 depositedValidators;
        uint256 beaconValidators;
        uint256 beaconBalance;
        uint256 totalShares;
    }

    LidoState public latestState;

    mapping(uint256 => uint256) public blockNumberBySlot; 
    bool internal callback1Status;
    bool internal callback2Status;

    uint256 public lastUpdateTime;

    address public constant LIGHT_CLIENT = 0xaa1383Ee33c81Ef2274419dd5e0Ea5cCe4baF6cC;
    address public constant MULTICALL = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    /// @notice The address of the function gateway.
    address public constant FUNCTION_GATEWAY = 0x6e4f1e9eA315EBFd69d18C2DB974EEf6105FB803;

    /// @notice The function id of the consensus oracle.
    bytes32 public constant TVL_FUNCTION_ID = 0x63a29a77f155fc4c4d575fab7443c02732040a3389c213383c2f50c70c01fbc6;

    bytes32 public constant CALL_FUNCTION_ID = 0x8badf00d;

    /// @notice The nonce of the oracle.
    uint256 public nonce = 0;
    uint32 public eth_chainId = 1;
    uint256 public latestNonceWithResults;

    /// @dev The event emitted when a callback is received.
    event ZkTVLOracleV1Update(uint256 requestId, uint256 zkPrice, uint256 reportedPrice);

    /// @dev A helper function to read three uint64s from a bytes array.
    function readThreeUint64s(bytes memory _output) internal pure returns (uint64, uint64, uint64) {
        require(_output.length >= 24, "Array too short");

        uint64 value1;
        uint64 value2;
        uint64 value3;
        assembly {
            // Load the first 32 bytes (256 bits), then shift right by 192 bits to get the first 64 bits
            value1 := shr(192, mload(add(_output, 0x20)))

            // Load the next 32 bytes, then shift right to get the second 64-bit value
            value2 := shr(192, mload(add(_output, 0x28)))

            // Load the last 32 bytes, then shift right to get the third 64-bit value
            value3 := shr(192, mload(add(_output, 0x30)))
        }
        return (value1, value2, value3);
    }



    function slotToBlockNumber(uint256 slot) public view returns (uint256) {
        return blockNumberBySlot[slot];
    }

    function updateBlockNumberForSlot(uint256 slot, uint256 blockNumber) external {
        //TODO: check msg.sender in prod
        blockNumberBySlot[slot] = blockNumber;
    }

    function getBatchCalls()
    internal 
    pure 
    returns (IMulticall3.Call[] memory) {
        uint256 numcalls = 4; 
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](numcalls);
        calls[0] = IMulticall3.Call({target: STETH, callData: abi.encodeWithSelector(IStETH.getTotalPooledEther.selector)});
        calls[1] = IMulticall3.Call({target: STETH, callData: abi.encodeWithSelector(IStETH.getBufferedEther.selector)});
        calls[2] = IMulticall3.Call({target: STETH, callData: abi.encodeWithSelector(IStETH.getBeaconStat.selector)});
        calls[3] = IMulticall3.Call({target: STETH, callData: abi.encodeWithSelector(IStETH.getTotalShares.selector)});
        return calls;
    }

    /// @notice The entrypoint for requesting an oracle update.
    function requestUpdate() external payable {
        // Ensure that at least 12 hours have passed since the last update
        require(block.timestamp > lastUpdateTime + 12 hours, "insufficient elapsed time");
        (callback1Status, callback2Status) = (false, false);
        uint256 head = ILightClient(LIGHT_CLIENT).head();
        bytes32 blockRoot = ILightClient(LIGHT_CLIENT).headers(head);
        uint256 blockNumber = slotToBlockNumber(head);
        
        //we need two updates here: validator balances, and L1 multicall
        IFunctionGateway(FUNCTION_GATEWAY).requestCallback{value: msg.value/2}(
            TVL_FUNCTION_ID,
            abi.encodePacked(blockRoot),
            abi.encode(nonce),
            this.handleCallback1.selector,
            300000
        );
        IMulticall3.Call[] memory calls = getBatchCalls();
        IFunctionGateway(FUNCTION_GATEWAY).requestCallback{value: msg.value/2}(
            CALL_FUNCTION_ID, 
            abi.encode(eth_chainId, blockNumber, address(0), MULTICALL, abi.encodeWithSelector(IMulticall3.aggregate.selector, calls)),
            abi.encode(nonce),
            this.handleCallback2.selector, 
            2000000
        );

        requestBlockTimestamps[nonce] = block.timestamp;
        nonce++;
        lastUpdateTime = block.timestamp; //last update time = last time the update was REQUESTED, not necessarily fulfilled
    }

    /// @notice The callback function for the oracle.
    function handleCallback1(bytes memory output, bytes memory context) external {
        require(msg.sender == FUNCTION_GATEWAY);
        uint256 requestId = abi.decode(context, (uint256));
        (uint64 tvl, uint64 numExitedValidators, uint64 blockNumber) = readThreeUint64s(output);

        requestResults[nonce] = tvl;
        updateBlockTimestamps[nonce] = block.timestamp;
        nonceRequestIds[nonce] = requestId;
        latestNonceWithResults = nonce;
        callback1Status = true;
        // Store the additional outputs
        exitedValidators[nonce] = numExitedValidators;
        blockNumbers[nonce] = blockNumber;
        //emit ZkTVLOracleV1Update(requestId, result);
    }

    function handleCallback2(bytes memory output, bytes memory context) external {
        //handle the response from the multicall here 
        require(msg.sender == FUNCTION_GATEWAY);
        uint256 requestId = abi.decode(context, (uint256));
        (, bytes[] memory response) = abi.decode(output, (uint256, bytes[]));
        uint256 pooledEther = abi.decode(response[0], (uint256));
        uint256 bufferedEther = abi.decode(response[1], (uint256));
        uint256[3] memory beaconStats = abi.decode(response[2], (uint256[3]));
        uint256 totalShares = abi.decode(response[3], (uint256));
        latestState.totalPooledEther = pooledEther;
        latestState.bufferedEther = bufferedEther;
        latestState.depositedValidators = beaconStats[0];
        latestState.beaconValidators = beaconStats[1];
        latestState.beaconBalance = beaconStats[2];
        latestState.totalShares = totalShares;
        callback2Status = true;
        ( uint256 zkp, uint256 rp) = comparePrices();
        emit ZkTVLOracleV1Update(requestId, zkp, rp);
    }

    function latestResultInfo() public view returns (uint64 result, uint256 requestId, uint256 requestTimestamp, uint256 updateTimestamp) {
        return (
            requestResults[latestNonceWithResults],
            nonceRequestIds[latestNonceWithResults],
            requestBlockTimestamps[latestNonceWithResults],
            updateBlockTimestamps[latestNonceWithResults]
        );
    }

    function latestResult() public view returns (uint64 result) {
        return requestResults[latestNonceWithResults];
    }

    function latestBlockNumber() public view returns (uint64 blockNo) {
        return blockNumbers[latestNonceWithResults];
    }

    function latestNumExitedValidators() public view returns (uint64 numvals) {
        return exitedValidators[latestNonceWithResults];
    }

    function compareBalances() public view returns (uint256 zkTVL, uint256 reportedTVL) {
        uint256 zktvl = uint256(requestResults[latestNonceWithResults])*1e9;
        return (zktvl, latestState.beaconBalance);
    }

    function comparePrices() public view returns (uint256 zkPrice, uint256 reportedPrice) {
        uint256 zkprice = 1e18*(uint256(latestResult())*1e19 + latestState.bufferedEther
        + (latestState.depositedValidators - latestState.beaconValidators)*32e18)/latestState.totalShares;
        uint256 reportedprice = 1e18*latestState.totalPooledEther/latestState.totalShares;
        return (zkprice, reportedprice);
    }

}
