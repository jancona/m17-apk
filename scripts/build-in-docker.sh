#!/bin/sh
# build-in-docker.sh - run scripts/build.sh in an Alpine arm64 container
# Usage: scripts/build-in-docker.sh OUTPUT_DIR [PACKAGE...]
set -eu
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT="${1:?usage: build-in-docker.sh OUTPUT_DIR [PACKAGE...]}"
shift
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
exec docker run --rm --platform linux/arm64 \
	-v "$REPO_DIR":/repo:ro -v "$OUT":/out \
	${ABUILD_PRIVATE_KEY:+-e ABUILD_PRIVATE_KEY} \
	"alpine:${ALPINE_VERSION:-3.23}" sh /repo/scripts/build.sh /out "$@"
