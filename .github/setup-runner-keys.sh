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

# Staleness guard (advisor-flagged, 2026-09-11): ublue-os HAS rotated this key
# before (git log --oneline -- cosign.pub upstream shows 2d50cf0f, one
# rotation in ~2 years) and will again. The failure mode if
# .github/ublue-os-cosign.pub ever goes stale is the exact cryptic
# "invalid signature" error that cost real diagnostic time today, and
# nothing else catches it before the build — build_scripts/base/20-tests.sh
# only asserts the SAME pin, but from *inside* the image, after the pull
# that would already have failed. Grep the pin out of that file (not a
# second hardcoded copy) so an upstream merge that updates it trips this
# assertion automatically with a self-describing error, instead of the pin
# silently drifting out of sync with a hand-maintained duplicate.
EXPECTED_SHA256=$(grep -oP 'KEY1_SHA256="\K[0-9a-f]{64}' build_scripts/base/20-tests.sh)
if [[ -z "${EXPECTED_SHA256}" ]]; then
  echo "setup-runner-keys.sh: could not extract KEY1_SHA256 from build_scripts/base/20-tests.sh — upstream may have renamed the variable; fix this script's grep pattern." >&2
  exit 1
fi
ACTUAL_SHA256=$(sha256sum .github/ublue-os-cosign.pub | cut -d' ' -f1)
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  echo "setup-runner-keys.sh: .github/ublue-os-cosign.pub (${ACTUAL_SHA256}) no longer matches ublue-os's current signing key pin (${EXPECTED_SHA256}, from build_scripts/base/20-tests.sh)." >&2
  echo "ublue-os likely rotated their cosign key. Fetch their current cosign.pub and update .github/ublue-os-cosign.pub." >&2
  exit 1
fi

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
