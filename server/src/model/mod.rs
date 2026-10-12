//! Internal Data Model — Protocol-level types.
//!
//! These types implement the OpenHuman internal model defined in
//! `protocol/internal-model/`. They are role-neutral: the internal
//! model never stores OpenAI `role: user` / `role: assistant`.
//! Role mapping happens only at the `openai_compat` boundary.

pub mod agent_capability;
pub mod agent_context;
pub mod content;
pub mod conversation;
pub mod event;
pub mod identity;
pub mod message;
pub mod tool_invocation;
