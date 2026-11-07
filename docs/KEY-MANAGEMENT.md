# Key custody — Phase 2 draft

**No key material is included.** Generate a lab-only age X25519 identity and recipient; store private identity outside the project and artifacts under an ACL restricted to the Windows account. Record the recipient fingerprint and verify it out-of-band.

Generate an independent OpenSSL Ed25519 signing keypair for manifest authentication. Keep the private signing key separate from the age private identity and encrypted archives. Pin the verification public key path and independently check its fingerprint before using it.

Never put private keys into Git, `.env`, command-line arguments, shell history, Docker images, environment dumps, or published evidence. Paths to keys may appear in local commands, but key contents must not. Keep a tested offline recovery copy of the decryption identity, separately secured; loss of the only key makes encrypted archives unrecoverable.

The first local implementation may use files protected by NTFS ACLs and BitLocker; this is not equivalent to an HSM or centralized KMS. Key rotation, revocation, signature timestamp freshness, and compromise response require additional work.

A manifest's SHA-256 is only tamper-evident when its detached signature is verified against the independently trusted public key. An attacker holding the signing key can forge manifests.
