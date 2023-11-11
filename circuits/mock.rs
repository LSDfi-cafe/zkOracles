//! An example of a basic EVM function which takes in on-chain input bytes and returns output bytes
//! that correspond to the result of an `eth_call`.
//!
//! To build the binary:
//!
//!     `cargo build --example eth_call --release`
//!
//! To build the function, which saves the verifier contract:
//!
//!     `./target/release/example/eth_call build`
//!
//! To generate the output and proof:
//!
//!    `./target/release/example/eth_call prove --input-json input.json`
//!

use std::env;

use ethers::middleware::Middleware;
use ethers::providers::{Http, Provider};
use ethers::types::transaction::eip2718::TypedTransaction;
use ethers::types::{Eip1559TransactionRequest, H160};
use ethers::utils::hex;
use rustx::function::RustFunction;
use rustx::program::Program;
use serde_json::Value;
use reqwest;
use alloy_sol_types::{sol, SolType};
use alloy_primitives::{address, bytes, fixed_bytes, FixedBytes};

type BlockRootRequestTuple = sol! { tuple(bytes32,)};
type BlockRootInput = sol ! {bytes32};

#[derive(Debug, Clone)]
struct LidoMock;

impl Program for LidoMock {
    fn run(input_bytes: Vec<u8>) -> Vec<u8> {
        // Updated TODOs post API update:
        // New endpoint: https://beaconapi-kd5nwjhq0.succinct.xyz/api/beacon/debug/lido/
        // Need to accept a BLOCK_ROOT as a parameter
        // eg. const BLOCK_ROOT: &str = "0x4f1dd351f11a8350212b534b3fca619a2a95ad8d9c16129201be4a6d73698adb";
        // Need to call  https://beaconapi-kd5nwjhq0.succinct.xyz/api/beacon/debug/lido/$BLOCK_ROOT
        // Response format looks like: {"tvl":8877126884153998,"nb_active_validators":276705,"nb_exited_validators":9695,"slot":7700480,"block":18509313}
        // Return response.tvl, response.nb_exited_validators, response.block

        //let block_root = String::from_hex(input_bytes).expect("Failed to parse input bytes to string");
        let block_root = BlockRootInput::abi_decode(&input_bytes, true).unwrap();
        //let block_root_str = hex::encode(block_root);
        println!("block_root: {}", block_root);
        let url = format!("https://beaconapi-kd5nwjhq0.succinct.xyz/api/beacon/debug/lido/{}", block_root);
        let response: serde_json::Value = reqwest::blocking::get(&url)
            .expect("Failed to send request")
            .json()
            .expect("Failed to parse response as JSON");

        let tvl = response["tvl"]
            .as_u64()
            .expect("Failed to parse tvl as u64");
        let nb_exited_validators = response["nb_exited_validators"]
            .as_u64()
            .expect("Failed to parse nb_exited_validators as u64");
        let block = response["block"]
            .as_u64()
            .expect("Failed to parse block as u64");

        let mut output = tvl.to_be_bytes().to_vec();
        output.extend_from_slice(&nb_exited_validators.to_be_bytes());
        output.extend_from_slice(&block.to_be_bytes());

        return output;
    }
}

fn main() {
    LidoMock::entrypoint();
}

#[cfg(test)]
mod tests {

    use super::*;
    //use alloy_primitives::{address, bytes};

    #[test]
    #[cfg_attr(feature = "ci", ignore)]
    fn test_call() {
        // Define the block root.
        let block_root_in: FixedBytes<32> = fixed_bytes!("7797dbd1eecad8fe38dd849c43b7ea9a6e9e656c968056415132be4e3bfcd4ed");
        let block_root: Vec<u8> = BlockRootInput::abi_encode(&block_root_in);

        let output = LidoMock::run(block_root);
        // Assert that the output matches.
        let tvl = u64::from_be_bytes(output[0..8].try_into().expect("Failed to parse tvl bytes to u64"));
        let nb_exited_validators = u64::from_be_bytes(output[8..16].try_into().expect("Failed to parse nb_exited_validators bytes to u64"));
        let block = u64::from_be_bytes(output[16..24].try_into().expect("Failed to parse block bytes to u64"));

        println!("tvl: {}", tvl);
        println!("nb_exited_validators: {}", nb_exited_validators);
        println!("block: {}", block);

        assert!(tvl > 0u64);
        assert!(nb_exited_validators > 0u64);
        assert!(block > 0u64);
    }
}
