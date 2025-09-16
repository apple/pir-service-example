# PIR Service Example

[Live Caller ID
Lookup](https://developer.apple.com/documentation/sms_and_call_reporting/getting_up-to-date_calling_and_blocking_information_for_your_app)
is a new feature that allows the system to communicate with a third party service to privately retrieve information
about a phone number for an incoming call. This allows the system to automatically block known spam
callers and display identity information on the incoming call screen.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/apple/pir-service-example/raw/main/Sources/PIRService/PIRService.docc/Resources/overview~dark@2x.png">
  <img alt="Overview of the Live Caller ID Lookup" src="https://github.com/apple/pir-service-example/raw/main/Sources/PIRService/PIRService.docc/Resources/overview@2x.png">
</picture>

[NEURLFilter](https://developer.apple.com/documentation/networkextension/neurlfiltermanager) is a new feature for iOS and macOS that allows the system
to communicate with a third party service to privately check if a requested URL should be allowed or not. This allows your app to implement URL filtering in a privacy preserving manner.

This repository provides a functional server backend to test the Live Caller ID Lookup and NEURLFilter features.

> [!WARNING]
> While functional, this is just an example service and should not be run in production.

## Overview
PIR Service Example provides:
* [PIRService](https://swiftpackageindex.com/apple/pir-service-example/main/documentation/pirservice), an example service for Live Caller ID Lookup.
* [PrivacyPass](https://swiftpackageindex.com/apple/pir-service-example/main/documentation/privacypass), an implementation of the Privacy Pass publicly verifiable tokens.

The documentation lives at [Swift Package Index](https://swiftpackageindex.com/apple/pir-service-example).

## Developing PIR Service Example
Building PIR Service Example requires:
* 64-bit processor with little-endian memory representation
* macOS or Linux operating system
* [Swift](https://www.swift.org/) version 6.0 or later
* Optionally, [XCode](https://developer.apple.com/xcode/) version 16.1 or later

Additionally, developing PIR Service Example requires:
* [Nick Lockwood SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
* [pre-commit](https://pre-commit.com)
* [SwiftLint](https://github.com/realm/SwiftLint)

### Building
You can build PIR Service Example either via Xcode or via command line in a terminal.
#### Xcode
To build PIR Service Example from Xcode, simply open the root directory (i.e., the `pir-service-example` directory) of the repository in Xcode.
See the [Xcode documentation](https://developer.apple.com/documentation/xcode) for more details on developing with Xcode.

#### Command line
To build PIR Service Example from command line, open the root directory (i.e., the `pir-service-example` directory) of the repository in a terminal, and run
```sh
swift build -c release
```
The build products will be in the `.build/release/` folder.

To build in debug mode, run
```sh
swift build
```
The build products will be in the `.build/debug/` folder.
> [!WARNING]
> Runtimes may be slow in debug mode.

### Testing
Run unit tests via
```sh
swift test -c release --parallel
```
To run tests in debug mode, run
```sh
swift test --parallel
```
> [!WARNING]
> Runtimes may be slow in debug mode.

### Database Reloading
The PIR Service supports dynamic database reloading without requiring a full service restart. This allows you to update the database and configuration while the service continues running.

#### Reloading Process
1. **Update your input database**: Modify your input database file (e.g., `input.txtpb`) with new or updated entries.

2. **Process the new database**: Run `PIRProcessDatabase` to generate the new database files:
   ```sh
   PIRProcessDatabase config.json
   ```

3. **Trigger reload**: Send a `SIGHUP` signal to the running PIR Service process:
   ```sh
   kill -SIGHUP <PID>
   ```

   You can find the process ID using:
   ```sh
   ps aux | grep PIRService
   ```

#### Behavior
- When the service receives a `SIGHUP` signal, it reloads the configuration file and all associated database files.
- The service logs "Reloading configuration..." when starting the reload and "Reloading configuration completed." when finished.
- The service maintains multiple versions of the database to ensure compatibility with clients using older PIR parameters.
- Clients automatically fetch updated PIR parameters periodically, or you can explicitly call `RefreshPIR` to force an immediate update.

#### Version Compatibility
The service is designed to handle database updates gracefully:
- When you update the database, new PIR parameters may be generated.
- The service stores both new and old versions of the dataset.
- Clients using old PIR parameters will continue to work with the previous version of the dataset.
- As clients update their PIR parameters, they will automatically use the new dataset.

For more details on maintaining PIR parameter compatibility across updates, see [Reusing PIR Parameters](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/privateinformationretrieval/reusingpirparameters).

### Contributing
If you would like to make a pull request to PIR Service Example, please run `pre-commit install`. Then each commit will run some basic formatting checks.

### Documentation
PIR Service Example uses DocC for documentation.
For more information, refer to [the DocC documentation](https://www.swift.org/documentation/docc) and the [Swift-DocC Plugin](https://swiftlang.github.io/swift-docc-plugin/documentation/swiftdoccplugin).
#### Xcode
The documentation can be built from Xcode via `Product -> Build Documentation`.
#### Command line
The documentation can be built from command line by running
```sh
swift package generate-documentation
```
and previewed by running
```sh
swift package --disable-sandbox preview-documentation --target PIRService
```
