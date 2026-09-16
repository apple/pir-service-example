# OS changes for PIR service providers

Learn about OS changes that affect PIR service providers.

## Overview

Changes are organized by the OS release that introduced them, most recent first.

### Upcoming changes

These changes are not yet enforced on shipping releases.

> Note: A [test profile](https://developer.apple.com/download/all/?q=Live%20Caller%20ID%20Lookup%20NEURLFilter)
> is available for iOS and macOS 27.2 betas that activates the 27.3 behavior below early, so you can test your
> adoption before it's enforced in 27.3.

* `Maximum shard count and power-of-two requirement` (iOS and macOS 27.3). The maximum number of shards is now
  limited to 65,536, and the shard count must be a power of two (e.g. 256, 512, 1024, 2048). Configurations that
  already meet both constraints are compatible with prior releases without any further changes; devices on iOS and
  macOS 27.3 reject a shard count that exceeds the limit or isn't a power of two.

* `Per-request evaluation keys` (iOS and macOS 27.3). A query may now include a fresh evaluation key directly in the
  query payload as a fallback to uploading one ahead of time. See <doc:HTTPEndpoints> for the endpoint-level details.

* `Config fetched via Apple infrastructure` (iOS and macOS 27.3). Clients fetch the unauthenticated `GET /config`
  endpoint through Apple infrastructure rather than calling your service directly. Keep serving it with no
  `Authorization` or `User-Identifier` header, and expect caching to delay config propagation to clients.
  See <doc:HTTPEndpoints> for details.

  > Note: The test profile above does not activate this behavior early. Fetching through Apple infrastructure is
  > not supported by the test profile on iOS and macOS 27.2 betas; you can only test this change once it's enforced
  > in 27.3.

* `Static service URLs in Info.plist` (iOS and macOS 27.3). The service URL and Privacy Pass issuer URL must be
  declared statically in your app extension's `NSPIRConfiguration` Info.plist entry, rather than provided
  dynamically at runtime. See <doc:Onboarding> for the required keys and how they map to your existing URLs.

* `User tier support removed` (iOS and macOS 27.3). Devices no longer call `/token-key-for-user-token`; the system
  always uses the first valid key in the token issuer directory instead. See <doc:Authentication> for the current
  behavior and compatibility.

### Released changes

* `Privacy Pass token lifecycle changes` (iOS and macOS 27.0). Token fetching and caching behavior changed, and issued
  tokens are now valid for one week after issuance, up from one day. See <doc:Authentication> for the current
  behavior and what it means for your token issuer.

* `Custom URL paths removed` (iOS and macOS 26.4). The service URL and token issuer URL must use subdomains instead of
  custom paths; support for custom paths was removed. See <doc:Onboarding> for URL requirements.

* `Fixed PIR Shard Config` (iOS 18.2). When all shard configurations are identical, `PIR Fixed Shard Config` allows for a more compact PIR config, saving bandwidth and client-side memory usage. To enable, set the `pirShardConfigs` field in the PIR config. iOS clients prior to iOS 18.2 will still require the `shardConfigs` field to be set. See [Reusing PIR Parameters]( https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/privateinformationretrieval/reusingpirparameters) for how to process the database such that all shard configurations are identical.

* `Reusing existing config id` (iOS 18.2). During the `config` request, if a client has a cached configuration, it will send the config id of that cached configuration. Then, if the configuration is unchanged, the server may respond with a config setting `reuseExistingConfig = true` and omit any other fields. This helps reduce the response size for the config fetch.

* `Sharding function configurability` (iOS 18.2). [Sharding
  function](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/pirprocessdatabase#Sharding-function)
  can be configured. The `doubleMod` sharding function was designed specifically for the use case where multiple
  requests are made with the same keyword, like in Live Caller ID Lookup, where we use the same phone number to look up
  blocking information and Identity information. Note: this option is not backward compatible with older iOS versions.
