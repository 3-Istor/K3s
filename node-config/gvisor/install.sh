#!/usr/bin/env bash
# Installs gVisor on a K3s node. Idempotent. Run as root on the node; it does
# not restart K3s (see README.md: one node at a time).
set -euo pipefail

version=20261116.0
sha512=a34261504066142b6c1cc4d1813bb2d092761675416e350edc98c4cc66469b63b6f41acdeed09681b6c717c00e80e437f5f2f9c8d37705b8a9260632867c2b7d
url="https://storage.googleapis.com/gvisor/releases/release/${version}/x86_64/gvisor.tar.zstd"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/gvisor.tar.zstd" "$url"
echo "${sha512}  $work/gvisor.tar.zstd" | sha512sum -c --quiet
tar --zstd -xf "$work/gvisor.tar.zstd" -C "$work" runsc containerd-shim-runsc-v1

install -m 0755 "$work/runsc" "$work/containerd-shim-runsc-v1" /usr/local/bin/
install -D -m 0644 "$here/runsc.toml" /etc/containerd/runsc.toml
install -D -m 0644 "$here/gvisor.toml" \
  /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/gvisor.toml

/usr/local/bin/runsc --version | head -1
