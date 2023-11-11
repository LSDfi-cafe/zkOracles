// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title ZkTVL
 * @dev The ZkTVL contract is a zkOracle designed to provide trustless reporting of the sum of validator balances for a specified LSD (Lido stETH in this case).
 * It allows for periodic updates of the oracle, ensuring that the reported balances are always current.
 * The contract maintains a record of the latest balances, as well as the time of the last update.
 * This allows users to not only fetch the latest balances, but also to determine how "fresh" or "stale" a balance is.
 * @author Unstable Team, Succinct Labs Team, UnshETH Team
 */

import {ILightClient} from "./interfaces/ILightClient.sol";
import {IFunctionGateway} from "./interfaces/IFunctionGateway.sol";

contract ZkTVL {

    mapping(uint256 => uint256) public requestBlockTimestamps;
    mapping(uint256 => uint256) public updateBlockTimestamps;
    mapping(uint256 => uint256) public nonceRequestIds;
    mapping(uint256 => uint64) public requestResults;

    uint256 public lastUpdateTime;

    address public constant LIGHT_CLIENT = 0xaa1383Ee33c81Ef2274419dd5e0Ea5cCe4baF6cC;

    /// @notice The address of the function gateway.
    address public constant FUNCTION_GATEWAY = 0x6e4f1e9eA315EBFd69d18C2DB974EEf6105FB803;

    /// @notice The function id of the consensus oracle.
    bytes32 public constant FUNCTION_ID = 0xB0BABABE5deadbeef;

    /// @notice The nonce of the oracle.
    uint256 public nonce = 0;
    uint256 public latestNonceWithResults;

    /// @dev The event emitted when a callback is received.
    event ZkTVLOracleV1Update(uint256 requestId, uint64 tvl);

    /// @dev A helper function to read a uint64 from a bytes array.
    function readUint64(bytes memory _output) internal pure returns (uint64) {
        uint64 value;
        assembly {
            value := mload(add(_output, 0x08))
        }
        return value;
    }

    /// @notice The entrypoint for requesting an oracle update.
    function requestUpdate() external payable {
        // Ensure that at least 12 hours have passed since the last update
        uint256 head = ILightClient(LIGHT_CLIENT).head();
        bytes32 blockRoot = ILightClient(LIGHT_CLIENT).headers(head);
        require(block.timestamp > lastUpdateTime + 12 hours, "insufficient elapsed time");

        IFunctionGateway(FUNCTION_GATEWAY).requestCallback{value: msg.value}(
            FUNCTION_ID,
            abi.encodePacked(blockRoot),
            abi.encode(nonce),
            this.handleCallback.selector,
            300000
        );
        requestBlockTimestamps[nonce] = block.timestamp;
        nonce++;
        lastUpdateTime = block.timestamp; //last update time = last time the update was REQUESTED, not necessarily fulfilled
    }

    /// @notice The callback function for the oracle.
    function handleCallback(bytes memory output, bytes memory context) external {
        require(msg.sender == FUNCTION_GATEWAY);
        uint256 requestId = abi.decode(context, (uint256));
        uint64 result = readUint64(output);

        requestResults[nonce] = result;
        updateBlockTimestamps[nonce] = block.timestamp;
        nonceRequestIds[nonce] = requestId;
        latestNonceWithResults = nonce;
        emit ZkTVLOracleV1Update(requestId, result);
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

}
