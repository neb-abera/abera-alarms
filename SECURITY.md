# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository, or write to support@alias.abera.tech. Do not open a public issue.

## What the app holds

- A device token for abera.tech: `aat_` and 43 base64url characters, 256 bits from the server's random number generator. The server stores only its SHA-256 hash.
- The token lives in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. It is readable from the first passcode entry after a restart, so the Stop button and background refresh work while the phone is locked. It is never in a backup and never on another device.
- The last state from the server, the list of alarms scheduled, and the acknowledgements waiting for a connection, in Application Support with `completeFileProtectionUntilFirstUserAuthentication`. They hold event titles, locations and times.

## Threats and what answers them

| Threat | Answer |
|---|---|
| A stolen or lost phone | Revoke its token on abera.tech/alerts. The next request from it is refused with 401. |
| A link from someone else points the app at their server | A release build pairs only with `https://abera.tech`. The link's server is checked against that list before the token is stored (`PairingLink.parse`). |
| The token leaks through a server log or a proxy | It travels in the link's fragment, which no web server receives, and then in an `Authorization` header over HTTPS. It is never in a query string. |
| A token that no longer works is kept | A 401 on pairing stores nothing. A 401 on sync says so on screen. |
| A hostile or broken server answer | Answers over 1 MB are refused. Dates longer than 40 characters are refused before parsing. A property test feeds the decoder 2,000 random byte strings. |
| An attacker schedules alarms on the phone | Only the paired server's answer schedules alarms, and only for alerts of type alarm. |

## Accepted risks

- A revoked or unpaired phone keeps the alarms it already scheduled until they ring or the owner presses Unpair. Removing them needs the app to run, and a phone that is refused cannot be told what the owner wants.
- Background refresh runs when iOS allows it. An event added after the last sync reaches the phone on its next launch or refresh. Pushover still delivers it with a connection.
- The `-demo` mode's in-memory server and alarms are compiled into Debug builds only (`#if DEBUG`).

## Standards checked

- NIST SP 800-63B, look-up secret authenticators: a random secret of 256 bits, stored hashed by the verifier, revocable, verified with a rate limit (the server side is in aberaTech).
- NIST SP 800-53 SC-8 (transmission confidentiality): HTTPS only. App Transport Security is at its default, so plain HTTP is refused.
- NIST SP 800-53 SC-28 (protection of information at rest): the Keychain and file protection classes above.
- DISA Application Security and Development STIG: no secret in source or logs, no credential in a URL, input validated before use, and errors that name no secret.
