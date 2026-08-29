#!/usr/bin/env bash
#
# Creates a persistent self-signed code-signing certificate named "mac-tools-signing"
# in your login keychain. Signing MacTools with this identity gives it a STABLE code
# signature, so macOS remembers the Accessibility grant across rebuilds.
#
# Run once:  ./setup-signing.sh
#
set -euo pipefail

CERT_NAME="mac-tools-signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> Certificate '$CERT_NAME' already exists. Nothing to do."
    exit 0
fi

echo "==> Generating self-signed code-signing certificate '$CERT_NAME'..."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# OpenSSL config with the extensions codesign requires (codeSigning EKU).
cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no

[ dn ]
CN = mac-tools-signing

[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# Generate key + self-signed cert (10 years).
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cert.cnf" >/dev/null 2>&1

# Bundle into a PKCS#12 for import. Use -legacy so macOS's `security` tool can read it.
openssl pkcs12 -export -legacy -out "$TMP/cert.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:temppass >/dev/null 2>&1

# Import into the login keychain; allow codesign to use the key without prompting.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "temppass" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1

# Trust the cert for code signing in the login keychain (no sudo needed).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" >/dev/null 2>&1

# Note: on the first build after creating this cert, macOS will prompt for your
# keychain password when codesign uses the private key. Click "Always Allow" in
# that dialog (not just "Allow") to update the key's partition list ACL, so future
# builds sign without prompting. This is done via the GUI to avoid ever passing your
# login keychain password on a command line.

echo "==> Done. Verifying identity is available for codesigning:"
security find-identity -v -p codesigning | grep "$CERT_NAME" || {
    echo "!! Certificate created but not showing as a codesigning identity."
    echo "   You may need to open Keychain Access and set the cert to 'Always Trust' for Code Signing."
    exit 1
}

echo ""
echo "Success. Now run ./install.sh — it will sign with '$CERT_NAME'."
echo "Grant Accessibility to MacTools ONE more time; it will stick from now on."
