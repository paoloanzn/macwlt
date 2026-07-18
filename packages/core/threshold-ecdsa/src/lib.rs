use std::ffi::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use cggmp24::key_share::KeyShare;
use cggmp24::signing::Signature;
use cggmp24::supported_curves::Secp256k1;
use cggmp24::{ExecutionId, PregeneratedPrimes};
use generic_ec::Point;
use rand::rngs::OsRng;
use rand::RngCore;
use sha3::Keccak256;
use zeroize::Zeroize;

const PARTY_COUNT: u16 = 2;
const PUBLIC_KEY_LENGTH: usize = 33;
const SIGNATURE_LENGTH: usize = 64;

type SecpKeyShare = KeyShare<Secp256k1>;

struct GeneratedMaterial {
    share_a: Vec<u8>,
    share_b: Vec<u8>,
    public_key: [u8; PUBLIC_KEY_LENGTH],
}

fn random_execution_id() -> [u8; 32] {
    let mut id = [0u8; 32];
    OsRng.fill_bytes(&mut id);
    id
}

fn generate_prime_material() -> Result<[PregeneratedPrimes; 2], String> {
    let participant_a = std::thread::spawn(|| PregeneratedPrimes::generate(&mut OsRng));
    let participant_b = std::thread::spawn(|| PregeneratedPrimes::generate(&mut OsRng));
    let participant_a = participant_a.join();
    let participant_b = participant_b.join();
    let participant_a =
        participant_a.map_err(|_| "threshold ECDSA participant A prime generation panicked")?;
    let participant_b =
        participant_b.map_err(|_| "threshold ECDSA participant B prime generation panicked")?;
    Ok([participant_a, participant_b])
}

fn protocol_results<T, E>(
    result: Result<round_based::sim::SimResult<Result<T, E>>, round_based::sim::SimError>,
    operation: &str,
) -> Result<Vec<T>, String>
where
    E: std::fmt::Display,
{
    let result = result.map_err(|error| format!("{operation} simulation failed: {error}"))?;
    result
        .into_vec()
        .into_iter()
        .map(|party| party.map_err(|error| format!("{operation} failed: {error}")))
        .collect()
}

fn generate_material() -> Result<GeneratedMaterial, String> {
    let keygen_id = random_execution_id();
    let keygen_id = ExecutionId::new(&keygen_id);
    let incomplete = protocol_results(
        round_based::sim::run(PARTY_COUNT, |i, party| async move {
            let mut rng = OsRng;
            cggmp24::keygen::<Secp256k1>(keygen_id, i, PARTY_COUNT)
                .start(&mut rng, party)
                .await
        }),
        "threshold ECDSA key generation",
    )?;

    let primes = generate_prime_material()?;
    let auxiliary_id = random_execution_id();
    let auxiliary_id = ExecutionId::new(&auxiliary_id);
    let auxiliary = protocol_results(
        round_based::sim::run(PARTY_COUNT, |i, party| {
            let pregenerated = primes[usize::from(i)].clone();
            async move {
                let mut rng = OsRng;
                cggmp24::aux_info_gen(auxiliary_id, i, PARTY_COUNT, pregenerated)
                    .start(&mut rng, party)
                    .await
            }
        }),
        "threshold ECDSA auxiliary generation",
    )?;

    let shares = incomplete
        .into_iter()
        .zip(auxiliary)
        .map(|parts| {
            KeyShare::from_parts(parts)
                .map_err(|error| format!("threshold ECDSA key share is invalid: {error}"))
        })
        .collect::<Result<Vec<SecpKeyShare>, String>>()?;
    if shares.len() != usize::from(PARTY_COUNT) {
        return Err("threshold ECDSA generated an unexpected number of shares".into());
    }

    let public_bytes = shares[0].shared_public_key.to_bytes(true);
    let public_key: [u8; PUBLIC_KEY_LENGTH] = public_bytes
        .as_ref()
        .try_into()
        .map_err(|_| "threshold ECDSA produced an invalid public key length")?;

    let share_a = serde_json::to_vec(&shares[0])
        .map_err(|error| format!("could not serialize threshold share A: {error}"))?;
    let share_b = serde_json::to_vec(&shares[1])
        .map_err(|error| format!("could not serialize threshold share B: {error}"))?;

    Ok(GeneratedMaterial {
        share_a,
        share_b,
        public_key,
    })
}

fn deserialize_share(bytes: &[u8], label: &str) -> Result<SecpKeyShare, String> {
    serde_json::from_slice(bytes)
        .map_err(|error| format!("could not deserialize threshold share {label}: {error}"))
}

