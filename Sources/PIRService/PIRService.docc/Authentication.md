# Anonymous Authentication

Learn how request authentication works.

## Overview

We use HTTP Bearer tokens and Publicly Verifiable Tokens from [Privacy Pass](https://www.rfc-editor.org/rfc/rfc9578) to
authenticate user requests. Privacy Pass tokens break the link between a specific user and the request, while still
allowing verification that the request came from an authorized user. Users can be divided into different user tiers so
that different level of details can be provided based on the user tier.

### Authentication flow

![Authentication flow diagram](authentication.png)

1. Authentication server shares the public keys with PIR compute nodes. (Optional)
2. Application authenticates with the authentication server using regular authentication flow.
3. Authentication server returns a User Token. This is a long lived HTTP Bearer token for the user.
4. Application registers the User Token with the system.
5. When a PrivacyPass token needs to be fetched, the system first asks the authentication server for the Token Issuer
   Directory that contains a list of public keys. To minimize the chance of authentication server giving out different
   public keys to different clients the clients fetch the Token Issuer Directory from a proxy server.
6. Authentication server returns the list of public keys (potentially through a proxy).
7. The system does not know which user tier is associated with which public key, so it sends the User Token to the
   authentication server.
8. Authentication server verifies the User Token and returns the public key that is associated with the User Tier. The
   system verifies that the returned public key is present in the Token Issuer Directory and it is valid based on the
   current time.
9. The system constructs a Privacy Pass token request using the specific public key. The token request is sent along
   with the User Token to the authentication server.
10. Authentication server verifies that:
    * HTTP Bearer token is valid,
    * the token request uses the public key that is associated with the right user tier,

    and issues the token response that the system uses to get a Privacy Pass token.
11. When a PIR request is made, the system attaches an unused Privacy Pass token to the request. The PIR node can use
    the public key to verify that the token is valid and that assures that the request is authorized.
12. Response to the PIR request is returned to the system.

### Details

In the sense of Privacy Pass architecture the authentication server fills the roles of Attester and Issuer. User Token
is used to attest token requests. The system uses the publicly verifiable Blind RSA based tokens: Token Type Blind RSA
(2048-bit).

The request for specific public key is a HTTP GET request for path `/token-key-for-user-token` on the authentication
server, where the `Authorization` header is set to the User Token. The response is a public key in DER-encoded
SubjectPublicKeyInfo (SPKI) object. The format is further described in [Section
6.5](https://www.rfc-editor.org/rfc/rfc9578#name-issuer-configuration-2) of the [Privacy Pass Issuance
Protocols](https://www.rfc-editor.org/rfc/rfc9578).

Token challenge will be created implicitly by the system itself. Generated token challenge will set the token type, and
the issuer name. Redemption context and origin info fields will be left unset.

The token request includes the User Token in the `Authorization` HTTP header.

### See also

- [The Privacy Pass Architecture](https://www.rfc-editor.org/rfc/rfc9576)
- [Privacy Pass Issuance Protocols](https://www.rfc-editor.org/rfc/rfc9578)
