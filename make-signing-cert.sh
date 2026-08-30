#!/usr/bin/env bash
set -euo pipefail

# Creates a free, self-signed code-signing certificate and trusts it for your
# user account. Run this once.
#
# Why it exists: an ad-hoc signed build has no stable identity, so macOS
# identifies it by the exact hash of its code. Change a line, rebuild, and the
# Keychain sees a different program asking for your Spotify token — hence the
# "FloatingLyric wants to use your confidential information" prompt, over and
# over. A certificate gives every build the same identity, so you approve once.
#
# This is NOT an Apple Developer ID. It stops the Keychain prompts on this Mac.
# It does not stop Gatekeeper warning on someone else's Mac — only a paid
# Developer ID does that (see README).

NAME="FloatingLyric Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
  echo "==> \"$NAME\" already exists — nothing to do."
  echo "    Build with it:  ./build.sh"
  exit 0
fi

command -v openssl >/dev/null || { echo "openssl not found"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

echo "==> Generating a 10-year self-signed code-signing certificate"
# extendedKeyUsage=codeSigning is what makes codesign accept it at all.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME/O=FloatingLyric/C=US" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout pass: 2>/dev/null

echo "==> Importing it into your login keychain"
# -T lets codesign use the private key without asking every single build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> Trusting it for code signing"
echo "    macOS will ask for your login password — that is this step, and it"
echo "    is the only one that needs it."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
if security find-identity -v -p codesigning | grep -qF "$NAME"; then
  echo "Done. \"$NAME\" is ready."
  echo
  echo "Now run:  ./build.sh"
  echo "It picks the certificate up on its own."
  echo
  echo "The first build may ask once for permission to use the signing key —"
  echo "click \"Always Allow\". After that, neither prompt comes back."
else
  echo "The certificate was created but is not showing as a valid identity."
  echo "Open Keychain Access, find \"$NAME\", and set Trust -> Code Signing"
  echo "to \"Always Trust\"."
  exit 1
fi
