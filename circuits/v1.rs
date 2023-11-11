#![allow(clippy::needless_range_loop)]

use ethers::types::U64;
use itertools::Itertools;
use plonky2::plonk::config::{AlgebraicHasher, GenericConfig};
use plonky2x::backend::circuit::{Circuit, DefaultSerializer, PlonkParameters};
use plonky2x::backend::function::Plonky2xFunction;
use plonky2x::frontend::eth::beacon::vars::{BeaconBalancesVariable, BeaconValidatorsVariable};
use plonky2x::frontend::mapreduce::generator::MapReduceGenerator;
use plonky2x::frontend::uint::uint64::U64Variable;
use plonky2x::prelude::{Bytes32Variable, CircuitBuilder, HintRegistry};
use plonky2x::utils::bytes32;
use serde::{Deserialize, Serialize};

// The withdrawal credentials of Lido validators.
const LIDO_WITHDRAWAL_CREDENTIALS: &str =
    "0x010000000000000000000000b9d7934878b5fb9610b3fe8a5e441e8fad7e293f";

/// The number of balances to fetch.
const NB_VALIDATORS: usize = 1024;

/// The batch size for fetching balances and computing the local balance roots.
const BATCH_SIZE: usize = 512;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LidoOracleV2;

impl Circuit for LidoOracleV2 {
    fn define<L: PlonkParameters<D>, const D: usize>(builder: &mut CircuitBuilder<L, D>)
    where
        <<L as PlonkParameters<D>>::Config as GenericConfig<D>>::Hasher:
            AlgebraicHasher<<L as PlonkParameters<D>>::Field>,
    {
        let block_root = builder.evm_read::<Bytes32Variable>();
        let partial_validators = builder.beacon_get_partial_validators::<NB_VALIDATORS>(block_root);
        let partial_balances = builder.beacon_get_partial_balances::<NB_VALIDATORS>(block_root);
        let idxs = (0u64..(NB_VALIDATORS as u64)).collect_vec();

        let output = builder.mapreduce::<
            (BeaconValidatorsVariable, BeaconBalancesVariable),
            U64Variable,
            (Bytes32Variable, Bytes32Variable, U64Variable),
            DefaultSerializer,
            BATCH_SIZE,
            _,
            _,
        >(
            (partial_validators, partial_balances),
            idxs,
            |(validators_root, balances_root), idxs, builder| {
                // Witness validators.
                let (validator_roots, validators) =
                    builder.beacon_witness_compressed_validator_batch::<BATCH_SIZE>(
                        validators_root,
                        idxs[0]
                    );

                // Witness balances.
                let balances = builder.beacon_witness_balance_batch::<BATCH_SIZE>(
                    balances_root,
                    idxs[0]
                );

                // Convert validators to leafs.
                let lido_withdrawal_credentials = builder.constant::<Bytes32Variable>(
                    bytes32!(LIDO_WITHDRAWAL_CREDENTIALS)
                );
                let mut validator_leafs = Vec::new();
                let mut is_lido_validator = Vec::new();
                for i in 0..validators.len() {
                    validator_leafs.push(validator_roots[i]);
                    is_lido_validator.push(builder.is_equal(
                        validators[i].withdrawal_credentials,
                        lido_withdrawal_credentials
                    ));
                }

                // Convert balances to leafs.
                let mut balance_leafs = Vec::new();
                let zero = builder.constant::<U64Variable>(0u64);
                let mut sum = builder.constant::<U64Variable>(0u64);
                for i in 0..idxs.len() / 4 {
                    let balances = [
                        balances[i*4],
                        balances[i*4+1],
                        balances[i*4+2],
                        balances[i*4+3],
                    ];
                    let masked_balances = [
                        builder.select(is_lido_validator[i*4], balances[0], zero),
                        builder.select(is_lido_validator[i*4+1], balances[1], zero),
                        builder.select(is_lido_validator[i*4+2], balances[2], zero),
                        builder.select(is_lido_validator[i*4+3], balances[3], zero),
                    ];
                    sum = builder.add_many(&masked_balances);
                    balance_leafs.push(builder.beacon_u64s_to_leaf(balances));
                }

                // Reduce validator leafs to a single root.
                let validators_acc = builder.ssz_hash_leafs(&validator_leafs);
                let balances_acc = builder.ssz_hash_leafs(&balance_leafs);

                // Return the respective accumulators and partial sum.
                (validators_acc, balances_acc, sum)
            },
            |_, left, right, builder| {
                (
                    builder.sha256_pair(left.0, right.0),
                    builder.sha256_pair(left.1, right.1),
                    builder.add(left.2, right.2)
                )
            }
        );

        builder.assert_is_equal(output.0, partial_validators.validators_root);
        builder.assert_is_equal(output.1, partial_balances.root);
        builder.evm_write::<U64Variable>(output.2);
    }

    fn register_generators<L: PlonkParameters<D>, const D: usize>(registry: &mut HintRegistry<L, D>)
    where
        <<L as PlonkParameters<D>>::Config as GenericConfig<D>>::Hasher: AlgebraicHasher<L::Field>,
    {
        let id = MapReduceGenerator::<
            L,
            (BeaconValidatorsVariable, BeaconBalancesVariable),
            U64Variable,
            (Bytes32Variable, Bytes32Variable, U64Variable),
            DefaultSerializer,
            BATCH_SIZE,
            D,
        >::id();
        registry.register_simple::<MapReduceGenerator<
            L,
            (BeaconValidatorsVariable, BeaconBalancesVariable),
            U64Variable,
            (Bytes32Variable, Bytes32Variable, U64Variable),
            DefaultSerializer,
            BATCH_SIZE,
            D,
        >>(id);
    }
}

fn main() {
    LidoOracleV2::entrypoint();
}

#[cfg(feature = "include_v1_tests")]
//#[cfg(test)]
mod tests {
    use log::debug;
    use plonky2x::prelude::DefaultParameters;

    use super::*;

    type L = DefaultParameters;
    const D: usize = 2;

    /// An example source block root.
    const BLOCK_ROOT: &str = "0x4f1dd351f11a8350212b534b3fca619a2a95ad8d9c16129201be4a6d73698adb";

    #[test]
    fn test_circuit() {
        env_logger::try_init().unwrap_or_default();

        // Build the circuit.
        let mut builder = CircuitBuilder::<L, D>::new();
        LidoOracleV2::define(&mut builder);
        let circuit = builder.build();

        // Generate input.
        let mut input = circuit.input();
        input.write::<Bytes32Variable>(bytes32!(BLOCK_ROOT));

        // Generate the proof and verify.
        let (proof, mut output) = circuit.prove(&input);
        circuit.verify(&proof, &input, &output);

        // Read output.
        let tvl = output.read::<U64Variable>();
        debug!("{}", tvl);

        LidoOracleV2::test_serialization::<L, D>();
    }
}
