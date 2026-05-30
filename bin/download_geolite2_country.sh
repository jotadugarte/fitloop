#!/usr/bin/env bash
# Downloads MaxMind GeoLite2-Country and extracts GeoLite2-Country.mmdb into storage/geoip/.
# Requires a free MaxMind account: https://www.maxmind.com/en/geolite2/signup
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LICENSE_KEY="${MAXMIND_LICENSE_KEY:-}"
if [[ -z "${LICENSE_KEY}" ]]; then
  echo "Set MAXMIND_LICENSE_KEY (from MaxMind account → Manage License Keys)." >&2
  exit 1
fi

DEST_DIR="${GEOLITE2_COUNTRY_MMDB_PATH:-${ROOT}/storage/geoip}"
if [[ "${DEST_DIR}" == */GeoLite2-Country.mmdb ]]; then
  MMDB_FILE="${DEST_DIR}"
  DEST_DIR="$(dirname "${MMDB_FILE}")"
else
  MMDB_FILE="${DEST_DIR}/GeoLite2-Country.mmdb"
fi

mkdir -p "${DEST_DIR}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

ARCHIVE="${TMP}/GeoLite2-Country.tar.gz"
URL="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=${LICENSE_KEY}&suffix=tar.gz"

echo "Downloading GeoLite2-Country…"
curl -fsSL -o "${ARCHIVE}" "${URL}"
tar -xzf "${ARCHIVE}" -C "${TMP}"

FOUND="$(find "${TMP}" -name 'GeoLite2-Country.mmdb' -print -quit)"
if [[ -z "${FOUND}" ]]; then
  echo "GeoLite2-Country.mmdb not found in archive." >&2
  exit 1
fi

cp "${FOUND}" "${MMDB_FILE}"
echo "Installed ${MMDB_FILE}"
echo "Set in production ENV: GEOLITE2_COUNTRY_MMDB_PATH=${MMDB_FILE}"
