//! Cryptographic helpers — API key hashing.
//!
//! # Why this module exists
//!
//! API keys used to be indexed by a `DefaultHasher`-derived value. That is a
//! 64-bit non-cryptographic hash (SipHash with a randomly seeded state), so:
//!
//! - it is **not stable across process restarts** — the same key hashes
//!   differently after a redeploy;
//! - it is only 64 bits, so it is trivially brute-forced if leaked;
//! - it gave the false impression that keys were stored hashed, while
//!   authentication actually queried `WHERE raw_key = $1` against plaintext.
//!
//! Everything now keys off real SHA-256. The digest is stable, one-way, and
//! 256 bits wide.

use sha2::{Digest, Sha256};

/// Compute the SHA-256 digest of `input`, lowercase hex encoded (64 chars).
///
/// This is the canonical form used to index and look up API keys. It must
/// never be given a salt or pepper: lookups are by exact digest, and a
/// per-install salt would make existing keys unresolvable after a migrate.
pub fn sha256_hex(input: &str) -> String {
    let digest = Sha256::digest(input.as_bytes());
    hex::encode(digest)
}

/// Constant-time-ish comparison of two hex digests.
///
/// Digests are compared for equality only after a length check, so differing
/// lengths return early. Both operands are public, fixed-length digests here
/// (not secrets being probed byte by byte), so a plain comparison is
/// sufficient — the digest itself is what must stay secret at rest.
pub fn digest_eq(a: &str, b: &str) -> bool {
    a.len() == b.len() && a == b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_vector() {
        // SHA-256("abc") — NIST test vector.
        assert_eq!(
            sha256_hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn empty_input() {
        assert_eq!(
            sha256_hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn stable_and_distinct() {
        let a = sha256_hex("ohk_demo_alice_codex");
        let b = sha256_hex("ohk_demo_alice_codex");
        let c = sha256_hex("ohk_demo_alice_codexx");
        assert_eq!(a, b);
        assert_ne!(a, c);
        assert_eq!(a.len(), 64);
    }

    #[test]
    fn seeded_demo_key_resolves() {
        // Guards the seed data in `001_init.sql`: the migration backfills
        // `key_hash` with exactly this digest, so if either side drifts the
        // demo key stops authenticating.
        assert_eq!(
            sha256_hex("ohk_demo_alice_codex"),
            "f229733fcff45484ec2c7834181b1b1466068e8321a9e4de4f56d060874f5b8e"
        );
    }
}
