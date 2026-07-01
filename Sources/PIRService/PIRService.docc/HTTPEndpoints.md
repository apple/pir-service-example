# Setting up the HTTP endpoints

Learn about the required endpoints that the system expects from your service.

## Overview

Communication between the system and server uses Protocol
Buffer (Protobuf) messages over HTTP. For the Protobuf schema please see [Homomorphic Encryption
Protobuf](https://github.com/apple/swift-homomorphic-encryption-protobuf).


The system expects three endpoints from the service:

1. The systems should be able to fetch configuration & get the status of evaluation keys stored on the server.
2. The system should be able to upload new evaluation key.
3. The system should be able to do Private Information Retrieval (PIR) queries.

The service also optionally supports a report endpoint, which applies only to the NEURLFilter use case:

5. For the NEURLFilter use case, the system can submit reports of blocked URLs to the service.

### Get configuration and status
The system calls the configuration endpoint periodically to get information about the use case configuration and
evaluation key status.

Request        | Value              | Description
-------------- | ------------------ | -----------
Method         | POST               | HTTP method.
Path           | `/config`          | HTTP path.
Header         | `Authorization`    | The value will contain a private access token.
Header         | `User-Agent`       | Identifier for the user's OS type and version.
Header         | `User-Identifier`  | Pseudorandom identifier tied to a user.
Request Body   | `ConfigRequest`    | Serialized Protobuf message that list the use-cases that the system is interested in. As of iOS 18.2, the client will set the `existing_config_ids` field.
Response       | `ConfigResponse`   | Serialized Protobuf message. The `ConfigResponse` contains the `configs` and `key_info` response fields. As of iOS 18.2, the message may set `reuse_existing_config: true` instead of the `pirConfig` field, reducing the message size. This indicates the client should use the config with id specified in `existing_config_ids`.
Response field | `configs`          | Map from use case names to the corresponding configuration.
Response field | `key_info`         | List of `KeyStatus` objects.

The system will cache the returned configurations. The `KeyStatus` objects are used to detect if the on-device key is in
sync with the evaluation key stored on the server.

### Upload evaluation key
When the system detects a new evaluation key, it uses this endpoint to upload it.

Request        | Value              | Description
-------------- | ------------------ | -----------
Method         | POST               | HTTP method.
Path           | `/key`             | HTTP path.
Header         | `Authorization`    | The value will contain a private access token.
Header         | `User-Agent`       | Identifier for the user's OS type and version.
Header         | `User-Identifier`  | Pseudorandom identifier tied to a user.
Body           | `EvaluationKeys`   | Serialized Protobuf message that contains evaluation key(s).

Your service should store the uploaded evaluation keys.

### PIR queries
This is the endpoint that answers to PIR requests. It uses the `User-Identifier` to look up the previously stored
evaluation key and uses it to evaluate the PIR request.

Request        | Value              | Description
-------------- | ------------------ | -----------
Method         | POST               | HTTP method.
Path           | `/queries`         | HTTP path.
Header         | `Authorization`    | The value will contain a private access token.
Header         | `User-Agent`       | Identifier for the user's OS type and version.
Header         | `User-Identifier`  | Pseudorandom identifier tied to a user.
Request Body   | `Requests`         | Serialized Protobuf message.
Response       | `Responses`        | Serialized Protobuf message.

### Report blocked URLs for NEURLFilter
This optional endpoint is used only by the NEURLFilter. It accepts reports of blocked URLs from the system. The
reporting feature is only allowed for supervised devices, where the admin/school has total control of their owned
devices. When Privacy Pass authentication is enabled, the request must include a valid Privacy Pass token in the
`Authorization` header (the same token used for PIR queries). Reports are written to disk when `reportDirectory` is set
in the server configuration; otherwise the report is dropped (and logged) and the server still returns a successful
response.

Request        | Value               | Description
-------------- | ------------------- | -----------
Method         | POST                | HTTP method.
Path           | `/report`           | HTTP path.
Header         | `Authorization`     | Privacy Pass token (required when Privacy Pass authentication is enabled). Format: `PrivateToken token=<base64url-encoded token bytes>`.
Header         | `Content-Type`      | Set to `application/json` to send a JSON array of URL strings. Omit (or use `application/octet-stream`) to send a serialized `URLFilterReport` Protobuf message.
Header         | `User-Agent`        | Identifier for the user's OS type and version. Captured and stored in the report metadata when present.
Request Body   | `URLFilterReport`   | Serialized Protobuf message or a JSON array containing the list of URLs that were blocked.
Response       | —                   | Empty body. Returns `200 OK` on success, `400 Bad Request` if the body is malformed.

The `URLFilterReport` Protobuf message is defined in this repository at
`Sources/PIRService/protobuf/URLFilterReport.proto`.

Each reported URL is the matched entry from the filter dataset, not the full URL the user visited. For example, if the
dataset contains `https://example.com/` and the user visits `https://example.com/xxx/yyy/zzz`, the entry matches and the
report contains `https://example.com/`.

To enable writing reports to disk, set the `reportDirectory` field in the server configuration JSON to the path of an
existing directory. Each received report is written as a separate `.txtpb` file (a text-format proto
`URLFilterReportWithMetadata`) with a UUID filename. If `reportDirectory` is omitted or set to `null`, reports are
accepted but immediately discarded.
