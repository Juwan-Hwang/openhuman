//! Notification Service — push notifications and event distribution.

pub mod dispatcher;

pub use dispatcher::{dispatch_offline_notification, register_device_token};
