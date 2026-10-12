/// OpenHuman Dart SDK — Protocol version constants.
///
/// This file defines the protocol, SDK, and minimum server versions.
/// These constants are used for:
///
/// - Capability negotiation (future)
/// - Debug logging
/// - Error reporting
/// - Compatibility checks
library;

/// The OpenHuman wire protocol version.
///
/// This version follows [Semantic Versioning](https://semver.org):
///
/// - **Major**: Breaking changes to the event envelope, field names,
///   or message format. Clients and servers with different major
///   versions are NOT compatible.
/// - **Minor**: Additive changes (new event types, new optional fields).
///   Clients and servers with different minor versions ARE compatible
///   (forward-compatible — unknown event types are forwarded to
///   `rawEvents` and ignored by typed sub-streams).
/// - **Patch**: Bug fixes, documentation changes. No protocol changes.
///
/// ## Current Version
///
/// `1.0.0` — Initial release.
///
/// ## Compatibility Strategy
///
/// | Client → Server | Compatible? |
/// |---|---|
/// | Same major, any minor/patch | ✅ Fully compatible |
/// | Same major, higher minor client | ✅ Forward-compatible (unknown events → `rawEvents`) |
/// | Same major, lower minor client | ✅ Forward-compatible (server sends new fields, client ignores them) |
/// | Different major | ❌ Not compatible |
///
/// The SDK uses `EventTypeX.fromWireName()` which returns `null` for
/// unknown event types, ensuring forward compatibility with future
/// server versions that add new event types.
const String kOpenHumanProtocolVersion = '1.0.0';

/// The Dart SDK package version.
///
/// This is the version of the `openhuman_sdk_dart` package itself,
/// NOT the protocol version. The SDK version tracks the feature set
/// and bug fixes of the Dart SDK code.
///
/// ## Current Version
///
/// `0.1.0` — Initial MVP release.
const String kOpenHumanSdkVersion = '0.1.0';

/// The minimum server version this SDK is compatible with.
///
/// The SDK can connect to any server >= this version (same major
/// protocol version). Servers with a lower version may not support
/// all features this SDK expects.
const String kOpenHumanMinServerVersion = '0.1.0';

/// Human-readable SDK version string for logging.
///
/// Format: `openhuman-sdk-dart/<sdk_version> (protocol/<protocol_version>)`
const String kOpenHumanSdkUserAgent =
    'openhuman-sdk-dart/$kOpenHumanSdkVersion (protocol/$kOpenHumanProtocolVersion)';
