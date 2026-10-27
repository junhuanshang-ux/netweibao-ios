#!/usr/bin/env python3
"""Static sanity checks for the generated Xcode project and resources."""

from __future__ import annotations

from pathlib import Path
import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "NetWeiBao.xcodeproj" / "project.pbxproj"
SOURCE_ROOT = ROOT / "NetWeiBao"
SCHEME = ROOT / "NetWeiBao.xcodeproj" / "xcshareddata" / "xcschemes" / "NetWeiBao.xcscheme"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def main() -> None:
    text = PROJECT.read_text(encoding="utf-8")
    cleaned = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    cleaned = re.sub(r"//[^\n]*", "", cleaned)

    lines = cleaned.splitlines()
    definitions = []
    for index, line in enumerate(lines):
        match = re.match(r"^\s*([0-9A-F]{24})\s*=\s*\{", line)
        if not match:
            continue
        following = line + "\n" + "\n".join(lines[index + 1 : index + 3])
        if "isa =" in following:
            definitions.append(match.group(1))

    if len(definitions) != len(set(definitions)):
        fail("duplicate object identifiers")

    references = set(re.findall(r"\b[0-9A-F]{24}\b", cleaned))
    missing = sorted(references - set(definitions))
    if missing:
        fail(f"undefined object references: {missing}")

    for section in [
        "PBXBuildFile",
        "PBXFileReference",
        "PBXFrameworksBuildPhase",
        "PBXGroup",
        "PBXNativeTarget",
        "PBXProject",
        "PBXResourcesBuildPhase",
        "PBXSourcesBuildPhase",
        "XCBuildConfiguration",
        "XCConfigurationList",
    ]:
        if f"Begin {section} section" not in text:
            fail(f"missing section {section}")

    if "rootObject = " not in text:
        fail("missing rootObject")

    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))
    source_section = text.split("/* Begin PBXSourcesBuildPhase section */", 1)[1].split(
        "/* End PBXSourcesBuildPhase section */", 1
    )[0]
    for path in swift_files:
        if f"{path.name} in Sources" not in source_section:
            fail(f"Swift file is not in Sources: {path.relative_to(ROOT)}")

    build_file_count = text.count("isa = PBXBuildFile")
    if build_file_count != len(swift_files) + 1:
        fail(f"expected {len(swift_files) + 1} build files, found {build_file_count}")

    info_path = SOURCE_ROOT / "App" / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    for key in [
        "CFBundleDisplayName",
        "CFBundleExecutable",
        "CFBundleIdentifier",
        "CFBundleShortVersionString",
        "NSLocalNetworkUsageDescription",
    ]:
        if key not in info:
            fail(f"Info.plist missing {key}")
    if info["CFBundleIdentifier"] != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail("unexpected CFBundleIdentifier")
    if "arm64" in info.get("UIRequiredDeviceCapabilities", []):
        fail("unnecessary arm64 requirement remains")

    for json_path in SOURCE_ROOT.rglob("*.json"):
        try:
            json.loads(json_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"invalid JSON {json_path}: {error}")

    icon_path = SOURCE_ROOT / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
    icon = icon_path.read_bytes()
    if icon[:8] != b"\x89PNG\r\n\x1a\n":
        fail("app icon is not a PNG")
    width, height = struct.unpack(">II", icon[16:24])
    if (width, height) != (1024, 1024):
        fail(f"app icon is {width}x{height}, expected 1024x1024")

    ET.parse(SCHEME)

    print(f"OK: {len(swift_files)} Swift files, {len(definitions)} project objects")
    print(f"OK: {info['CFBundleDisplayName']} {info['CFBundleShortVersionString']}")
    print(f"OK: app icon {width}x{height}")


if __name__ == "__main__":
    main()
