#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# != 4 ]]; then
    printf 'Usage: %s UNSIGNED.ipa PROFILE.mobileprovision IDENTITY.p12 SIGNED.ipa\n' "$0" >&2
    exit 2
fi

for tool in openssl zsign python3; do
    command -v "$tool" >/dev/null || { printf 'Missing %s\n' "$tool" >&2; exit 1; }
done

ipa=$(realpath -e "$1")
profile=$(realpath -e "$2")
identity=$(realpath -e "$3")
output=$(realpath -m "$4")
[[ -d "$(dirname "$output")" && ! -e "$output" ]] || {
    printf '%s\n' 'Choose a new output file in an existing directory' >&2
    exit 2
}
scratch=$(mktemp -d)
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$scratch"' EXIT

openssl cms -verify -inform DER -noverify -in "$profile" -out "$scratch/profile.plist"
# Let OpenSSL prompt for the import password. The decrypted material stays in the private scratch directory.
openssl pkcs12 -in "$identity" -noenc -out "$scratch/identity.pem"
openssl pkcs12 -export -in "$scratch/identity.pem" -passout pass: -out "$scratch/signing.p12"
openssl pkcs12 -in "$scratch/signing.p12" -clcerts -nokeys -passin pass: |
    openssl x509 -outform DER -out "$scratch/certificate.der"

python3 - "$ipa" "$scratch/profile.plist" "$scratch/certificate.der" <<'PY'
import datetime
import pathlib
import plistlib
import sys
import zipfile

ipa, profile_file, certificate = map(pathlib.Path, sys.argv[1:])
profile = plistlib.loads(profile_file.read_bytes())
with zipfile.ZipFile(ipa) as app:
    infos = [name for name in app.namelist()
             if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
    if len(infos) != 1:
        sys.exit("The IPA needs one application in Payload")
    bundle_id = plistlib.loads(app.read(infos[0])).get("CFBundleIdentifier")

if bundle_id != "org.streamdesk.client":
    sys.exit("Expected the StreamDesk bundle org.streamdesk.client")
expires = profile.get("ExpirationDate")
if not isinstance(expires, datetime.datetime) or expires.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
    sys.exit("The provisioning profile has expired")
if certificate.read_bytes() not in profile.get("DeveloperCertificates", []):
    sys.exit("The certificate is missing from the provisioning profile")
if not profile.get("ProvisionedDevices"):
    sys.exit("Use a device provisioning profile that includes the iPad")
app_id = profile.get("Entitlements", {}).get("application-identifier", "")
suffix = app_id.partition(".")[2]
if suffix != bundle_id:
    sys.exit("The signing tool requires an explicit profile for org.streamdesk.client")
PY

zsign -f -k "$scratch/signing.p12" -m "$profile" \
    -o "$scratch/signed.ipa" "$ipa"
python3 - "$scratch/signed.ipa" "$profile" "$output" <<'PY'
import os
import pathlib
import shutil
import sys
import tempfile
import zipfile

signed, profile, output = map(pathlib.Path, sys.argv[1:])
with zipfile.ZipFile(signed) as app:
    embedded = [name for name in app.namelist() if name.endswith(".app/embedded.mobileprovision")]
    signatures = [name for name in app.namelist() if name.endswith(".app/_CodeSignature/CodeResources")]
    if len(embedded) != 1 or len(signatures) != 1 or app.read(embedded[0]) != profile.read_bytes() or app.testzip():
        sys.exit("The signing tool did not produce a valid IPA package with the expected profile")
fd, staged = tempfile.mkstemp(dir=output.parent, prefix=".streamdesk-")
try:
    with os.fdopen(fd, "wb") as destination, signed.open("rb") as source:
        shutil.copyfileobj(source, destination)
    os.link(staged, output)
finally:
    os.unlink(staged)
print("Signed IPA written to", output)
PY
