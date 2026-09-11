#!/usr/bin/env bash

# Setup Public Keys for containers that are pulled during the build
#
# jcrben fork (2026-09-11): this script's `ghcr.io/ublue-os` key is for
# VERIFYING PULLS FROM UPSTREAM (akmods, base images) — a completely
# different trust relationship from the repo root `cosign.pub`, which is
# OUR OWN signing key for OUR OWN published images. The upstream template
# conflates the two (`cp cosign.pub ...`), which is harmless on
# ublue-os/aurora itself (their cosign.pub genuinely IS ublue-os's key) but
# breaks every upstream pull the moment a fork replaces cosign.pub with its
# own identity, per the template's own setup instructions. Root-caused
# 2026-09-11 after two builds failed identical "invalid signature" errors
# pulling ghcr.io/ublue-os/akmods, immediately following the cosign.pub swap
# in ae5e70d6 — a fixed, dedicated copy of ublue-os's own key
# (.github/ublue-os-cosign.pub, recovered from git history predating that
# commit) decouples the two so replacing our own signing key never again
# breaks upstream pull verification.

set -eoux pipefail

PKI_DIR="/etc/pki/containers"
REGISTRIES="/etc/containers/registries.d"

mkdir -p "${PKI_DIR}" "${REGISTRIES}"
cp .github/ublue-os-cosign.pub "${PKI_DIR}/ghcr.io-ublue-os.pub"
cp quay.io-fedora-ostree-desktops.pub "${PKI_DIR}"

yq -n '.docker."ghcr.io/ublue-os".use-sigstore-attachments = true' | tee "${REGISTRIES}"/ublue-os.yaml
yq -n '.docker."quay.io/fedora-ostree-desktops".use-sigstore-attachments = true' | tee "${REGISTRIES}"/fedora-ostree-desktops.yaml

jq '.transports.docker["ghcr.io/ublue-os"] = [
  {
    "type": "sigstoreSigned",
    "keyPath": "/etc/pki/containers/ghcr.io-ublue-os.pub",
    "signedIdentity": {
      "type": "matchRepository"
    }
  }
] |
.transports.docker["quay.io/fedora-ostree-desktops"] = [
  {
    "type": "sigstoreSigned",
    "keyPath": "/etc/pki/containers/quay.io-fedora-ostree-desktops.pub",
    "signedIdentity": {
      "type": "matchRepository"
    }
  }
]' /etc/containers/policy.json | tee /etc/containers/policy.json.tmp > /dev/null && mv /etc/containers/policy.json.tmp /etc/containers/policy.json
