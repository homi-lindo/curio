#!/bin/sh
# Plug-and-play TLS for the Curió sync server.
#
# On first run, auto-generates a self-signed certificate into the data volume
# and enables HTTPS, unless the operator disables it (LUME_SYNC_TLS_AUTO=0) or
# already provided a certificate (LUME_SYNC_TLS_CERT/KEY). Devices trust this
# certificate by pinning its fingerprint (printed by the server at startup), so
# no public CA or reverse proxy is needed.
set -eu

AUTO="${LUME_SYNC_TLS_AUTO:-1}"
DATA_DIR="$(dirname "${LUME_SYNC_FILE:-/data/server-state.json}")"
CERT="${LUME_SYNC_TLS_CERT:-$DATA_DIR/auto-cert.pem}"
KEY="${LUME_SYNC_TLS_KEY:-$DATA_DIR/auto-key.pem}"

if [ "$AUTO" != "0" ] && [ -z "${LUME_SYNC_TLS_CERT:-}" ]; then
  mkdir -p "$DATA_DIR"
  if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    echo "Curió sync: generating self-signed certificate at $CERT"
    CN="${LUME_SYNC_PUBLIC_HOST:-curio-sync}"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout "$KEY" -out "$CERT" -subj "/CN=$CN" >/dev/null 2>&1
  fi
  export LUME_SYNC_TLS_CERT="$CERT"
  export LUME_SYNC_TLS_KEY="$KEY"
fi

exec /usr/local/bin/lume_sync_server "$@"
