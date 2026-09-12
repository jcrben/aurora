#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Rebuilds drkonqi-coredump-launcher with an upstream-bound fix for a real,
# reproduced KCrash-metadata race (crash reports/coredumps never reach
# Sentry/the crash handler): the launcher checks for KCrash's own sidecar
# metadata file exactly once and gives up before the write lands, always
# losing the race. Root-caused with gdb on a live crash on iridium14,
# 2026-09-11 (dotfiles mystery 237a5f, todo e161c2 in ~/code/todos). Patch
# authored, validated against a standalone unit test AND a real QTest
# autotest in a dedicated toolbox, and pinned to the exact shipped version
# (plasma-drkonqi-6.7.4-1.fc44) in jcrben/drkonqi commit e537cb9a. This step
# exists purely to let Ben self-validate the fix on real hardware before
# the upstream MR to invent.kde.org/plasma/drkonqi lands and reaches Aurora
# normally -- remove it once that MR ships.

DRKONQI_REF="v6.7.4"
DRKONQI_SRC="/tmp/drkonqi-build"
PATCH="/ctx/build_scripts/patches/drkonqi/0001-coredump-launcher-retry-resolving-KCrash-metadata.patch"

# dnf5 builddep reads the real Fedora spec's BuildRequires -- the correct,
# authoritative dependency set for this exact shipped package, rather than
# a hand-guessed list. The base image already carries the KF6/Qt6 *runtime*
# (it's a KDE Plasma image); only -devel headers + build tools are net-new,
# and are removed again below so they don't bloat the final image.
BEFORE_PKGS="$(mktemp)"
AFTER_PKGS="$(mktemp)"
rpm -qa --qf '%{NAME}\n' | sort > "${BEFORE_PKGS}"

dnf5 -y install dnf5-plugins
dnf5 -y builddep plasma-drkonqi
dnf5 -y install git-core cmake ninja-build

git clone --branch "${DRKONQI_REF}" --depth 1 https://invent.kde.org/plasma/drkonqi.git "${DRKONQI_SRC}"
git -C "${DRKONQI_SRC}" apply --verbose "${PATCH}"

cmake -S "${DRKONQI_SRC}" -B "${DRKONQI_SRC}/build" -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_TESTING=OFF
cmake --build "${DRKONQI_SRC}/build" --target drkonqi-coredump-launcher

BUILT_BIN="$(find "${DRKONQI_SRC}/build" -type f -name drkonqi-coredump-launcher -executable)"
[ -n "${BUILT_BIN}" ] || { echo "05-drkonqi-crash-fix.sh: build did not produce a drkonqi-coredump-launcher binary" >&2; exit 1; }
install -Dm0755 "${BUILT_BIN}" /usr/libexec/drkonqi-coredump-launcher

rm -rf "${DRKONQI_SRC}"

# Remove only what this script itself installed -- never the runtime KDE
# packages the base image shipped with.
rpm -qa --qf '%{NAME}\n' | sort > "${AFTER_PKGS}"
comm -13 "${BEFORE_PKGS}" "${AFTER_PKGS}" | xargs -r dnf5 -y remove
rm -f "${BEFORE_PKGS}" "${AFTER_PKGS}"

echo "::endgroup::"
