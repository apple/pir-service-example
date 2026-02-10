# Testing Live Caller ID Lookup

Learn how to run the example service for Live Caller ID Lookup.

## Overview

The primary objective of this example service is to provide a functional demonstration that can be utilized for testing
the feature. The general outline of the steps involved is as follows:

* Getting the tools.
* Preparing the dataset.
* Processing the dataset.
* Running the service.
* Writing the application extension.

### Getting the tools on your path

These testing steps assume that you have the following binaries available on your `$PATH`.
The binaries are:
 - `ConstructDatabase`
 - `PIRProcessDatabase`
 - `PIRService`

The way to add these to your path is by first making sure that the `~/.swiftpm/bin` directory is on your `$PATH`. To do
so, add the following line to your `~/.zshrc` or appropriate shell configuration file.
```sh
export PATH="$HOME/.swiftpm/bin:$PATH"
```
Make sure to reload it (`source ~/.zshrc`) or by restarting your terminal emulator. Then we are going to use the
`experimental-install` feature of Swift Package Manager.

#### ConstructDatabase

Change directory to a checkout of this repository and run the following command.
```sh
swift package experimental-install -c release --product ConstructDatabase
```

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

> Seealso: <doc:LiveCallerIDLookupDataFormat>

Lets start by making a new directory:
```sh
mkdir ~/testing
cd ~/testing
```
Now you need to prepare a dataset that is going to be served. To make it a little simpler you are going to use the
`ContructDatabase` utility. Save the following as `input.txtpb`.

```json
identities {
  key: "+123"
  value {
    name: "Adam"
    cache_expiry_minutes: 8
    category: IDENTITY_CATEGORY_PERSON
  }
}
identities {
  key: "+1234"
  value {
    name: "Bob"
    cache_expiry_minutes: 7
    block: true
  }
}
identities {
  key: "+12345"
  value {
    name: "Grocery Store"
    cache_expiry_minutes: 18
    block: false
    category: IDENTITY_CATEGORY_BUSINESS
  }
}
```

> Note: You can also get the example input by observing the output of running `ConstuctDatabase` without arguments.

