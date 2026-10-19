# Security policy

Glint captures your screen, so its security and privacy matter. By design, it:
- runs in the macOS App Sandbox, with access only to files you choose in the Save panel;
- has no network entitlement, so it cannot send anything off your Mac;
- refuses to export an image if a redaction can't be produced, rather than leaking what was under it.

## Supported versions

Security fixes go into the latest release.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately through
[GitHub's private vulnerability reporting](https://github.com/salmansiddiqui17/glint/security/advisories/new).
Include steps to reproduce and the Glint and macOS versions. You should get a reply within a week.
