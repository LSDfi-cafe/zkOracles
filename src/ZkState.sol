// SPDX-License-Identifier: NO-LICENSE
pragma solidity ^0.8.16;



//         __       ______   _________     _     _________  ________  
//        [  |  _ .' ____ \ |  _   _  |   / \   |  _   _  ||_   __  | 
//  ____   | | / ]| (___ \_||_/ | | \_|  / _ \  |_/ | | \_|  | |_ \_| 
// [_   ]  | '' <  _.____`.     | |     / ___ \     | |      |  _| _  
//  .' /_  | |`\ \| \____) |   _| |_  _/ /   \ \_  _| |_    _| |__/ | 
// [_____][__|  \_]\______.'  |_____||____| |____||_____|  |________| 

/**
 * @title ZkState
 * @dev The ZkState contract is a zkOracle designed to provide up-to-date fair value rates and supply counts for various LSD tokens on L2s.
 * It allows for periodic updates of the oracle, ensuring that the prices are always current.
 * The contract maintains a record of the latest prices for each LSD token, as well as the time of the last update.
 * This allows users to not only fetch the latest prices, but also to determine how "fresh" or "stale" a price is.
 * Note that these prices are meant to be used in tandem with zkTVL oracle-reported validator balances to ensure integrity
 * @author Unstable Team, Succinct Labs Team, UnshETH Team
 */

import {IMulticall3} from "./interfaces/IMulticall3.sol";

interface IFunctionGateway {
    function requestCallback(
        bytes32 _functionId,
        bytes memory _input,
        bytes memory _context,
        bytes4 _callbackSelector,
        uint32 _callbackGasLimit
    ) external payable returns (bytes32);

    function isCallback() external view returns (bool);
}

interface IDarknet {
    function checkPrice(address lsd) external view returns (uint256);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
}

