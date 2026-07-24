#!/bin/zsh
# Create the stable local code-signing identity used by build-app.sh.
set -eu

SIGNING_NAME="restore-layout-dev"

if security find-identity -v -p codesigning 2>/dev/null \
    | grep -Fq "\"$SIGNING_NAME\""; then
  echo "✓ Code-signing identity '$SIGNING_NAME' already exists."
  exit 0
fi

LOGIN_KEYCHAIN="$(
  security default-keychain -d user 2>/dev/null | tr -d '\"' | xargs
)"
if [[ -z "$LOGIN_KEYCHAIN" ]]; then
  LOGIN_KEYCHAIN="$(
    security login-keychain -d user 2>/dev/null | tr -d '\"' | xargs
  )"
fi

CERT_DIR="$(mktemp -d /tmp/restore-layout-dev-cert.XXXXXX)"
trap 'rm -rf "$CERT_DIR"' EXIT
IMPORT_PASSWORD="restore-layout-local-import"

echo "→ Creating a ten-year self-signed code-signing certificate…"
if ! openssl req -new -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
    -subj "/CN=$SIGNING_NAME/O=RestoreLayout Development/" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$CERT_DIR/private-key.pem" \
    -out "$CERT_DIR/certificate.pem"; then
  echo "OpenSSL could not create the certificate." >&2
  exit 1
fi

openssl pkcs12 -export -legacy \
  -inkey "$CERT_DIR/private-key.pem" \
  -in "$CERT_DIR/certificate.pem" \
  -name "$SIGNING_NAME" \
  -passout "pass:$IMPORT_PASSWORD" \
  -out "$CERT_DIR/identity.p12"

if ! security import "$CERT_DIR/identity.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$IMPORT_PASSWORD" \
    -T /usr/bin/codesign; then
  FALLBACK_IDENTITY="/tmp/restore-layout-dev-identity.p12"
  cp "$CERT_DIR/identity.p12" "$FALLBACK_IDENTITY"
  echo ""
  echo "Automatic Keychain import failed. In Keychain Access:"
  echo "  1. Select the login keychain."
  echo "  2. Import $FALLBACK_IDENTITY."
  echo "  3. Use password: $IMPORT_PASSWORD"
  echo "  4. Expand '$SIGNING_NAME', open the certificate, and set"
  echo "     Code Signing trust to Always Trust."
  echo "  5. Delete $FALLBACK_IDENTITY after importing it."
  exit 1
fi

if ! security add-trusted-cert -d -r trustRoot -p codeSign \
    -k "$LOGIN_KEYCHAIN" "$CERT_DIR/certificate.pem"; then
  echo ""
  echo "The identity was imported, but macOS did not apply trust automatically."
  echo "Open Keychain Access → login → My Certificates → '$SIGNING_NAME',"
  echo "open Trust, and set Code Signing to Always Trust."
  exit 1
fi

if security find-identity -v -p codesigning 2>/dev/null \
    | grep -Fq "\"$SIGNING_NAME\""; then
  echo "✓ Created trusted code-signing identity '$SIGNING_NAME'."
else
  echo "The certificate is present but is not yet a valid signing identity." >&2
  echo "In Keychain Access, set its Code Signing trust to Always Trust." >&2
  exit 1
fi
