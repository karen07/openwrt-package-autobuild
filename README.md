# OpenWrt Package Autobuild

This script builds packages from my repositories for OpenWrt.

It connects to the router over SSH, detects the OpenWrt version and target architecture, downloads the matching SDK, clones the package sources, builds the package, and installs it on the router over SSH.

## Available packages

- antiblock
- yubikey-hack
- dns-client-test
- domains-block-test
- dns-server-test
- luci-app-antiblock
- QUICTun
