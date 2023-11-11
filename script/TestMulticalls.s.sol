pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
//import {ZkLens} from "../src/ZkLens.sol";
import {IMulticall3} from "../src/interfaces/IMulticall3.sol";
import {IStETH} from "../src/interfaces/IStETH.sol";

interface IDarknet {
    function checkPrice(address lsd) external view returns (uint256);
}

contract TestGetBatchCallsScript is Script {

    struct LidoState {
        uint256 totalPooledEther;
        uint256 bufferedEther;
        uint256 depositedValidators;
        uint256 beaconValidators;
        uint256 beaconBalance;
        uint256 totalShares;
    }

    LidoState public latestState;
    
    bool internal test;

    address public constant sfrxETHAddress = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant rETHAddress = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant wstETHAddress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant cbETHAddress = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address public constant wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ankrETHAddress = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address public constant swETHAddress = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address public constant unshETHAddress = 0x0Ae38f7E10A43B5b2fB064B42a2f4514cbA909ef;

    address public constant MULTICALL = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public constant DARKNET = 0x34f969E2c9D7f8bf1E537889949390d4a756270A;

    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address[7] public lsdaddresses = [sfrxETHAddress, rETHAddress, wstETHAddress, cbETHAddress, wethAddress, ankrETHAddress, swETHAddress];

    function setUp() public {
    }

    function getBatchStateCalls()
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

    function getBatchCalls(address[7] memory addresses) 
        internal
        virtual
        returns (IMulticall3.Call[] memory) {
        
        uint256 length = lsdaddresses.length;
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](length);
        for (uint256 i = 0; i < length; ++i) {
            calls[i] = IMulticall3.Call({target: DARKNET, callData: abi.encodeWithSelector(IDarknet.checkPrice.selector, addresses[i])});
        }
        return calls;

    }

    function bytesToString(bytes memory byteData) public pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + byteData.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < byteData.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(byteData[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(byteData[i] & 0x0f))];
        }
        return string(str);
    }

    function bytesArrayToString(bytes[] memory byteDataArray) public pure returns (string[] memory) {
        string[] memory strArray = new string[](byteDataArray.length);
        for (uint i = 0; i < byteDataArray.length; i++) {
            strArray[i] = bytesToString(byteDataArray[i]);
        }
        return strArray;
    }

    function bytesArrayToUintArray(bytes[] memory byteDataArray) public pure returns (uint256[] memory) {
        uint256[] memory uintArray = new uint256[](byteDataArray.length);
        for (uint i = 0; i < byteDataArray.length; i++) {
            uintArray[i] = abi.decode(byteDataArray[i], (uint256));
    }
        return uintArray;
    }

    function run() public {

        IMulticall3.Call[] memory calls = getBatchStateCalls();

        for (uint256 i = 0; i < calls.length; i++) {
            IMulticall3.Call memory currentCall = calls[i];
            console2.log("Call ", i);
            console2.log("Target: ", currentCall.target);
            console2.log("Call data: ", bytesToString(currentCall.callData));
        }  

        bytes memory finalCalldata = abi.encodeWithSelector(IMulticall3.aggregate.selector, calls);
        console2.log("Final calldata: ", bytesToString(finalCalldata));

        (, bytes[] memory response) = IMulticall3(MULTICALL).aggregate(calls);

        string[] memory responseStringArray = bytesArrayToString(response);

        for (uint i = 0; i < responseStringArray.length; i++) {
            console2.log("Response string ", i, ": ", responseStringArray[i]);
        }

        uint256 pooledEther = abi.decode(response[0], (uint256));
        uint256 bufferedEther = abi.decode(response[1], (uint256));
        uint256[3] memory beaconStats = abi.decode(response[2], (uint256[3]));
        uint256 totalShares = abi.decode(response[3], (uint256));
        console2.log("pooledEther: ", pooledEther);
        console2.log("bufferedEther: ", bufferedEther);
        console2.log("beaconStats: ", beaconStats[0], beaconStats[1], beaconStats[2]);
        console2.log("totalShares: ", totalShares);

        latestState.totalPooledEther = pooledEther;
        latestState.bufferedEther = bufferedEther;
        latestState.depositedValidators = beaconStats[0];
        latestState.beaconValidators = beaconStats[1];
        latestState.beaconBalance = beaconStats[2];
        latestState.totalShares = totalShares;

        console2.log("latestState.totalPooledEther: ", latestState.totalPooledEther);
        console2.log("latestState.bufferedEther: ", latestState.bufferedEther);
        console2.log("latestState.depositedValidators: ", latestState.depositedValidators);
        console2.log("latestState.beaconValidators: ", latestState.beaconValidators);
        console2.log("latestState.beaconBalance: ", latestState.beaconBalance);
        console2.log("latestState.totalShares: ", latestState.totalShares);
        test = true;

        // zkState Calls:    
        // IMulticall3.Call[] memory calls = getBatchCalls(lsdaddresses);

        // for (uint256 i = 0; i < calls.length; i++) {
        //     IMulticall3.Call memory currentCall = calls[i];
        //     console2.log("Call ", i);
        //     console2.log("Target: ", currentCall.target);
        //     console2.log("Call data: ", bytesToString(currentCall.callData));
        // }

        // bytes memory finalCalldata = abi.encodeWithSelector(IMulticall3.aggregate.selector, calls);
        // console2.log("Final calldata: ", bytesToString(finalCalldata));

        // (, bytes[] memory response) = IMulticall3(MULTICALL).aggregate(calls);

        // string[] memory responseStringArray = bytesArrayToString(response);

        // for (uint i = 0; i < responseStringArray.length; i++) {
        //     console2.log("Response string ", i, ": ", responseStringArray[i]);
        // }

        // uint256[] memory responseUintArray = bytesArrayToUintArray(response);

        // for (uint i = 0; i < responseUintArray.length; i++) {
        //     console2.log("Response uint ", i, ": ", responseUintArray[i]);
        // }
    }
}