fn sign_transaction(
    share_a: &[u8],
    share_b: &[u8],
    transaction: &[u8],
) -> Result<[u8; SIGNATURE_LENGTH], String> {
    if transaction.is_empty() {
        return Err("Ethereum transaction signing preimage must not be empty".into());
    }

    let shares = [
        deserialize_share(share_a, "A")?,
        deserialize_share(share_b, "B")?,
    ];
    if shares[0].shared_public_key != shares[1].shared_public_key {
        return Err("threshold ECDSA shares do not belong to the same wallet".into());
    }

    let execution_id = random_execution_id();
    let execution_id = ExecutionId::new(&execution_id);
    let participants = [0u16, 1u16];
    let data = cggmp24::DataToSign::<Secp256k1>::digest::<Keccak256>(transaction);
    let signatures: Vec<Signature<Secp256k1>> = protocol_results(
        round_based::sim::run_with_setup(&shares, |i, party, share| async move {
            let mut rng = OsRng;
            cggmp24::signing(execution_id, i, &participants, share)
                .sign(&mut rng, party, &data)
                .await
        }),
        "threshold ECDSA signing",
    )?;
    if signatures.len() != usize::from(PARTY_COUNT) || signatures[0] != signatures[1] {
        return Err("threshold ECDSA participants produced different signatures".into());
    }
    signatures[0]
        .verify(
            &Point::<Secp256k1>::from(shares[0].shared_public_key),
            &data,
        )
        .map_err(|_| "threshold ECDSA signature did not verify")?;

    let mut signature = [0u8; SIGNATURE_LENGTH];
    signatures[0].write_to_slice(&mut signature);
    Ok(signature)
}

unsafe fn write_error(buffer: *mut c_char, capacity: usize, message: &str) {
    if buffer.is_null() || capacity == 0 {
        return;
    }
    let bytes = message.as_bytes();
    let length = bytes.len().min(capacity - 1);
    ptr::copy_nonoverlapping(bytes.as_ptr(), buffer.cast::<u8>(), length);
    *buffer.add(length) = 0;
}

unsafe fn publish_bytes(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut bytes = bytes.into_boxed_slice();
    *out_len = bytes.len();
    *out = bytes.as_mut_ptr();
    std::mem::forget(bytes);
}

#[no_mangle]
pub unsafe extern "C" fn macwlt_threshold_ecdsa_generate(
    out_share_a: *mut *mut u8,
    out_share_a_len: *mut usize,
    out_share_b: *mut *mut u8,
    out_share_b_len: *mut usize,
    out_public_key_33: *mut u8,
    error_buffer: *mut c_char,
    error_capacity: usize,
) -> c_int {
    if out_share_a.is_null()
        || out_share_a_len.is_null()
        || out_share_b.is_null()
        || out_share_b_len.is_null()
        || out_public_key_33.is_null()
    {
        write_error(
            error_buffer,
            error_capacity,
            "threshold ECDSA output pointer is null",
        );
        return -1;
    }
    *out_share_a = ptr::null_mut();
    *out_share_a_len = 0;
    *out_share_b = ptr::null_mut();
    *out_share_b_len = 0;

    match catch_unwind(AssertUnwindSafe(generate_material)) {
        Ok(Ok(material)) => {
            ptr::copy_nonoverlapping(
                material.public_key.as_ptr(),
                out_public_key_33,
                PUBLIC_KEY_LENGTH,
            );
            publish_bytes(material.share_a, out_share_a, out_share_a_len);
            publish_bytes(material.share_b, out_share_b, out_share_b_len);
            0
        }
        Ok(Err(error)) => {
            write_error(error_buffer, error_capacity, &error);
            -1
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_capacity,
                "threshold ECDSA generation panicked",
            );
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn macwlt_threshold_ecdsa_sign_transaction(
    share_a: *const u8,
    share_a_len: usize,
    share_b: *const u8,
    share_b_len: usize,
    transaction: *const u8,
    transaction_len: usize,
    out_signature_64: *mut u8,
    error_buffer: *mut c_char,
    error_capacity: usize,
) -> c_int {
    if share_a.is_null() || share_b.is_null() || transaction.is_null() || out_signature_64.is_null()
    {
        write_error(
            error_buffer,
            error_capacity,
            "threshold ECDSA input pointer is null",
        );
        return -1;
    }
    let share_a = std::slice::from_raw_parts(share_a, share_a_len);
    let share_b = std::slice::from_raw_parts(share_b, share_b_len);
    let transaction = std::slice::from_raw_parts(transaction, transaction_len);

    match catch_unwind(AssertUnwindSafe(|| {
        sign_transaction(share_a, share_b, transaction)
    })) {
        Ok(Ok(signature)) => {
            ptr::copy_nonoverlapping(signature.as_ptr(), out_signature_64, SIGNATURE_LENGTH);
            0
        }
        Ok(Err(error)) => {
            write_error(error_buffer, error_capacity, &error);
            -1
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_capacity,
                "threshold ECDSA signing panicked",
            );
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn macwlt_threshold_ecdsa_free(bytes: *mut u8, length: usize) {
    if bytes.is_null() {
        return;
    }
    let slice = ptr::slice_from_raw_parts_mut(bytes, length);
    let mut bytes = Box::from_raw(slice);
    bytes.zeroize();
}
