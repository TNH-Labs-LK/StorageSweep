# Security Policy

Storage Sweep moves files to the Trash, so we take bugs that could remove the wrong files seriously.

## Supported versions

Only the latest release gets fixes.

## Reporting a problem

**Please don't open a public issue for security problems.**

Report them privately instead:

- Use GitHub's **[Report a vulnerability](https://github.com/TNH-Labs-LK/StorageSweep/security/advisories/new)** button on the Security tab.

Please include what you found, how to reproduce it and which macOS version you used. You'll get a reply within 7 days, and you'll be credited in the release notes unless you'd rather not be.

## What counts

- The app removing or offering to remove something outside what the user selected
- A protected path (system folders, Keychains, `.ssh`, main home folders) being selectable
- Anything that sends data off the user's Mac
