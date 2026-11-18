#!/bin/sh
# update-checksums.sh - download each package's sources and write their
# sha512sums into its APKBUILD (abuild checksum), in an Alpine container.
# Run after changing a version or a source. Review the diff: it's the
# moment the sources are trusted.
# Usage: scripts/update-checksums.sh [PACKAGE...]
set -eu
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
exec docker run --rm -i --platform linux/arm64 -v "$REPO_DIR":/repo \
	"alpine:${ALPINE_VERSION:-3.23}" sh -s "$@" <<'INNER'
set -eu
apk add -q --no-cache abuild >/dev/null
adduser -D -G abuild builder
cd /repo/packages
if [ $# -eq 0 ]; then set -- $(ls -d */* | sed 's|.*/||'); fi
for pkg in "$@"; do
	dir=$(ls -d */"$pkg" | head -1)
	cp -r "$dir" "/home/builder/$pkg"
	chown -R builder "/home/builder/$pkg"
	su builder -c "cd /home/builder/$pkg && abuild checksum" >/dev/null
	cp "/home/builder/$pkg/APKBUILD" "$dir/APKBUILD"
	echo "$pkg: checksums updated"
done
INNER
