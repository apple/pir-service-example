# Common errors that come up when using the example service

Learn about the common errors that the device logs and why they happen.

## Overview

While using the example service or when developing your own service, you may encounter one of the common errors
listed below. This page gives more details about these errors, like why they happen, what they mean, and how
to work around them.

### How to look for errors

You can use the Console app to see on-device logs. Search for error messages from the `com.apple.cipherml` subsystem.

### Common problems

#### The request timed out

**Error example**:

```
"The request timed out." UserInfo={NSLocalizedDescription=The request timed out.,
NSErrorFailingURLKey=http://MacBook-Pro.local:8080/.well-known/private-token-issuer-directory
```

**Reason:**
The most likely reason is that the device is not able to make a connection to your service.

**Workaround:**
This problem has multiple potential causes with multiple workarounds.
1. Check that you started the example service with specifying `--hostname 0.0.0.0` on the command line to make sure that
   it is listening on all interfaces.
2. Double-check that the device is on the same network as your MacBook.
3. Change from using mDNS to a IP address directly.

#### Failed to fetch token
**Error example**:

```
configure failed Error Domain=com.apple.CipherML Code=1100 "Unable to query status due to errors: failed to fetch token"
UserInfo={NSLocalizedDescription=Unable to query status due to errors: failed to fetch token,
NSUnderlyingError=0x9fc845ef0 {Error Domain=CipherML.AuthenticationError Code=3 "failed to fetch token"
UserInfo={NSLocalizedDescription=failed to fetch token}}}
```

**Reason:**
This could be because you misconfigured the issuerURL. For example, if you entered: `http://MacBook-Pro.local:8080/` as
the `issuerRequestUri` field in `service-config.json`. Another potential reason is that the user token is not accepted
by the server.

**Workaround:**
The `issuerRequestUri` field in `service-config.json` should also contain `/issue` path, like this:
`http://MacBook-Pro.local:8080/issue`. Also make sure that the user token in the extension matches one in the
`service-config.json`.

#### Missing configuration

**Error example**:

```
Error Domain=com.apple.CipherML Code=401 "Unable to request data by keywords batch: missing configuration"
UserInfo={NSLocalizedDescription=Unable to request data by keywords batch: missing configuration,
NSUnderlyingError=0x600002f4c6f0 {Error Domain=CipherML.CipherMLError Code=25 "missing configuration"
UserInfo={NSLocalizedDescription=missing configuration}}}: missing configuration
```

**Reason:**
Device issued a request to the configuration endpoint (`/config`), but did not find the configuration for the usecase it
was looking for.

**Workaround:**
Double-check that the service has usecases configured the way the device expects them. Usecase names for Live Caller ID Lookup should be:
* `<app_extension_bundle_identifier>.block`
* `<app_extension_bundle_identifier>.identity`

In the above, replace `<app_extension_bundle_identifier>` with your app extension's bundle identifier.

And usecase name for NEURLFilter should be:
* `<app_bundle_identifier>.url.filtering`

In the above, replace `<app_bundle_identifier>` with your application's bundle identifier.

#### No token key found with key id

**Error example**:

```
Error Domain=com.apple.CipherML Code=401 "Unable to request data by keywords batch: server error
({"error":{"message":"No token key found with key id: [215, 192, 75, 68, 132, 153, 117, 6, 13, 165, 212, 152, 30, 119,
175, 105, 191, 65, 112, 227, 4, 21, 187, 161, 113, 105, 254, 108, 83, 88, 91, 222]"}})"
UserInfo={NSLocalizedDescription=Unable to request data by keywords batch: server error ({"error":{"message":"No token
key found with key id: [215, 192, 75, 68, 132, 153, 117, 6, 13, 165, 212, 152, 30, 119, 175, 105, 191, 65, 112, 227, 4,
21, 187, 161, 113, 105, 254, 108, 83, 88, 91, 222]"}}), NSUnderlyingError=0x600003b5d2f0 {Error
Domain=CipherML.CipherMLError Code=5 "server error ({"error":{"message":"No token key found with key id: [215, 192, 75,
68, 132, 153, 117, 6, 13, 165, 212, 152, 30, 119, 175, 105, 191, 65, 112, 227, 4, 21, 187, 161, 113, 105, 254, 108, 83,
88, 91, 222]"}})" UserInfo={NSLocalizedDescription=server error ({"error":{"message":"No token key found with key id:
[215, 192, 75, 68, 132, 153, 117, 6, 13, 165, 212, 152, 30, 119, 175, 105, 191, 65, 112, 227, 4, 21, 187, 161, 113, 105,
254, 108, 83, 88, 91, 222]"}})}}}: server error ({"error":{"message":"No token key found with key id: [215, 192, 75, 68,
132, 153, 117, 6, 13, 165, 212, 152, 30, 119, 175, 105, 191, 65, 112, 227, 4, 21, 187, 161, 113, 105, 254, 108, 83, 88,
91, 222]"}})
```

**Reason:**
The device caches a few private access tokens. In this case, the device made a request with a cached token, and the
server is not able to find a public key that matches the key ID in the cached token. This most likely happened because
you restarted the service, which means that new keys were generated, and the example service forgot the old keys,
therefore making the cached tokens invalid.

**Workaround:**
Once the device runs out of cached tokens, it will fetch new ones. One way to speed up the process is to explicitly refresh the PIR parameters.
* For example, for Live Caller ID Lookup, call [refreshPIRParameters(forExtensionWithIdentifier:)](https://developer.apple.com/documentation/sms_and_call_reporting/livecalleridlookupmanager/4418043-refreshpirparameters).
* For NEURLFilter, see [NEURLFilter API documentation](https://developer.apple.com/documentation/networkextension/neurlfiltermanager).

#### Evaluation key not found

**Error example**:

```
Error Domain=com.apple.CipherML Code=401 "Unable to request data by keywords batch: server error
({"error":{"message":"Evaluation key not found"}})" UserInfo={NSLocalizedDescription=Unable to request data by keywords
batch: server error ({"error":{"message":"Evaluation key not found"}}), NSUnderlyingError=0x600003bc4150 {Error
Domain=CipherML.CipherMLError Code=5 "server error ({"error":{"message":"Evaluation key not found"}})"
UserInfo={NSLocalizedDescription=server error ({"error":{"message":"Evaluation key not found"}})}}}: server error
({"error":{"message":"Evaluation key not found"}})
```

**Reason:**
A real service should persist the evaluation key, but the example service only stores it in memory. So the server side
copy of the evaluation key is gone after you restart the example service.

**Workaround:**
The device will periodically refetch the configuration from the server and will notice the missing evaluation key. You can also force the system to refresh configuration by calling the appropriate refresh API.
* For Live Caller ID Lookup, you can call [refreshPIRParameters(forExtensionWithIdentifier:)](https://developer.apple.com/documentation/sms_and_call_reporting/livecalleridlookupmanager/4418043-refreshpirparameters).
* For NEURLFilter, refer to [NEURLFilter API documentation](https://developer.apple.com/documentation/networkextension/neurlfiltermanager).
