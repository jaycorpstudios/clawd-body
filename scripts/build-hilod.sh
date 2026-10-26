#!/bin/bash
# Release build of hilod and hilo, signed with a local self-signed identity so macOS keeps
# hilod's Bluetooth permission across rebuilds (an ad-hoc signature changes on every build).
set -eu
identity="Hilo Local Signing"
cd "$(dirname "$0")/../daemon"

if ! security find-certificate -c "$identity" >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$identity" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$identity" \
    -passout pass:hilo -out "$tmp/id.p12"
  security import "$tmp/id.p12" -P hilo -T /usr/bin/codesign
  echo "created signing identity '$identity' in the login keychain"
fi

swift build -c release
for bin in hilod hilo; do
  codesign --force --sign "$identity" --identifier "dev.hilo.$bin" ".build/release/$bin"
done
codesign -dr - .build/release/hilod 2>&1 | grep designated