contract ZkState {
    mapping(address => uint96) indexByLsd;

    mapping(address => uint256) latestLsdPrice;
    mapping(address => uint256) latestSupply;
    
    uint256 public lastUpdateTime;
    uint256 public lastUpdateBlock;

    address public constant sfrxETHAddress = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant rETHAddress = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant wstETHAddress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant cbETHAddress = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address public constant wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ankrETHAddress = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address public constant swETHAddress = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    //address public constant ethxAddress = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address public constant unshETHAddress = 0x0Ae38f7E10A43B5b2fB064B42a2f4514cbA909ef;
    address public constant stETHAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address[7] public lsds = [sfrxETHAddress, rETHAddress, wstETHAddress, cbETHAddress, wethAddress, ankrETHAddress, swETHAddress];

    address public constant FUNCTION_GATEWAY = 0x6e4f1e9eA315EBFd69d18C2DB974EEf6105FB803;
    address public constant MULTICALL = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public constant DARKNET = 0x34f969E2c9D7f8bf1E537889949390d4a756270A;

    bytes32 public constant FUNCTION_ID = 0xf628b95dfeae87ea7313695eb53fe0a10a26fdaf131e85106bb3b5d1bbf2e3f8;
    uint256 public nonce = 0;
    uint32 public eth_chainId = 1;

    event ZkStateOracleUpdate(uint256 lastUpdateTime, uint256 lastUpdateBlock, uint256 requestId);


    /**
     * @notice Requests an update of LSD token prices.
     * @dev This function prepares a batch of calls to the DARKNET contract to check the price of each LSD token.
     * It then sends these calls to the function gateway, which will execute them and return the results in a callback.
     * @param blockNumber The block number to be used in the function gateway request.
     */
    function requestUpdate(uint64 blockNumber) external payable {
        // Ensure that at least 12 hours have passed since the last update
        require(block.timestamp > lastUpdateTime + 12 hours, "insufficient elapsed time");

        // Prepare a batch of calls to the DARKNET contract to check the price of each LSD token
        IMulticall3.Call[] memory calls = getBatchCalls();
        
        // Request a callback from the function gateway
        // The function gateway will execute the batch of calls and return the results in a callback
        // The callback function to be called is this contract's handleCallback function
        // The gas limit for the callback is set to 2,000,000
        IFunctionGateway(FUNCTION_GATEWAY).requestCallback{value: msg.value}(
            FUNCTION_ID,
            // The input to the function gateway includes the Ethereum chain ID, the block number, the address of the multicall contract, and the encoded batch of calls
            abi.encode(eth_chainId, blockNumber, address(0), MULTICALL, abi.encodeWithSelector(IMulticall3.aggregate.selector, calls)),
            // The context provided to the function gateway is the current nonce
            abi.encode(nonce),
            // The selector of the callback function
            this.handleCallback.selector,
            // The gas limit for the callback
            2000000
        );
        // Increment the nonce
        nonce++;
    }
    /**
     * @notice Converts an array of bytes to an array of uint256.
     * @param byteDataArray The input array of bytes.
     * @return uintArray The output array of uint256.
     */
    function bytesArrayToUintArray(bytes[] memory byteDataArray) public pure returns (uint256[] memory) {
        uint256[] memory uintArray = new uint256[](byteDataArray.length);
        for (uint i = 0; i < byteDataArray.length; i++) {
            uintArray[i] = abi.decode(byteDataArray[i], (uint256));
    }
        return uintArray;
    }

    /**
     * @notice Handles the callback from the function gateway.
     * @param output The output from the function gateway.
     * @param context The context provided to the function gateway.
     */
    function handleCallback(bytes memory output, bytes memory context) external {
        // Ensure the callback is from the function gateway
        require(msg.sender == FUNCTION_GATEWAY && IFunctionGateway(FUNCTION_GATEWAY).isCallback());

        // Decode the requestId from the context
        uint256 requestId = abi.decode(context, (uint256));
        uint256 len = lsds.length;
        // Decode the response from the output
        (, bytes[] memory response) = abi.decode(output, (uint256, bytes[]));

        for (uint i = 0; i < len; i++) {
            latestLsdPrice[lsds[i]] = abi.decode(response[i], (uint256));
            latestSupply[lsds[i]] = abi.decode(response[i + len], (uint256));
        }

        // old logic: 
        // Convert the response bytes array to two uint256 arrays
        // uint256[] memory latestPrices = new uint256[](lsds.length);
        // uint256[] memory latestSupplies = new uint256[](lsds.length);
        // for (uint i = 0; i < lsds.length; i++) {
        //     latestPrices[i] = abi.decode(response[i], (uint256));
        //     latestSupplies[i] = abi.decode(response[i + lsds.length], (uint256));
        // }

        // //@dev: this can likely be condensed into the previous loop 
        // // Update the latest prices for each LSD token
        // for (uint i = 0; i < lsds.length; i++) {
        //     latestLsdPrice[lsds[i]] = latestPrices[i];
        //     latestSupply[lsds[i]] = latestSupplies[i];
        // }

        // Update the time and block of the last update
        lastUpdateTime = block.timestamp;
        lastUpdateBlock = block.number;

        // Emit an event for the update
        emit ZkStateOracleUpdate(lastUpdateTime, lastUpdateBlock, requestId);
    }

    /**
     * @notice This function prepares a batch of calls to the DARKNET contract to check the price of each LSD token.
     * @dev It creates an array of IMulticall3.Call structs, each containing the target contract address and the encoded function call.
     * @return calls An array of IMulticall3.Call structs ready to be passed to the multicall function.
     */
    function getBatchCalls() 
        internal
        view
        returns (IMulticall3.Call[] memory) {
        
        // Get the number of LSD tokens
        uint256 numcalls = 2*lsds.length;
        uint256 len = lsds.length;
        // Initialize an array of IMulticall3.Call structs with the same length
        //IMulticall3.Call[] memory calls = new IMulticall3.Call[](length);
        
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](numcalls); //make it twice the length

        // For each LSD token, prepare a call to the DARKNET contract's checkPrice function
        uint256 i;
        for (i = 0; i < len; ++i) {
            // The callData is the encoded function selector and the LSD token address
            address lsdAddr = lsds[i] == wstETHAddress ? stETHAddress : lsds[i]; //need to use stETH address for lido supply
            calls[i] = IMulticall3.Call({target: DARKNET, callData: abi.encodeWithSelector(IDarknet.checkPrice.selector, lsds[i])});
            calls[i+len] = IMulticall3.Call({target: lsdAddr, callData: abi.encodeWithSelector(IERC20.totalSupply.selector)});
            //store the totalSupply calls 

        }

        //Now store the totalSupply calls
        // for (uint j = i; j < length; ++j) {
        //     calls[j] = IMulticall3.Call({target: lsds[i], callData: abi.encodeWithSelector(IERC20.totalSupply.selector)});
        // }

        // Return the array of calls
        return calls;

    }

    function getPrice(address lsd) public view returns (uint256) {
        return getPriceWithTimeThreshold(lsd, 0);
    }

    function getSupply(address lsd) public view returns (uint256) {
        return getSupplyWithTimeThreshold(lsd, 0);
    }

    /**
     * @notice Fetches the price of a given LSD token, ensuring the price is not stale.
     * @dev If the time threshold is not provided or is zero, a default value of 1 day is used.
     * @param lsd The address of the LSD token.
     * @param timeThreshold The maximum age of the price information in seconds.
     * @return The latest price of the LSD token.
     */
    function getPriceWithTimeThreshold(address lsd, uint256 timeThreshold) public view returns (uint256) {
        uint256 timeThresholdToUse = timeThreshold == 0 ? 1 days : timeThreshold;
        require(lastUpdateTime > block.timestamp - timeThresholdToUse, "Last update is stale, request new update");
        return latestLsdPrice[lsd];
    }

    /**
     * @notice Fetches the supply of a given LSD token, ensuring the supply is not stale.
     * @dev If the time threshold is not provided or is zero, a default value of 1 day is used.
     * @param lsd The address of the LSD token.
     * @param timeThreshold The maximum age of the supply information in seconds.
     * @return The latest supply of the LSD token.
     */
    function getSupplyWithTimeThreshold(address lsd, uint256 timeThreshold) public view returns (uint256) {
        uint256 timeThresholdToUse = timeThreshold == 0 ? 1 days : timeThreshold;
        require(lastUpdateTime > block.timestamp - timeThresholdToUse, "Last update is stale, request new update");
        return latestSupply[lsd];
    }

}