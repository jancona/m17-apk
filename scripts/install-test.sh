#!/bin/sh
# install-test.sh - install every package from a built repository in a
# fresh Alpine container and check the result
# Usage: scripts/install-test.sh REPO_DIR   (the output of build.sh)
set -eu
OUT=$(cd "${1:?usage: install-test.sh REPO_DIR}" && pwd)
exec docker run --rm --platform linux/arm64 -v "$OUT":/repo:ro "alpine:${ALPINE_VERSION:-3.23}" sh -c '
	set -e
	cp /repo/*.rsa.pub /etc/apk/keys/
	echo /repo/m17 >> /etc/apk/repositories
	apk add -q --no-cache rpi-dashboard m17-gateway-openrc m17-firmware-cc1200 \
		m17-firmware-mmdvm m17-firmware-mmdvm-hs m17-sx1255-overlay m17-web m17-web-openrc
	/opt/m17/m17-gateway/m17-gateway -h 2>&1 | grep -q -- -config
	test -f /etc/m17-gateway/m17-gateway.ini
	test -L /etc/m17-gateway.ini
	su -s /bin/sh www-data -c "test -w /etc/m17-gateway.ini && test -w /var/lib/m17-gateway/M17Hosts.txt"
	test -f /boot/firmware/overlays/genericstereoaudiocodec.dtbo
	test -n "$(ls /usr/share/m17-firmware/mmdvm_hs/)"
	test -n "$(ls /usr/share/m17-firmware/mmdvm/)"
	test -f /usr/share/m17-firmware/cc1200/CC1200_HAT-fw.bin
	apk info -v | grep -E "^(m17|rpi-dashboard)" | sort
	/usr/bin/m17-web -h 2>&1 | grep -q -- -state-dir
	id m17-web | grep -q dialout
	test "$(stat -c %U:%a /var/lib/m17-web)" = "m17-web:700"
	test -x /etc/init.d/m17-web
	echo "install test passed"
'
