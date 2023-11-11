# ZkOracles: zkTVL + zkState

Welcome to the official repository for ZkOracles powered by Succinct's Telepathy client. This proof-of-concept demonstrates the functionality of trustless oracles employing zk-SNARKs to ensure accurate, decentralized reporting of validator balances and LSD internal rates. These can then be combined to build a fully functional trustless price oracle for assets such as LSDs. An example of such a price oracle is provided for Lido wstETH. 

![zkOracles](https://i.imgur.com/dC95F6k.jpg)

## Overview

This repository contains three contracts: 

1. **`zkTVL`**: Provides a trustless sum of validator balances on the consensus layer for a given LSD, provided it has a single withdrawal address.
2. **`zkState`**: Supplies trustless, fair value rates, and total supplies of LSDs on various Layer 2 platforms.
3. **`zkOracle`**: An example that combines Consensus layer queries and L1 state queries to create a trustless oracle for Lido wstETH. 

The `circuits` folder contains two circuits that can be deployed with the Succinct SDK: 
* `v1.rs`: This circuit, built with plonky2x calculates the total Lido reserves, number of validators deposited, and number of validators exited
* `mock.rs`: This is a mock version of `v1` that returns the same data as the circuit which can be used to test contract interactions cheaply
  


## Installation and Build Instructions

To get started, make sure you have Rust, Cargo, and Foundry installed. 

```shell
curl https://sh.rustup.rs -sSf | sh
curl -L https://foundry.paradigm.xyz | bash
```

### Building the Project

Clone the repository and install the necessary dependencies:

```shell
git clone [Insert Repository URL Here]
cd ZkOracles
forge install
cargo install
```

If you want to test the circuit locally, remove the `include_v1_tests` flag under `[features]` in `Cargo.tml` and set `NB_VALIDATORS=1024` in `v1.rs` to avoid long proving times. 

```shell
cargo build
cargo test -- --nocapture
```

Compile the smart contracts:

```shell
forge build
```

## Deployment

Before deployment, rename `env.example` to `.env` and make sure to set the following values: 
* `PRIVATE_KEY`: Private key of your deployer account
* `RPC_5`: Goerli testnet RPC 
* `ETHERSCAN_API_5`: Goerli Etherscan API key for verifying deployed contracts
* `MAINNET_RPC`: Mainnet RPC URL

In order to deploy your circuit via the Succinct SDK (currently in closed Alpha), you need to first create a new project:

1. Navigate to the [Create Project](https://alpha.succinct.xyz/new/project) page.
2. Follow the prompts to connect your GitHub and select your repo
3. Select the appropriate commit hash (`HEAD` by default) and select the `v1` entrypoint (or `mock` for testing contract interactions) to create a release
4. Navigate to `Releases` on your project page and select the latest release. Under `Deployments`, click Deploy and select a chain to deploy your `FunctionVerifier`
5. Once deployment is complete, go to the `Deployments` page for your project and find the `FUNCTION_ID` and `FUNCTION_GATEWAY` addresses.
6. Replace the `FUNTION_GATEWAY` and `TVL_FUNCTION_ID` values in `ZkOracle.sol` and/or `ZkTVL.sol` with the correct addresses for your deployment.  

Now, we can deploy the oracle contracts on Goerli.

1. Ensure you have `ETH` in a wallet that's Goerli testnet compatible.
2. Make sure your `.env` file is configured.
3. Deploy the Lido zkOracle:

```shell
cd script
chmod +x deploy_oracle.sh
./deploy_oracle.sh
```
This script will deploy `zkOracle.sol` to the Goerli testnet, and will verify the contract on Etherscan and return the deployment address. To deploy `zkState` or `zkTVL`, simply change the contract name in `script/deploy_oracle.sh`. 

## Testing

Once the contracts have been deployed, you can test the entire end-to-end flow for the `zkOracle` wstETH price calculation as follows: 

1. **Light Client Slot Update**:
   - Obtain the latest slot number reported by the `LightClient` by executing `LightClient.head()`.
   - Update the slot in your system by calling `updateBlockNumberForSlot(head, blockNumber)` with the retrieved slot number and corresponding block number.

2. **Requesting Oracle Update**:
   - Initiate an oracle update by calling `requestUpdate()` on the deployed contract with a transaction fee (0.02 Goerli ETH recommended).

3. **Proof Generation and Monitoring**:
   - Monitor the proof generation process via the Succinct Explorer or your project page on Succinct’s platform.
   - Wait for the system to generate and verify the zk-SNARK proof, which may take several minutes.

4. **Oracle Callback and Event Emission**:
   - The oracle contract will emit an update event once the callback function is successfully executed.

5. **Verification and Comparison**:
   - Verify the computed LSD price by calling `comparePrices()` on the contract.
   - This function will return the zk Circuit computed price and the internally reported price of the LSD in a tuple as `(uint256 zkPrice, uint256 reportedPrice)`

Remember to configure the LightClient's address in your contract before beginning tests and ensure that the Beaconscan API or equivalent service is accessible to fetch the latest slot number. Note that this step is only necessary for testing on Goerli and won't be required in production as the appropriate block number will be available on-chain. 





