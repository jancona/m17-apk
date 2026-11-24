# m17-apk

Alpine Linux packages for [M17](https://m17project.org/) hotspots: m17-gateway, the web dashboard, HAT firmware and the SX1255 audio overlay. They're built for aarch64 (Raspberry Pi Zero 2 W and later) on Alpine 3.23, and used by [m17-hotspot-os](https://github.com/jancona/m17-hotspot-os); they install on any Alpine system.

## Packages

| Package | Contents |
|---|---|
| `m17-gateway` | [m17-gateway](https://github.com/jancona/m17), built from source: `/opt/m17/m17-gateway/`, its users and groups, a default `/etc/m17-gateway.ini` on first install |
| `m17-gateway-openrc` | The OpenRC service |
| `rpi-dashboard` | The [web dashboard](https://github.com/M17-Project/rpi-dashboard) in `/opt/m17/rpi-dashboard/`, with its settings in `/var/lib/m17-dashboard/`; an nginx site in `/usr/share/rpi-dashboard/` |
| `m17-firmware-cc1200` | [CC1200 HAT firmware](https://github.com/M17-Project/CC1200_HAT-fw) (latest release) |
| `m17-firmware-mmdvm-hs` | [MMDVM_HS](https://github.com/M17-Project/MMDVM_HS) firmware: MMDVM_HS_Hat, MMDVM_HS_Dual_Hat (and `-12mhz`), generic GPIO boards |
| `m17-firmware-mmdvm` | [MMDVM](https://github.com/M17-Project/MMDVM) firmware: Repeater-Builder, MMDVM_RPT_Hat, ZUM MMDVM-Pi, Nucleo |
| `m17-web` (+ `-openrc`) | The [web UI](https://github.com/jancona/m17-web) (setup wizard; was m17-admin), built from source; runs as its own user on 127.0.0.1:8090 |
| `m17-sx1255-overlay` | [`genericstereoaudiocodec.dtbo`](https://github.com/M17-Project/RaspberryPi_I2S_Slave) for the SX1255 HAT's I2S codec |

Firmware is installed under `/usr/share/m17-firmware/<family>/`; flashing it is up to the user (or, later, the hotspot's setup wizard).

## Using the repository

```bash
wget -O /etc/apk/keys/m17-apk.rsa.pub https://jancona.github.io/m17-apk/m17-apk.rsa.pub
echo "https://jancona.github.io/m17-apk/v3.23/m17" >> /etc/apk/repositories
apk update
apk add m17-gateway m17-gateway-openrc rpi-dashboard
```

Then set your callsign and modem in `/etc/m17-gateway.ini`, and start the gateway with `rc-update add m17-gateway && rc-service m17-gateway start`. For the dashboard, enable `php-fpm84` and nginx with the site from `/usr/share/rpi-dashboard/nginx-site.conf`, and set its admin password with `doas -u www-data php84 /opt/m17/rpi-dashboard/set_password.php`.

**Differences from the Debian packages:** the gateway's configuration lives in `/etc/m17-gateway/` (`/etc/m17-gateway.ini` links to it), and its host files are in `/var/lib/m17-gateway/`. The dashboard's `files/` links to the same host files, so the dashboard's "Update hostfile" button updates the ones the gateway reads. The dashboard uses `procps`'s `pgrep`: BusyBox's `pgrep -x` doesn't find the gateway.

## Building

Every push builds all packages in an `alpine:3.23` container on an arm64 runner and test-installs them. Pushes to `main` are signed with the repository key and published to GitHub Pages; pull requests are built with a throwaway key.

Locally (Docker, arm64 or with qemu-user):

```bash
scripts/build-in-docker.sh out              # every package
scripts/build-in-docker.sh out m17-gateway  # one package
```

A local build is signed with a throwaway key whose public half is put in `out/`.

### Updating a package

1. Change `pkgver` (and `_commit` where there is one) in `packages/m17/<name>/APKBUILD`, and reset `pkgrel` to 0. For a packaging-only change, bump `pkgrel` instead.
2. Run `scripts/update-checksums.sh <name>` to download the new sources and write their checksums. Check the diff: this is the moment the new sources are trusted.
3. Commit; CI builds, tests and publishes.

m17-gateway is built with `GOTOOLCHAIN=auto` because its `go.mod` asks for a newer Go than Alpine 3.23 ships; the toolchain and modules are verified against the Go checksum database.

### Upstream updates

A daily workflow ([`check-upstream.yml`](.github/workflows/check-upstream.yml), also runnable by hand) runs `scripts/check-upstream.sh` to find newer upstream versions: a new release of m17-gateway or the CC1200 firmware, a new rpi-dashboard commit, or a new commit that changed the MMDVM / MMDVM_HS `release/` folder or the SX1255 overlay. It updates the APKBUILDs, recomputes the checksums, builds and test-installs everything, then opens (or updates) one "Upstream updates" pull request. Merging it publishes the packages; m17-hotspot-os's weekly check then builds a new OS release with them.

If a firmware repository adds or removes a board's file, the pull request (or the run's summary) says so: those lists are updated by hand. Snapshot versions never go down: a second commit on the same day bumps `pkgrel`.

Pull requests opened by the workflow don't start the build workflow (GitHub doesn't let one workflow's `GITHUB_TOKEN` trigger another), which is why the check builds and tests before opening one.

### Signing key

The index is signed with an abuild RSA key. The public key is [`keys/m17-apk.rsa.pub`](keys/m17-apk.rsa.pub); the private key is the repository secret `ABUILD_PRIVATE_KEY`.

## License

The packaging in this repository is GPL-2.0. Each package's license is in its APKBUILD and is installed under `/usr/share/licenses/`.
