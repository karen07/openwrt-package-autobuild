# OpenWrt Package Autobuild

Этот скрипт собирает мои пакеты для OpenWrt с помощью официального OpenWrt SDK.

Он может подключаться к роутеру по SSH, определять целевую архитектуру OpenWrt, скачивать подходящий SDK, клонировать исходники пакетов с GitHub, собирать пакеты, а затем либо устанавливать их на роутер, либо сохранять APK-файлы локально.

## Доступные пакеты

- antiblock
- yubikey-hack
- dns-client-test
- domains-block-test
- dns-server-test
- luci-app-antiblock
- QUICTun
- all

## Использование

```sh
./auto_install.sh install <package> <router>
./auto_install.sh build-router <package> <router> <version> [output-dir]
./auto_install.sh build-target <package> <version> <target> <subtarget> <pkgarch> [output-dir]
```

## Примеры

Собрать и установить один пакет на роутер:

```sh
./auto_install.sh install antiblock router
```

Собрать и установить все пакеты на роутер:

```sh
./auto_install.sh install all router
```

Собрать все пакеты для той же цели, что и у роутера, но сохранить APK-файлы локально:

```sh
./auto_install.sh build-router all router 25.12.4
```

Сохранить APK-файлы в указанную директорию:

```sh
./auto_install.sh build-router all router 25.12.4 release
```

Собрать без подключения к роутеру:

```sh
./auto_install.sh build-target all 25.12.4 x86 64 x86_64 release
```

## Владелец GitHub

По умолчанию репозитории клонируются из `karen07`.

Это можно переопределить так:

```sh
GITHUB_OWNER=someuser ./auto_install.sh build-router all router 25.12.4
```
