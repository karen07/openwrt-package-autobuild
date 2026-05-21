# OpenWrt Package Autobuild

This script builds my packages for OpenWrt using the official OpenWrt SDK.

It can connect to the router over SSH, detect the OpenWrt target architecture, download the matching SDK, clone package sources from GitHub, build packages, and either install them on the router or save APK files locally.

## Available packages

- antiblock
- yubikey-hack
- dns-client-test
- domains-block-test
- dns-server-test
- luci-app-antiblock
- QUICTun
- all

## Usage

```sh
./auto_install.sh install <package> <router>
./auto_install.sh build-router <package> <router> <version> [output-dir]
./auto_install.sh build-target <package> <version> <target> <subtarget> <pkgarch> [output-dir]
```

## Examples

Build and install one package on a router:

```sh
./auto_install.sh install antiblock router
```

Build and install all packages on a router:

```sh
./auto_install.sh install all router
```

Build all packages for the same target as the router, but save APK files locally:

```sh
./auto_install.sh build-router all router 25.12.4
```

Save APK files to a specific directory:

```sh
./auto_install.sh build-router all router 25.12.4 release
```

Build without connecting to a router:

```sh
./auto_install.sh build-target all 25.12.4 x86 64 x86_64 release
```

## GitHub owner

By default, repositories are cloned from `karen07`.

You can override it with:

```sh
GITHUB_OWNER=someuser ./auto_install.sh build-router all router 25.12.4
```
