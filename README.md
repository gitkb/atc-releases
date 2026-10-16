# ATC

**Agent Traffic Control for AI coding agents.**

ATC is a headless meta harness and session control plane for AI coding agents. It lowers tasks, templates, and prompts into provider-native agent sessions, tracks dispatch evidence in a local registry, and keeps review and merge decisions human-visible.

```bash
brew install gitkb/tap/atc
```

This repository publishes ATC release assets and the install script. No GitHub account or token is needed to install.

## Install Options

| Method | Command |
|--------|---------|
| Homebrew | `brew install gitkb/tap/atc` |
| Install script | `curl -fsSL https://raw.githubusercontent.com/gitkb/atc-releases/main/install.sh \| bash` |
| Specific version | `VERSION=x.y.z curl -fsSL https://raw.githubusercontent.com/gitkb/atc-releases/main/install.sh \| bash` |
| Custom directory | `INSTALL_DIR=/usr/local/bin curl -fsSL https://raw.githubusercontent.com/gitkb/atc-releases/main/install.sh \| bash` |

The install script puts `atc` and its `atc-productionize` sidecar in `~/.local/bin`. On macOS, it also places the signed `ATC Hotkey.app` in `~/.local/libexec`, where `atc` finds it.

Each release archive has a `.sha256` file next to it on the [releases page](https://github.com/gitkb/atc-releases/releases); the install script verifies it before installing.

## Platforms

| OS | Architectures |
|----|---------------|
| macOS | Apple silicon (arm64), Intel (x64) |
| Linux (glibc 2.28+) | arm64, x64 |

## Get Started

```bash
atc --help
```

ATC works with [GitKB](https://github.com/gitkb/gitkb-releases): GitKB Desktop installs and updates ATC for you.

## Issues

Found a problem? [Open an issue](https://github.com/gitkb/atc-releases/issues/new/choose).
