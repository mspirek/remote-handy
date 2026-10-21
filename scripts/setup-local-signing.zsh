#!/usr/bin/env zsh
set -euo pipefail

identity_name="${REMOTE_HANDY_CODESIGN_IDENTITY:-Remote Handy Local Code Signing}"

existing_identity_hash() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -v name="$identity_name" 'index($0, "\"" name "\"") > 0 { print $2; exit }'
}

if [[ -n "$(existing_identity_hash)" ]]; then
  print "Code signing identity already exists: $identity_name"
  exit 0
fi

tmp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/remote-handy-signing.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

openssl_config="$tmp_dir/openssl.cnf"
private_key="$tmp_dir/key.pem"
certificate="$tmp_dir/cert.pem"
identity_p12="$tmp_dir/identity.p12"
p12_password="$(/usr/bin/uuidgen)"

cat >"$openssl_config" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = code_signing

[ dn ]
CN = $identity_name
O = Remote Handy Local

[ code_signing ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$private_key" \
  -out "$certificate" \
  -config "$openssl_config" >/dev/null 2>&1

/usr/bin/openssl pkcs12 -export \
  -out "$identity_p12" \
  -inkey "$private_key" \
  -in "$certificate" \
  -name "$identity_name" \
  -passout "pass:$p12_password" >/dev/null 2>&1

print "Importing local code signing identity into your default login keychain:"
print "  $identity_name"
print ""
print "macOS may ask for your login password or for permission to let codesign use the key."

/usr/bin/security import "$identity_p12" \
  -P "$p12_password" \
  -T /usr/bin/codesign >/dev/null

/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  "$certificate" >/dev/null

if [[ -z "$(existing_identity_hash)" ]]; then
  print -u2 "error: imported identity was not found as a valid code signing identity."
  print -u2 "Open Keychain Access and confirm the certificate appears under 'My Certificates'."
  exit 1
fi

print ""
print "Ready. Future 'make install-local' runs will sign Remote Handy with:"
print "  $identity_name"
