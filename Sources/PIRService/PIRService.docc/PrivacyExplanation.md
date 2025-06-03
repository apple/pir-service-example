# Understanding how PIR features preserve privacy

Both Live Caller ID Lookup and NEURLFilter protect user privacy by hiding the client’s IP address, using anonymous authentication, and
hiding the incoming phone number or requested URL, respectively.

## Overview

The Live Caller ID Lookup feature allows you to check incoming calls against your service for known spam numbers while
preserving user privacy. When someone’s device receives a phone call, the system communicates with your back-end server
to retrieve caller ID and blocking information, and then displays that information on the incoming call screen and in
the device’s recent phone calls.

NEURLFilter is a similar feature that allows your app to implement private URL filtering functionality. When your user requests a URL,
NEURLFilter lets your app privately query your back-end server to check if this URL should be allowed or not.

Apple’s implementation of both of these features upholds user privacy while providing useful information. It does this
by:
* Hiding the client’s IP address using Apple’s [Oblivious HTTP](https://www.rfc-editor.org/rfc/rfc9458) relay.
* Using anonymous authentication with [The Privacy Pass Architecture](https://www.rfc-editor.org/rfc/rfc9576).
* Hiding the incoming number or requested URL by using Private Information Retrieval.

### Hide the client’s IP address

The client hides identifiable information using [Oblivious
HTTP](https://www.rfc-editor.org/rfc/rfc9458)(OHTTP). In OHTTP, the client will encrypt the request using the public key
of a gateway. It then sends the encrypted request to a relay that removes the client's IP address before forwarding it
to the gateway. The gateway decrypts the request and sends it to the target resource.

![Oblivious HTTP flow diagram](oblivious-http.png)

Apple will provide the relay for all users of Live Caller ID Lookup and NEURLFilter. This means that third party gateways and services
are not able to see client IP addresses. At the same time, Apple's relays do not learn the specifics of the requests.

### Use anonymous authentication

These features use [The Privacy Pass Architecture](https://www.rfc-editor.org/rfc/rfc9576), which allows you to
authenticate the users registered with the service without sharing the user’s identity or linking the client’s identity
to the query. First, your on device app authenticates the client with your method of choice and vends a long term token
(user token). Then, the app hands this token to the on device system. From there, the system runs multiple instances of
the [token issuance protocol](https://www.rfc-editor.org/rfc/rfc9578#name-issuance-protocol-for-publi) with your server
and receives several private access tokens that it can use to make authenticated anonymous queries.

Your server doesn’t learn which user token is associated with a private access token. Additionally, your on device,
client side app only participates in the initial authentication. The client side app doesn’t know the private tokens and
query phone numbers since the system controls them. This ensures authentication while preserving privacy. For more
information, see <doc:Authentication>.

### Hide the incoming number or requested URL

Live Caller ID Lookup and NEURLFilter use Keyword Private Information Retrieval (KPIR) to hide client queries. KPIR is a cryptographic
protocol that allows the user to fetch data corresponding to a particular keyword from the database hosted on an untrusted
server without revealing the keyword to the server. Implementing these features requires the service
provider to run a KPIR server on its database and handle all of the client’s KPIR encrypted queries. For more
information, see [Swift Homomorphic Encryption library](https://github.com/apple/swift-homomorphic-encryption).
