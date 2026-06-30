Sources/PIRService/generated/# Protobuf files

The files in `../generated` are generated from these protobuf files using the following command at the root of the repository.

```sh
find Sources/PIRService/protobuf -name "*.proto" -exec protoc -I Sources/PIRService/protobuf --swift_out Sources/PIRService/generated {} \;
```

Note: [swift-protobuf](https://github.com/apple/swift-protobuf) version 1.38.1 was used.
