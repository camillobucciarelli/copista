# Security Policy

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub Security Advisories:
https://github.com/camillobucciarelli/copista/security/advisories/new

Include: affected version, reproduction steps, and the impact you believe the
issue has.

## Response

This project is maintained by a single developer in their spare time. Best
effort targets, not guarantees: acknowledgement within 7 days, initial
assessment within 14 days, fix or documented mitigation for confirmed
high-severity issues within 90 days. Please allow a fix to ship before public
disclosure. There is no bug bounty program.

## Supported versions

Only the latest released version receives security fixes.

## Security model

Copista keeps the clipboard history only on the local Mac, makes no network
connections and skips entries marked as confidential by password managers. The
history is stored as unencrypted text; it does not protect against a
compromised operating system or an attacker with access to the user's account.
