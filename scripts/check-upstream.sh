#!/bin/sh
# check-upstream.sh - update APKBUILDs to the latest upstream versions
# Part of m17-apk. Needs gh (authenticated; GH_TOKEN in CI) and jq.
#
# Usage: scripts/check-upstream.sh [REPORT_FILE]
#
# Changes pkgver/_commit/pkgrel in place for every package with a newer
# upstream, and writes a Markdown report (default: stdout) listing the
# changes and anything that needs a human. Checksums are not updated here:
# run scripts/update-checksums.sh on the changed packages afterwards.
#
# How each package tracks upstream:
#   m17-gateway           latest release of jancona/m17 (vX.Y.Z)
#   m17-firmware-cc1200   latest release of M17-Project/CC1200_HAT-fw
#   rpi-dashboard         latest commit; pkgver <VERSION file>_git<date>
#   m17-firmware-mmdvm-hs last commit that changed release/ in MMDVM_HS
#   m17-firmware-mmdvm    last commit that changed release/ in MMDVM
#   m17-sx1255-overlay    last commit that changed the .dtbo
# For git snapshots, a new commit on the same day as the pinned one bumps
# pkgrel, so the version still goes up.

set -eu

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
PKGS="$REPO_DIR/packages/m17"
REPORT="${1:-/dev/stdout}"
CHANGED=""
NOTES=""
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
LIST="$TMPD/list"
: > "$LIST"

get_var() { sed -n "s/^$2=//p" "$PKGS/$1/APKBUILD" | head -1 | tr -d '"'; }
set_var() {
	f="$PKGS/$1/APKBUILD"
	sed "s|^$2=.*|$2=$3|" "$f" > "$f.new" && mv "$f.new" "$f"
}
note() { NOTES="$NOTES
- $*"; }
changed() { # changed PKG OLD NEW
	CHANGED="$CHANGED $1"
	echo "- **$1**: $2 → $3" >> "$LIST"
}

commit_date() { # commit_date REPO SHA -> YYYYMMDD
	gh api "repos/$1/commits/$2" --jq '.commit.committer.date' | cut -c1-10 | tr -d -
}

# contains REPO PINNED SHA - true if PINNED already includes SHA
contains() {
	[ "$2" = "$3" ] && return 0
	status=$(gh api "repos/$1/compare/$3...$2" --jq '.status')
	[ "$status" = "ahead" ] || [ "$status" = "identical" ]
}

update_release() { # update_release PKG REPO
	tag=$(gh api "repos/$2/releases/latest" --jq '.tag_name')
	new="${tag#v}"
	old=$(get_var "$1" pkgver)
	case "$new" in
		""|*[!0-9A-Za-z._]*) note "$1: could not read the latest release of $2 ('$tag')"; return ;;
	esac
	[ "$new" = "$old" ] && return
	set_var "$1" pkgver "$new"
	set_var "$1" pkgrel 0
	changed "$1" "$old" "$new"
}

update_snapshot() { # update_snapshot PKG REPO PATH PREFIX
	pkg="$1"; repo="$2"; path="$3"; prefix="$4"
	if [ -n "$path" ]; then
		latest=$(gh api -X GET "repos/$repo/commits" -f path="$path" -f per_page=1 --jq '.[0].sha')
	else
		latest=$(gh api "repos/$repo/commits/HEAD" --jq '.sha')
	fi
	pinned=$(get_var "$pkg" _commit)
	[ -n "$latest" ] || { note "$pkg: could not read commits of $repo"; return; }
	contains "$repo" "$pinned" "$latest" && return

	old=$(get_var "$pkg" pkgver)
	oldrel=$(get_var "$pkg" pkgrel)
	if [ "$prefix" = VERSION ]; then
		prefix=$(gh api "repos/$repo/contents/VERSION?ref=$latest" -H "Accept: application/vnd.github.raw" | tr -d ' \r\n')
		case "$prefix" in ""|*[!0-9.]*) note "$pkg: unusable VERSION file at $latest"; return ;; esac
	fi
	newdate=$(commit_date "$repo" "$latest")
	new="${prefix}_git$newdate"
	set_var "$pkg" _commit "$latest"
	# Never lower the version: a new commit dated the same day as (or, if
	# the pins were inconsistent, before) the current snapshot bumps pkgrel
	olddate="${old##*_git}"
	if [ "$new" = "$old" ] || { [ "${old%_git*}" = "$prefix" ] && [ "$newdate" -le "$olddate" ] 2>/dev/null; }; then
		new="$old"
		set_var "$pkg" pkgrel $((oldrel + 1))
		changed "$pkg" "$old-r$oldrel" "$new-r$((oldrel + 1)) (${latest%"${latest#???????}"})"
	else
		set_var "$pkg" pkgver "$new"
		set_var "$pkg" pkgrel 0
		changed "$pkg" "$old" "$new (${latest%"${latest#???????}"})"
	fi
}

# check_files PKG REPO DIR - note if the files in DIR upstream differ from
# the ones the APKBUILD lists (a board added or removed)
check_files() {
	pkg="$1"; repo="$2"; dir="$3"
	commit=$(get_var "$pkg" _commit)
	upstream=$(gh api "repos/$repo/contents/$dir?ref=$commit" --jq '.[] | select(.type == "file") | .name' | sort)
	listed=$(sed -n "s|.*/$dir/\([^/ ]*\)$|\1|p" "$PKGS/$pkg/APKBUILD" | sort)
	if [ "$upstream" != "$listed" ]; then
		added=$(printf '%s\n' "$upstream" | grep -vxF "$listed" | tr '\n' ' ')
		removed=$(printf '%s\n' "$listed" | grep -vxF "$upstream" | tr '\n' ' ')
		note "$pkg: $dir/ upstream differs from the APKBUILD's list. Added: ${added:-none}. Removed: ${removed:-none}. Update source= and package() by hand."
	fi
}

update_release m17-gateway jancona/m17
update_release m17-firmware-cc1200 M17-Project/CC1200_HAT-fw
update_snapshot rpi-dashboard M17-Project/rpi-dashboard "" VERSION
update_snapshot m17-firmware-mmdvm-hs M17-Project/MMDVM_HS release 0
update_snapshot m17-firmware-mmdvm M17-Project/MMDVM release 0
update_snapshot m17-sx1255-overlay M17-Project/RaspberryPi_I2S_Slave genericstereoaudiocodec.dtbo 0
check_files m17-firmware-mmdvm-hs M17-Project/MMDVM_HS release
check_files m17-firmware-mmdvm M17-Project/MMDVM release

{
	if [ -s "$LIST" ]; then
		echo "## Upstream updates"
		echo
		cat "$LIST"
	else
		echo "All packages are up to date."
	fi
	if [ -n "$NOTES" ]; then
		echo
		echo "## Needs attention"
		echo "$NOTES"
	fi
} > "$TMPD/report"
cat "$TMPD/report" > "$REPORT"

# For the workflow: the packages that changed, space-separated
echo "${CHANGED# }" > "${CHANGED_FILE:-/dev/null}"
