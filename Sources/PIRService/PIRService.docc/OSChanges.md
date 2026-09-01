# OS changes for PIR service providers

Learn about OS changes that affect PIR service providers.

## Overview

Changes are organized by the OS release that introduced them, most recent first.

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
