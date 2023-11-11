source ../.env
forge create src/ZkOracle.sol:ZkOracle \
    --rpc-url $RPC_5 \
    --private-key $PRIVATE_KEY \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_5