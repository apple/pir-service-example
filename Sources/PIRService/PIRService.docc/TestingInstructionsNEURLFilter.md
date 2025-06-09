# Testing NEURLFilter

Learn how to run the example service for NEURLFilter.

## Overview

The primary objective of this example service is to provide a functional demonstration that can be utilized for testing
the feature. The general outline of the steps involved is as follows:

* Getting the tools.
* Preparing the dataset.
* Processing the dataset.
* Running the service.
* Writing the application and application extension.

### Getting the tools on your path

These testing steps assume that you have the following binaries available on your `$PATH`.
The binaries are:
 - `PIRProcessDatabase`
 - `PIRService`

The way to add these to your path is by first making sure that the `~/.swiftpm/bin` directory is on your `$PATH`. To do
so, add the following line to your `~/.zshrc` or appropriate shell configuration file.
```sh
export PATH="$HOME/.swiftpm/bin:$PATH"
```
Make sure to reload it (`source ~/.zshrc`) or by restarting your terminal emulator. Then we are going to use the
`experimental-install` feature of Swift Package Manager.

#### PIRProcessDatabase

This tool comes from the [main repository](https://github.com/apple/swift-homomorphic-encryption) of Swift Homomorphic
Encryption. Change directory to a checkout of the main repository and run the following command.

```sh
swift package experimental-install -c release --product PIRProcessDatabase
```

#### PIRService

Change directory to a checkout of this repository and run the following command.
```sh
swift package experimental-install -c release --product PIRService
```
### Preparing the dataset

> Seealso: <doc:NEURLFilterDataFormat>

Lets start by making a new directory:
```sh
mkdir ~/testing
cd ~/testing
```
Now you need to prepare a dataset that is going to be served. Save the following as `input.txtpb`.

```json
rows: [{
        keyword: "example.com",
        value: "1"
    },
    {
        keyword: "example2.com",
        value: "1"
    },
    {
        keyword: "example3.com",
        value: "1"
    },
    {
        keyword: "example4.com",
        value: "1"
    },
    {
        keyword: "example5.com",
        value: "1"
    },
    {
        keyword: "example6.com",
        value: "1"
    },
    {
        keyword: "example7.com",
        value: "1"
    },
    {
        keyword: "example8.com",
        value: "1"
    },
    {
        keyword: "example9.com",
        value: "1"
    },
    {
        keyword: "example10.com/resource?query=bugs",
        value: "1"
    }]

```

This file is a [text format representation](https://protobuf.dev/reference/protobuf/textformat-spec/) of protobuf data.
 As you can see, we have set up 10 URLs to be blocked.

## Processing the dataset

Next, we need to process the dataset so online PIR queries can be
done faster. For this we will use the
[PIRProcessDatabase](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/pirprocessdatabase)
utility.

> Important: These example configurations are just for example. Please see
> [Parameter Tuning](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/privateinformationretrieval/parametertuning)
> to learn how to adjust the configuration for your dataset.

Write the following configuration into a file called `url-config.json`.
```json
{
  "inputDatabase": "input.txtpb",
  "outputDatabase": "url-SHARD_ID.bin",
  "outputPirParameters": "url-SHARD_ID.params.txtpb",
  "rlweParameters": "n_4096_logq_27_28_28_logt_5",
  "sharding": {
    "entryCountPerShard": 50000
  },
  "trialsPerShard": 5
}
```
Now call the utility.

```sh
PIRProcessDatabase url-config.json
```

This instructs the `PIRProcessDatabase` utility to load the input from `input.txtpb`, output the processed database into
a file called `url-0.bin`. See how the occurrences of `SHARD_ID` get replaced in `url-SHARD_ID.bin` to become the
first (and only) shard in our case with name `url-0.binpb`. In addition to the processed database, the utility also
outputs a file called `url-0.params.txtpb`. This file holds the PIR parameters for the shard.

### Running the service

Copy the following to a file called `service-config.json`.

```json
{
  "users": [
    {
      "tier": "tier1",
      "tokens": ["AAAA"]
    },
    {
      "tier": "tier2",
      "tokens": ["BBBB", "CCCC"]
    }
  ],
  "usecases": [
    {
      "fileStem": "url",
      "shardCount": 1,
      "name": "com.example.apple-samplecode.SimpleURLFilter.url.filtering"
    }
  ]
}
```
This configuration file has 3 sections.

1. `users` - This is a mapping from user tiers to User Tokens that are allowed for that tier. The User tokens are
   already base64 encoded as they appear in the HTTP `Authorization` header.
2. `usecases` - This is a list of usecases, where each usecase has the `fileStem`, `shardCount`, and `name`. When
   loading the usecase, `PIRService` does something like:
```swift
self.shards = try (0..<shardCount).map { shardIndex in
    let parameterPath = "\(fileStem)-\(shardIndex).params.txtpb"
    let databasePath = "\(fileStem)-\(shardIndex).bin"
    ...
}
```
The `name` will be used by the device to identify the dataset. In this example, we assume that the bundle identifier of
the application is `com.example.apple-samplecode.SimpleURLFilter`. Then the system will try to fetch the URL
information from `com.example.apple-samplecode.SimpleURLFilter.url.filtering`.

After the configuration file is as it should be, it is time to run the example service:

```sh
PIRService --hostname 0.0.0.0 service-config.json
```

By default `PIRService` will start listening on the loopback interface, but you can add the `--hostname 0.0.0.0` part to
make it listen on all network interfaces. The default port is `8080`, but it can be changed by using the `--port`
option.

### Writing the application

Use the `NEURLFilterManager` API in your filter app to create the URL filter configuration and manage your URL filter.  Create the URL filter configuration to let the system know how to talk to your PIR server and Privacy Pass issuer.  Use the `setConfiguration()` function to create the URL configuration with the required attributes

```swift
public func setConfiguration(pirServerURL: URL,
                             pirPrivacyPassIssuerURL: URL?,
                             pirAuthenticationToken: String,
                             controlProviderBundleIdentifier: String) throws
```

This example service provides both the service itself and the Privacy Pass token issuer. So we should set the `pirServerURL` and `pirPrivacyPassIssuerURL` both to the same value: `http://lookup.example.net:8080`. For the `pirAuthenticationToken`, please set it to one of the values that you added in the service configuration file in <doc:Running-the-service>, for example `BBBB`.  Specify the bundle identifier of your `NEURLFilterControlProvider` app extension also.  Optionally configure other URL Filter parameters, such as `prefilterFetchInterval` to specify how often your app extension should run to fetch your Bloom filter onto device.  Now you can enable and save your URL Filter configuration, and your URL filter will take effect.

### Writing the application extension

Create your URL Filter app extension by implementing the `NEURLFilterControlProvider` protocol.  Implement the `fetchPrefilter()` function to fetch your Bloom filter either from your app bundle resources or from your server.  Return the Bloom filter to the system using the `NEURLFilterPrefilter` struct.  Your app extension will be executed according to the `prefilterFetchInterval` you configure in your URL Filter configuration.  See [documentation](https://developer.apple.com/documentation/networkextension/neurlfiltercontrolprovider) for `fetchPrefilter()` function to see how to build your Bloom filter with your URL data set.

#### Running locally

When running things locally on your Mac, and your testing device is on the same network, then you can use mDNS to let
the device find your Mac. Let's assume that your Mac's hostname is `Tims-MacBook-Pro.local`.

> Note: You can find out your hostname by typing `hostname`.

Then we should use the following value for the URLs: `http://Tims-Macbook-Pro.local:8080`. Thanks to the mDNS protocol
your device should be able to resolve your hostname to the actual IP address of your Mac and make the connection.
