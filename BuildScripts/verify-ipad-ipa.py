#!/usr/bin/env python3
"""Check that the StreamDesk device archive and embedded code target iOS 12."""

import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

IOS12 = (12, 0, 0)
MACHO_MAGICS = {
    bytes.fromhex(magic)
    for magic in ("cffaedfe", "feedfacf", "cefaedfe", "feedface", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")
}
# otool -h without -v prints the numeric CPU type and subtype from the selected slice.
ARM64_BASELINE_HEADER = re.compile(r"^\s*0xfeedfacf\s+16777228\s+0\s+0x00\s", re.MULTILINE)
VERSION = re.compile(
    r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (?:2|IOS|iOS)\s+(?:sdk [\d.]+\s+)?minos ([\d.]+)"
    r"|cmd LC_VERSION_MIN_IPHONEOS\s+cmdsize \d+\s+version ([\d.]+)"
)


def verify(archive_path):
    otool = ["xcrun", "otool"] if shutil.which("xcrun") else ["llvm-otool"]
    with zipfile.ZipFile(archive_path) as archive, tempfile.TemporaryDirectory() as directory:
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError(f"{corrupt}: ZIP checksum mismatch")
        names = archive.namelist()
        infos = [name for name in names if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
        if len(infos) != 1:
            raise ValueError("Expected one application under Payload")
        info = plistlib.loads(archive.read(infos[0]))
        if info.get("MinimumOSVersion") != "12.0" or info.get("CFBundleIdentifier") != "org.streamdesk.client":
            raise ValueError("Unexpected application identity or deployment target")
        if 2 not in info.get("UIDeviceFamily", []):
            raise ValueError("The archive does not declare iPad support")

        root = infos[0].removesuffix("Info.plist")
        main = root + info["CFBundleExecutable"]
        if not any(name.startswith(root + "iPad.storyboardc/") for name in names):
            raise ValueError("The compiled iPad storyboard is missing")
        binaries = [main]
        for entry in archive.infolist():
            if entry.filename.startswith(root + "Frameworks/") and not entry.is_dir():
                with archive.open(entry) as member:
                    if member.read(4) in MACHO_MAGICS:
                        binaries.append(entry.filename)

        for name in binaries:
            binary = pathlib.Path(directory) / "macho"
            binary.write_bytes(archive.read(name))
            commands = subprocess.check_output([*otool, "-arch", "arm64", "-h", "-l", str(binary)], text=True)
            if not ARM64_BASELINE_HEADER.search(commands):
                raise ValueError(f"{name}: missing baseline ARM64/ALL slice for iPad Air 1")
            match = VERSION.search(commands)
            if not match:
                raise ValueError(f"{name}: missing arm64 iOS deployment command")
            components = (match[1] or match[2]).split(".")
            version = tuple(int(component) for component in (components + ["0", "0"])[:3])
            if (name == main and version != IOS12) or version > IOS12:
                raise ValueError(f"{name}: incompatible iOS minimum {'.'.join(components)}")
            if "LC_DYLD_CHAINED_FIXUPS" in commands:
                raise ValueError(f"{name}: chained fixups require a newer iOS loader")
        print(f"Verified {len(binaries)} baseline ARM64/ALL Mach-O files for iOS 12")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} STREAMDESK.ipa")
    try:
        verify(sys.argv[1])
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
