# Reference Material

This directory contains read-only clones of TLS libraries and specifications
for cross-referencing during NSS development. Do not attempt to modify files
here — the mount is read-only.

All repos live under `reference/repos/<name>/`.

## TLS Libraries

### rustls
Rust TLS library with a clean, modern codebase. Useful for comparing how TLS
features (session resumption, key schedule, certificate verification) are
implemented in a memory-safe language with clear abstractions.

### boringssl
Google's fork of OpenSSL, used in Chrome and Android. The closest peer to NSS
in terms of scope and deployment. Its `ssl/` directory mirrors many of the same
protocol paths NSS takes — comparing handshake state machines, extension
handling, and AEAD usage is often informative.

### openssl
The most widely deployed TLS library. Its `ssl/` and `crypto/` directories
are useful references for PKCS#11 interaction patterns, certificate chain
building, and legacy protocol handling. Note that OpenSSL's code style and
error handling differ significantly from NSS.

### s2n-tls
AWS's TLS library, designed for simplicity and auditability. Has well-isolated
handshake and record-layer code that can clarify protocol flows. Its test
infrastructure (particularly for negative/edge-case testing) is worth studying.

## Firefox

### firefox
The Firefox browser source tree (gecko-dev mirror). Useful for understanding
how NSS is integrated and consumed — particularly the PSM (Personal Security
Manager) layer in `security/manager/`, the certverifier in
`security/certverifier/`, and the build system integration. When investigating
how Firefox calls into NSS or how certificate/TLS policy decisions are made at
the application level, start here.

## Thunderbird

### thunderbird-desktop
The Thunderbird email client source tree. Useful for understanding how NSS is
used for email security — particularly S/MIME signing and encryption in
`mailnews/mime/`, certificate management in `mail/components/`, and the
account security settings UI. When investigating bugs in CMS/PKCS#7 code,
PKCS#12 import/export, or certificate verification paths that email clients
exercise differently from browsers, start here.

## Specifications

### tls13-spec
The TLS 1.3 specification (RFC 8446) in source form. Consult this for
authoritative answers about handshake flows, key derivation, extension
semantics, and alert handling.

### dtls13-spec
The DTLS 1.3 specification (RFC 9147) in source form. Covers the
datagram-specific adaptations: epoch handling, record sequence numbering,
retransmission, and ACKs.

## Usage Tips

- Cross-reference other libraries when investigating protocol-level bugs to
  understand whether behaviour is spec-mandated or implementation-specific.
- Use `grep`/`Grep` to search across all repos at once:
  `Grep pattern /workspaces/nss-dev/reference/repos/`
- When fixing a bug in NSS's handshake or extension code, check how boringssl
  and rustls handle the same case — they often have clear, well-commented
  implementations.
- The spec repos contain the authoritative text. Prefer them over memory when
  checking protocol details.