This file is a [text format representation](https://protobuf.dev/reference/protobuf/textformat-spec/) of protobuf data.
The schema for the message can be found at `Sources/ConstructDatabase/protobuf/InputIdentities.proto`. As you can see,
we have set up 3 identities.

#### Adding icons
While `input.txtpb` contains almost all the fields that are needed, it is missing icons. Icons are somewhat hard to
represent in a textual format so `ConstructDatabase` provides a way to overcome that limitation. To add icons for the
identities create a new folder:

```sh
mkdir icons
```

And add icons as HEIC files to that folder. The filename should be: `$phonenumber.heic`. For example, after you have
added icons for "Adam" & "Grocery store" the directory listing should look like this:

```sh
$ ls icons
+123.heic
+12345.heic
```

> Warning: Images should be smaller than 64KB. We use 16-bit integers to encode the size of a value so the size of the
> `CallIdentity` protobuf message should not exceed 2^16-1 bytes.

> Tip: PIR runtime depends on the size of the images. For best performance, use small icons.

It is not necessary to provide icons for all identities. When `ConstuctDatabase` is parsing the input identities file,
it will search for the icon in the icons directory and attaches it if it is found.

### Constructing the two databases
Once we have prepared our input in the `input.txtpb` file and the `icons` folder. It is time to call:
```sh
ConstructDatabase --icon-directory icons input.txtpb block.binpb identity.binpb
```

This creates the `block.binpb` and `identity.binpb` files which are the blocking dataset and the identity dataset
expected for Live Caller ID Lookup. Both of these are in binary protobuf format, that is accepted by the
[PIRProcessDatabase](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/pirprocessdatabase)
utility.

### Processing the datasets

Before setting up a server to host these two datasets we need to process them a bit, so the online PIR queries can be
done faster. For this we will use the
[PIRProcessDatabase](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/pirprocessdatabase)
utility.

> Important: These example configurations are just for example. Please see
> [Parameter Tuning](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/privateinformationretrieval/parametertuning)
> to learn how to adjust the configuration for your dataset.

Write the following configuration into a file called `block-config.json`.
```json
{
  "inputDatabase": "block.binpb",
  "outputDatabase": "block-SHARD_ID.bin",
  "outputPirParameters": "block-SHARD_ID.params.txtpb",
  "rlweParameters": "n_4096_logq_27_28_28_logt_5",
  "sharding": {
    "entryCountPerShard": 50000
  },
  "trialsPerShard": 5,
  "databaseType": "keyword"
}
```
Now call the utility.

```sh
PIRProcessDatabase block-config.json
```

This instructs the `PIRProcessDatabase` utility to load the input from `block.binpb`, output the processed database into
a file called `block-0.bin`. See how the occurrences of `SHARD_ID` get replaced in `block-SHARD_ID.bin` to become the
first (and only) shard in our case with name `block-0.binpb`. In addition to the processed database, the utility also
outputs a file called `block-0.params.txtpb`. This file holds the PIR parameters for the shard.

Now we do basically the same thing for the identity database: write the following into a file called
`identity-config.json`.
```json
{
  "inputDatabase": "identity.binpb",
  "outputDatabase": "identity-SHARD_ID.bin",
  "outputPirParameters": "identity-SHARD_ID.params.txtpb",
  "rlweParameters": "n_4096_logq_27_28_28_logt_5",
  "sharding" : {
    "entryCountPerShard" : 5000
  },
  "trialsPerShard": 5
}
```

And call `PIRProcessDatabase` to process the identity database.

```sh
PIRProcessDatabase identity-config.json
```

This will create the following files:
 - `identity-0.bin` - the processed database,
 - `identity-0.params.txtpb` - the PIR parameters for the identity database.

> Important: The blocking dataset is has very small entries and the identity dataset has larger entries. So it makes
> sense to use different parameters for them.

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
      "fileStem": "block",
      "shardCount": 1,
      "name": "net.example.lookup.block"
    },
    {
      "fileStem": "identity",
      "shardCount": 1,
      "name": "net.example.lookup.identity"
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
the on-device Live Caller ID Lookup Extension is `net.example.lookup`. Then the system will try to fetch the blocking
information from `net.example.lookup.block` and the identity information from `net.example.lookup.identity`.

After the configuration file is as it should be, it is time to run the example service:

```sh
PIRService --hostname 0.0.0.0 service-config.json
```

By default `PIRService` will start listening on the loopback interface, but you can add the `--hostname 0.0.0.0` part to
make it listen on all network interfaces. The default port is `8080`, but it can be changed by using the `--port`
option.

#### Features
After introduction in iOS 18.0, `Live Caller ID Lookup` introduced further features.

* `Fixed PIR Shard Config` (iOS 18.2). When all shard configurations are identical, `PIR Fixed Shard Config` allows for a more compact PIR config, saving bandwidth and client-side memory usage. To enable, set the `pirShardConfigs` field in the PIR config. iOS clients prior to iOS 18.2 will still require the `shardConfigs` field to be set. See [Reusing PIR Parameters]( https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/privateinformationretrieval/reusingpirparameters) for how to process the database such that all shard configurations are identical.

* `Reusing existing config id` (iOS 18.2). During the `config` request, if a client has a cached configuration, it will send the config id of that cached configuration. Then, if the configuration is unchanged, the server may respond with a config setting `reuseExistingConfig = true` and omit any other fields. This helps reduce the response size for the config fetch.

* `Sharding function configurability` (iOS 18.2). [Sharding
  function](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/pirprocessdatabase#Sharding-function)
  can be configured. The `doubleMod` sharding function was designed specifically for the use case where multiple
  requests are made with the same keyword, like in Live Caller ID Lookup, where we use the same phone number to look up
  blocking information and Identity information. Note: this option is not backward compatible with older iOS versions.

### Writing the application extension

> Important: Please see [Getting up-to-date calling and blocking information for your
> app](https://developer.apple.com/documentation/sms_and_call_reporting/getting_up-to-date_calling_and_blocking_information_for_your_app)
> for information how to create an Live Caller ID Lookup extension.

To configure your extension to talk to the example service you need to fill in
[the extension
context](https://developer.apple.com/documentation/sms_and_call_reporting/livecalleridlookupextensioncontext).

This example service provides both the service itself and the privacy pass token issuer. So we should set the
`serviceURL` and `tokenIssuerURL` both to the same value: `http://lookup.example.net:8080`. For the `userTierToken`,
please set it to one of the values that you added in the service configuration file in <doc:#Running-the-service>
section. For example `BBBB`.

```swift
var context: LiveCallerIDLookupExtensionContext { get {
    return LiveCallerIDLookupExtensionContext(
        // The URL for the server endpoint that the system uses to fetch incoming call information.
        serviceURL: URL(string: "http://lookup.example.net:8080")!,
        // The URL of the token issuer.
        tokenIssuerURL: URL(string: "http://lookup.example.net:8080")!,
        // The token to authenticate the app.
        userTierToken: Data(base64Encoded: "BBBB")!
    )
}}
```

#### Running locally

When running things locally on your Mac, and your testing device is on the same network, then you can use mDNS to let
the device find your Mac. Let's assume that your Mac's hostname is `Tims-MacBook-Pro.local`.

> Note: You can find out your hostname by typing `hostname`.

Then we should use the following value for the URLs: `http://Tims-Macbook-Pro.local:8080`. Thanks to the mDNS protocol
your device should be able to resolve your hostname to the actual IP address of your Mac and make the connection.
