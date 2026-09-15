# How to onboard with an Oblivious HTTP relay hosted by Apple

Understand the requirements for running PIRService.

## Overview

To hide client’s IP address all network request made by the system to the server will go over
[Oblivious HTTP](https://www.rfc-editor.org/rfc/rfc9458). Apple will provide the oblivious relay and therefore there is
a required onboarding step to make sure that Apple’s oblivious HTTP relay has been configured to forward requests to
your chosen oblivious HTTP gateway.

![Oblivious HTTP flow diagram](oblivious-http.png)

### How to test without private relay

The system does not use private relay when the application is installed directly from Xcode. This allows the
application & the service deployment to be tested before filling out the onboarding form and setting up Oblivious HTTP
relay.


### Requirements

Before filling out the onboarding form, there are a few requirements you have to satisfy to ensure smooth operations.

#### OHTTP gateway

Apple's OHTTP relay expects your chosen OHTTP gateway to support HTTP/2. You can verify it by running.
```
openssl s_client -alpn h2 -connect $(OHTTP_GATEWAY_FQDN):443 </dev/null
```
In the output check if the SSL session was established or not.

#### URLs
You will need to provide the URLs you would put into your feature configuration. For example, for Live Caller ID Lookup, you would provide the URLs configured in
[LiveCallerIDLookupExtensionContext](https://developer.apple.com/documentation/identitylookup/livecalleridlookupextensioncontext). For NEURLFilter, you will provide the URLs specified in [NEURLFilter API documentation](https://developer.apple.com/documentation/networkextension/neurlfiltermanager).

> Warning: We require you to use subdomains instead of paths. Support for custom paths for the
> service URL and token issuer URL was removed in iOS and macOS 26.4.

Good example:
```
https://gateway.example.net
https://issuer.example.net
https://service.example.net
```

Bad example:
```
http://example.net:8080/lookup - No HTTPS, non standard port, path instead of subdomain
http://example.net/ - trailing '/' needs to be removed
```

> Note: When installing directly from Xcode during development, the URL can contain paths, custom ports and HTTP instead
> of HTTPS. This eases local testing and development. However, the system applies these URL checks when your app is
> installed from the App Store.

##### Declaring URLs in Info.plist

Starting in iOS and macOS 27.3, your service URL and Privacy Pass issuer URL must also be declared statically in your
app extension's Info.plist, rather than provided only at runtime. Add a top-level `NSPIRConfiguration` dictionary
with a `PIRServerURL` key and a `PrivacyPassIssuerURL` key; only a host is allowed (no custom paths, query
parameters, or other components). How this interacts with values passed at registration varies by use case, as
described below:

```xml
<key>NSPIRConfiguration</key>
<dict>
    <key>PIRServerURL</key>
    <string>https://pir.example.com</string>
    <key>PrivacyPassIssuerURL</key>
    <string>https://issuer.example.com</string>
</dict>
```

* Live Caller ID Lookup: `PIRServerURL` is equivalent to the `serviceURL` property and `PrivacyPassIssuerURL` is
  equivalent to `tokenIssuerURL`. Both keys are required; devices on iOS and macOS 27.3 ignore any value passed at
  registration and use the Info.plist values instead.
* NEURLFilter: `PIRServerURL` is equivalent to the `pirServerURL` property and `PrivacyPassIssuerURL` is equivalent to
  `pirPrivacyPassIssuerURL`. `PrivacyPassIssuerURL` is optional and defaults to the value of `PIRServerURL` when
  absent; devices on iOS and macOS 27.3 reject any mismatch between runtime values and Info.plist.

#### HTTP Bearer Token / UserToken
The `userToken` field is of type `String` and the system sets the "Authorization" header like this:
```swift
request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
```

#### Checklist

1. You must know the bundle identifier of your extension for Live Caller ID Lookup, or bundle identifier of your application for NEURLFilter.
2. You need to provide expected request and response size and per continent traffic estimates that include:
    * peak requests per second
    * total requests per day
3. You have added a test identity to your dataset.
    * For Live Caller ID Lookup, it should be +14085551212 with name “Johnny Appleseed”.
    * For NEURLFilter, it should be `www.apple.com/url-filter-test` with value as the integer `1`.
4. You have set up an Oblivious HTTP gateway.
5. You must provide your Oblivious HTTP Gateway configuration resource.
6. You must provide your Oblivious HTTP Gateway resource -- a URL used to make oblivious HTTP requests to your service.
7. You must provide your Privacy Pass Token Issuer URL.
8. You must provide your service URL.
9. You must provide an HTTP Bearer token, that allows us to validate that your deployment is set up correctly and we can
   successfully fetch the test identity.
10. You must add a DNS TXT record to your service URL to prove your ownership, control, and intent to serve Live Caller
    ID Lookups or NEURLFilter. More specifically you need to add one of the following records, depending on whether you are hosting
    Live Caller ID Lookups, or NEURLFilter:
    * For Live Caller ID Lookup, add `apple-live-caller-id-lookup=<app_extension_bundle_identifier>`
    * For NEURLFilter, add `apple-url-filter=<app_bundle_identifier>`

    Here, `<app_extension_bundle_identifier>` is replaced with your extension's bundle identifier for Live Caller ID Lookup; and `<app_bundle_identifier>` is replaced with your application bundle identifier for NEURLFilter. For example, if your Live Caller ID Lookup
    extension's bundle identifier is `net.example.lookup` the DNS TXT record should be: `apple-live-caller-id-lookup=net.example.lookup`.
11. You must ensure that your deployment (including Oblivious HTTP gateway & PIR service) is running so that we can
    perform the validation test.

### Onboarding forms

The onboarding form should be filled out when you have a working service, but before you start distributing your
application.

> Important: Register your Live Caller ID Lookup or Network Extension URL Filter configuration on the
> [Identity & Trust](https://icloud.developer.apple.com/dashboard/identity) page in the
> [CloudKit Console](https://icloud.developer.apple.com/).
