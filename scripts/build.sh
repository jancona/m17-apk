#!/bin/sh
# build.sh - build the packages and a signed APK repository
# Part of m17-apk. Runs as root inside an alpine:<version> container (CI,
# or scripts/build-in-docker.sh); the packages themselves are built by an
# unprivileged user, as abuild requires.
#
# Usage: scripts/build.sh OUTPUT_DIR [PACKAGE...]
#
# OUTPUT_DIR gets <repo>/<arch>/*.apk and a signed APKINDEX.tar.gz, e.g.
# OUTPUT_DIR/m17/aarch64/. With no PACKAGE names, every package under
# packages/ is built.
#
# Signing key: if ABUILD_PRIVATE_KEY is set (CI), it is used with the
# public key keys/$KEY_NAME.pub. Otherwise a throwaway key is generated, so
# a local build works but its index isn't trusted by real installs.

set -eu

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT="${1:?usage: build.sh OUTPUT_DIR [PACKAGE...]}"
shift
KEY_NAME="${KEY_NAME:-m17-apk.rsa}"
BUILDER=builder

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

apk add -q --no-cache alpine-sdk >/dev/null
id "$BUILDER" >/dev/null 2>&1 || adduser -D -G abuild "$BUILDER"
# Members of the abuild group install build dependencies through
# abuild-sudo; nothing else runs as root

HOME_DIR=$(getent passwd "$BUILDER" | cut -d: -f6)
mkdir -p "$HOME_DIR/.abuild"
if [ -n "${ABUILD_PRIVATE_KEY:-}" ]; then
	printf '%s\n' "$ABUILD_PRIVATE_KEY" > "$HOME_DIR/.abuild/$KEY_NAME"
	cp "$REPO_DIR/keys/$KEY_NAME.pub" "$HOME_DIR/.abuild/$KEY_NAME.pub"
	echo "==> Signing with $KEY_NAME"
else
	openssl genrsa -out "$HOME_DIR/.abuild/$KEY_NAME" 4096 2>/dev/null
	openssl rsa -in "$HOME_DIR/.abuild/$KEY_NAME" -pubout -out "$HOME_DIR/.abuild/$KEY_NAME.pub" 2>/dev/null
	echo "==> No ABUILD_PRIVATE_KEY: signing with a throwaway key"
	# An index left by an earlier run was signed with a different
	# throwaway key and can't be added to, so start from nothing
	rm -rf "${OUT:?}"/*
fi
chmod 600 "$HOME_DIR/.abuild/$KEY_NAME"
echo "PACKAGER_PRIVKEY=\"$HOME_DIR/.abuild/$KEY_NAME\"" > "$HOME_DIR/.abuild/abuild.conf"
# Install-time checks (abuild -r) need the key too
cp "$HOME_DIR/.abuild/$KEY_NAME.pub" /etc/apk/keys/

# Build from a copy the builder owns
rm -rf "$HOME_DIR/src"
cp -r "$REPO_DIR/packages" "$HOME_DIR/src"
chown -R "$BUILDER:abuild" "$HOME_DIR" "$OUT"

if [ $# -eq 0 ]; then
	# shellcheck disable=SC2046  # package names have no spaces
	set -- $(cd "$HOME_DIR/src" && ls -d */* | sed 's|.*/||')
fi

for pkg in "$@"; do
	dir=$(cd "$HOME_DIR/src" && ls -d */"$pkg" 2>/dev/null | head -1)
	[ -n "$dir" ] || { echo "No package named $pkg" >&2; exit 1; }
	echo "==> Building $dir"
	su "$BUILDER" -c "cd '$HOME_DIR/src/$dir' && REPODEST='$OUT' abuild -r"
done

# The public key next to the index, for anyone setting up the repository
cp "$HOME_DIR/.abuild/$KEY_NAME.pub" "$OUT/"
echo "==> Repository:"
find "$OUT" -type f | sort
