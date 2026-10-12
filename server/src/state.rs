//! Shared types that cross the storage / service / API boundary.
//!
//! In Phase 4, the old `Store` and `SharedState` have been replaced
//! by the `storage` module (trait + memory impl). This file retains
//! the `AuthPrincipal` type used by both the auth middleware and
//! the repository traits.

use crate::model::identity::{AgentIdentity, ApiKey, HumanIdentity};

/// The authenticated principal resolved from an API key.
///
/// Contains the agent identity, the bound human endpoint,
/// and the API key record itself.
#[derive(Debug, Clone)]
pub struct AuthPrincipal {
    pub agent: AgentIdentity,
    pub human: HumanIdentity,
    pub api_key: ApiKey,
}
