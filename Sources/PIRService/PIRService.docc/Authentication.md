# Anonymous Authentication

Learn how request authentication works.

## Overview

We use HTTP Bearer tokens and Publicly Verifiable Tokens from [Privacy Pass](https://www.rfc-editor.org/rfc/rfc9578) to
authenticate user requests. Privacy Pass tokens break the link between a specific user and the request, while still
allowing verification that the request came from an authorized user. Users can be divided into different user tiers so
that different levels of detail can be provided based on the user tier.

### Authentication flow

![Authentication flow diagram](authentication.png)

1. Authentication server shares the public keys with PIR compute nodes. (Optional)
2. Application authenticates with the authentication server using regular authentication flow.
3. Authentication server returns a User Token. This is a long lived HTTP Bearer token for the user.
4. Application registers the User Token with the system.
5. When a Privacy Pass token needs to be fetched, the system first asks the authentication server for the Token Issuer
   Directory that contains a list of public keys. To minimize the chance of the authentication server giving out
   different public keys to different clients, the clients fetch the Token Issuer Directory from a proxy server.
6. Authentication server returns the list of public keys (potentially through a proxy).
7. The system does not know which user tier is associated with which public key, so it sends the User Token to the
   authentication server.
8. Authentication server verifies the User Token and returns the public key that is associated with the user tier. The
   system verifies that the returned public key is present in the Token Issuer Directory and it is valid based on the
   current time.
9. The system constructs a Privacy Pass token request using the specific public key. The token request is sent along
   with the User Token to the authentication server.
10. Authentication server verifies that:
    * HTTP Bearer token is valid,
    * the token request uses the public key that is associated with the right user tier,

    and issues the token response that the system uses to get a Privacy Pass token.
11. When a PIR request is made, the system attaches an unused Privacy Pass token to the request. The PIR node can use
    the public key to verify that the token is valid, which assures the request is authorized.
12. Response to the PIR request is returned to the system.

### Details

In the sense of Privacy Pass architecture the authentication server fills the roles of Attester and Issuer. The User
Token is used to attest token requests. The system uses the publicly verifiable Blind RSA based tokens: Token Type
Blind RSA (2048-bit). These are also called Private Access Tokens (the term used in the flow diagram above).

The request for a specific public key is an HTTP GET request for path `/token-key-for-user-token` on the authentication
server, where the `Authorization` header is set to the User Token. The response is a public key as a DER-encoded
SubjectPublicKeyInfo (SPKI) object. The format is further described in [Section
6.5](https://www.rfc-editor.org/rfc/rfc9578#name-issuer-configuration-2) of the [Privacy Pass Issuance
Protocols](https://www.rfc-editor.org/rfc/rfc9578).

The token challenge is created implicitly by the system itself. The generated token challenge sets the token type and
the issuer name. Redemption context and origin info fields are left unset.

The token request includes the User Token in the `Authorization` HTTP header.

### How the system fetches tokens

> Note: The behavior described in this section applies to iOS 27.0 and later. Versions before iOS 27.0 fetched tokens
> differently, so the batch sizes, thresholds, and schedule described here should not be relied upon for earlier
> releases.

The system keeps a local cache of unused Privacy Pass tokens and refills it in the background, so that a PIR request
rarely has to wait for token issuance. Understanding this behavior helps you provision your issuer for the request
patterns it will see.

**Batch size.** The number of tokens requested per fetch depends on why the fetch happened:

- Proactive refills request an *adaptive* batch that tracks each user tier's typical daily token consumption (see
  "Adaptive batch sizing" below).
- Reactive refills and on-demand fetches always request a *fixed* batch of 10 tokens, regardless of how many tokens
  are currently cached. The batch size is intentionally independent of cache state on these paths so the issuer
  cannot infer whether the client just ran out of tokens or is topping up a partially full cache from the number of
  tokens requested.

**Expiration.** Each issued token is valid for one week after issuance. After that the system
discards it and fetches replacements.

> Important: The token validity period increased from one day to one week. If you operate an issuer, keep each public
> verification key valid for at least one week after its last use, or week-old tokens will fail verification and their
> PIR requests will fail.

**When the system fetches tokens.** There are three triggers:

- *Proactive refill.* A periodic background task runs approximately every 6 hours (with up to ~1 hour of random jitter),
  while the device is idle and has network connectivity. It fetches an adaptive batch (see below) for each
  authenticated user tier.
- *Reactive refill.* After serving a token, if the number of remaining cached tokens drops below a low-water mark of 5,
  the system schedules a one-shot background refill. This refill is delayed by a random interval of 0–2 hours so that
  its timing cannot be correlated with the PIR request that triggered it. Only one reactive refill is pending at a
  time, and when it runs it tops up a fixed batch of 10 tokens for every user token currently below the low-water
  mark — not only the user token whose request triggered the refill.
- *On-demand fetch.* If a live PIR request finds no usable token in the cache, the system fetches 1 token synchronously
  to serve the request and fetches the remaining 9 in the background, for a fixed batch of 10.

Because tokens live for one week but the proactive task runs every ~6 hours, the cache is normally topped back up
well before tokens expire or the pool drains. The reactive and on-demand paths mainly serve as fallbacks during heavy
use or after long idle periods.

**Adaptive batch sizing.** The proactive refill does not request a fixed number of tokens. Instead, it tracks a
slowly smoothed average of how many tokens each user tier consumes per day — an exponentially-weighted
moving average with a 7-day half-life — and requests roughly a 6-hour share of that average (`B = max(1,
round(dailyRate × 6 / 24))`) on every proactive run:

- *Cold start.* A user tier with no consumption history starts at the floor of 1 token per proactive run and ramps up
  toward its steady-state usage over roughly a week as queries accrue. (Separately, the fixed backstops cover the gap
  during this ramp-up: the reactive refill, the on-demand fetch, and an initial warm-up fetch when a user tier is
  first registered, each requesting the fixed batch of 10.)
- *Steady state.* A user tier issuing a steady rate of *R* tokens/day converges to a proactive batch that also
  averages *R* tokens/day, spread across the four daily proactive runs.
- *Falling demand.* If a user tier goes idle, its batch decays back toward the floor of 1 over roughly the same
  week-long half-life, rather than dropping immediately to zero.
- *Ceiling.* The batch is capped at 512 tokens per run as a defensive bound against a runaway or erroneous demand
  estimate; this ceiling is not expected to be reached by normal usage.

**What this means for your issuer:**

- Expect proactive-refill batch sizes per user tier to track that tier's own slowly changing weekly-average
  consumption, not its most recent burst of activity. A tier that suddenly queries heavily will not see its
  proactive batch jump immediately, and a newly active tier ramps up from a batch size of 1 over roughly a week.
- Expect additional issuance requests in fixed bursts of up to 10 tokens per user tier from reactive refills and
  on-demand fetches. A single reactive refill may request tokens for several user tokens at once.
- Token fetches are intentionally decoupled (jittered) from PIR requests, so issuance timing does not correlate with
  query timing.

### See also

- [The Privacy Pass Architecture](https://www.rfc-editor.org/rfc/rfc9576)
- [Privacy Pass Issuance Protocols](https://www.rfc-editor.org/rfc/rfc9578)
