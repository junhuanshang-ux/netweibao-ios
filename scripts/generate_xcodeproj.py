#!/usr/bin/env python3
"""Generate NetWeiBao.xcodeproj without requiring Xcode or third-party tools.

The project uses classic PBX groups and explicit build files so it opens in
Xcode 15 and 16. Run this script again after adding or removing Swift files.
"""

from __future__ import annotations

from pathlib import Path
import hashlib
import shutil

ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "NetWeiBao.xcodeproj"
SOURCE_ROOT = ROOT / "NetWeiBao"
TARGET_NAME = "NetWeiBao"
BUNDLE_ID = "com.netweibao.app"


def uid(key: str) -> str:
    return hashlib.sha1(key.encode("utf-8")).hexdigest().upper()[:24]


def quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


PROJECT = uid("project")
MAIN_GROUP = uid("group:main")
PRODUCTS_GROUP = uid("group:products")
PRODUCT_REF = uid("product")
TARGET = uid("target")
SOURCES_PHASE = uid("phase:sources")
FRAMEWORKS_PHASE = uid("phase:frameworks")
RESOURCES_PHASE = uid("phase:resources")
PROJECT_CONFIG_LIST = uid("configlist:project")
TARGET_CONFIG_LIST = uid("configlist:target")
PROJECT_DEBUG = uid("config:project:debug")
PROJECT_RELEASE = uid("config:project:release")
TARGET_DEBUG = uid("config:target:debug")
TARGET_RELEASE = uid("config:target:release")


def relative_files() -> list[Path]:
    files = []
    for path in sorted(SOURCE_ROOT.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix == ".swift" or path.name == "Info.plist":
            files.append(path.relative_to(SOURCE_ROOT))
    return files


def directory_children(relative_dir: Path | None, all_files: list[Path]) -> tuple[list[str], list[str]]:
    """Return (subdirectory names, filenames) directly inside relative_dir."""
    directories: set[str] = set()
    filenames: list[str] = []

    for relative in all_files:
        parent = relative.parent
        if relative_dir is None:
            # Root files only; assets are special-cased below.
            if parent == Path("."):
                filenames.append(relative.name)
            else:
                directories.add(relative.parts[0])
            continue

        if parent == relative_dir:
            filenames.append(relative.name)
            continue

        try:
            remainder = parent.relative_to(relative_dir)
        except ValueError:
            continue
        if remainder.parts:
            directories.add(remainder.parts[0])

    return sorted(directories), sorted(filenames)


def group_id(relative_dir: Path) -> str:
    return uid(f"group:{relative_dir.as_posix()}")


def file_id(relative: Path) -> str:
    return uid(f"file:{relative.as_posix()}")


def build_id(relative: Path) -> str:
    return uid(f"build:{relative.as_posix()}")


def file_type(path: Path) -> str:
    return {
        ".swift": "sourcecode.swift",
        ".plist": "text.plist.xml",
        ".xcassets": "folder.assetcatalog",
    }.get(path.suffix, "text")


def main() -> None:
    if PROJECT_DIR.exists():
        shutil.rmtree(PROJECT_DIR)

    files = relative_files()
    swift_files = [path for path in files if path.suffix == ".swift"]
    info_plist = Path("App/Info.plist")
    assets = Path("Assets.xcassets")

    if info_plist not in files:
        raise SystemExit("missing NetWeiBao/App/Info.plist")
    if not (SOURCE_ROOT / assets).is_dir():
        raise SystemExit("missing NetWeiBao/Assets.xcassets")

    all_groups = [Path(".")]
    for path in files:
        for parent in path.parents:
            if parent != Path("."):
                all_groups.append(parent)
    all_groups = sorted(set(all_groups), key=lambda item: (len(item.parts), item.as_posix()))

    # The root group gets a display name of NetWeiBao and holds the asset catalog.
    def children_for(relative_dir: Path) -> list[str]:
        dirs, filenames = directory_children(None if relative_dir == Path(".") else relative_dir, files)
        result = [
            group_id(Path(name) if relative_dir == Path(".") else relative_dir / name)
            for name in dirs
        ]
        result.extend(file_id(Path(name) if relative_dir == Path(".") else relative_dir / name) for name in filenames)
        if relative_dir == Path("."):
            result.append(uid("file:Assets.xcassets"))
        return result

    lines: list[str] = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")

    # PBXBuildFile
    lines.append("")
    lines.append("/* Begin PBXBuildFile section */")
    for relative in swift_files:
        lines.append(
            f"\t\t{build_id(relative)} /* {relative.name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_id(relative)} /* {relative.name} */; }};"
        )
    lines.append(
        f"\t\t{build_id(assets)} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; "
        f"fileRef = {uid('file:Assets.xcassets')} /* Assets.xcassets */; }};"
    )
    lines.append("/* End PBXBuildFile section */")

    # PBXFileReference
    lines.append("")
    lines.append("/* Begin PBXFileReference section */")
    for relative in files:
        lines.append(
            f"\t\t{file_id(relative)} /* {relative.name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(relative)}; path = {relative.name}; sourceTree = \"<group>\"; }};"
        )
    lines.append(
        f"\t\t{uid('file:Assets.xcassets')} /* Assets.xcassets */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};"
    )
    lines.append(
        f"\t\t{PRODUCT_REF} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; path = {TARGET_NAME}.app; "
        f"sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    lines.append("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    lines.append("")
    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    lines.append(
        f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{\n"
        f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    lines.append("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    lines.append("")
    lines.append("/* Begin PBXGroup section */")
    lines.append(
        f"\t\t{MAIN_GROUP} = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{group_id(Path('.'))} /* NetWeiBao */,\n"
        f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,\n"
        f"\t\t\t);\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    lines.append(
        f"\t\t{PRODUCTS_GROUP} /* Products */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{PRODUCT_REF} /* {TARGET_NAME}.app */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = Products;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )

    for relative_dir in all_groups:
        children = children_for(relative_dir)
        if relative_dir == Path("."):
            name = TARGET_NAME
            path_line = f"\t\t\tpath = {TARGET_NAME};\n"
        else:
            name = relative_dir.name
            path_line = f"\t\t\tpath = {relative_dir.name};\n"

        child_lines = "".join(f"\t\t\t\t{child},\n" for child in children)
        lines.append(
            f"\t\t{group_id(relative_dir)} /* {name} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n"
            f"{child_lines}"
            f"\t\t\t);\n"
            f"{path_line}"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};"
        )
    lines.append("/* End PBXGroup section */")

    # PBXNativeTarget
    lines.append("")
    lines.append("/* Begin PBXNativeTarget section */")
    lines.append(
        f"\t\t{TARGET} /* {TARGET_NAME} */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"{TARGET_NAME}\" */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{SOURCES_PHASE} /* Sources */,\n"
        f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,\n"
        f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n"
        f"\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t);\n"
        f"\t\t\tname = {TARGET_NAME};\n"
        f"\t\t\tproductName = {TARGET_NAME};\n"
        f"\t\t\tproductReference = {PRODUCT_REF} /* {TARGET_NAME}.app */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.application\";\n"
        f"\t\t}};"
    )
    lines.append("/* End PBXNativeTarget section */")

    # PBXProject
    lines.append("")
    lines.append("/* Begin PBXProject section */")
    lines.append(
        f"\t\t{PROJECT} /* Project object */ = {{\n"
        f"\t\t\tisa = PBXProject;\n"
        f"\t\t\tattributes = {{\n"
        f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        f"\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
        f"\t\t\t\tLastUpgradeCheck = 1600;\n"
        f"\t\t\t\tTargetAttributes = {{\n"
        f"\t\t\t\t\t{TARGET} = {{\n"
        f"\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n"
        f"\t\t\t\t\t}};\n"
        f"\t\t\t\t}};\n"
        f"\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"{TARGET_NAME}\" */;\n"
        f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
        f"\t\t\tdevelopmentRegion = en;\n"
        f"\t\t\thasScannedForEncodings = 0;\n"
        f"\t\t\tknownRegions = (\n"
        f"\t\t\t\ten,\n"
        f"\t\t\t\tBase,\n"
        f"\t\t\t\t\"zh-Hans\",\n"
        f"\t\t\t);\n"
        f"\t\t\tmainGroup = {MAIN_GROUP};\n"
        f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;\n"
        f"\t\t\tprojectDirPath = \"\";\n"
        f"\t\t\tprojectRoot = \"\";\n"
        f"\t\t\ttargets = (\n"
        f"\t\t\t\t{TARGET} /* {TARGET_NAME} */,\n"
        f"\t\t\t);\n"
        f"\t\t}};"
    )
    lines.append("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    lines.append("")
    lines.append("/* Begin PBXResourcesBuildPhase section */")
    lines.append(
        f"\t\t{RESOURCES_PHASE} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{build_id(assets)} /* Assets.xcassets in Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    lines.append("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    lines.append("")
    lines.append("/* Begin PBXSourcesBuildPhase section */")
    source_lines = "".join(
        f"\t\t\t\t{build_id(relative)} /* {relative.name} in Sources */,\n"
        for relative in swift_files
    )
    lines.append(
        f"\t\t{SOURCES_PHASE} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"{source_lines}"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    lines.append("/* End PBXSourcesBuildPhase section */")

    # XCBuildConfiguration
    lines.append("")
    lines.append("/* Begin XCBuildConfiguration section */")

    def project_config(config_id: str, name: str, debug: bool) -> str:
        settings = [
            ("ALWAYS_SEARCH_USER_PATHS", "NO"),
            ("CLANG_ANALYZER_NONNULL", "YES"),
            ("CLANG_ENABLE_MODULES", "YES"),
            ("CLANG_ENABLE_OBJC_ARC", "YES"),
            ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
            ("CLANG_WARN_BOOL_CONVERSION", "YES"),
            ("CLANG_WARN_COMMA", "YES"),
            ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
            ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
            ("CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "YES_ERROR"),
            ("CLANG_WARN_EMPTY_BODY", "YES"),
            ("CLANG_WARN_ENUM_CONVERSION", "YES"),
            ("CLANG_WARN_INFINITE_RECURSION", "YES"),
            ("CLANG_WARN_INT_CONVERSION", "YES"),
            ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
            ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
            ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
            ("CLANG_WARN_OBJC_ROOT_CLASS", "YES_ERROR"),
            ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
            ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
            ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
            ("CLANG_WARN_UNGUARDED_AVAILABILITY", "YES_AGGRESSIVE"),
            ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
            ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
            ("COPY_PHASE_STRIP", "NO"),
            ("DEBUG_INFORMATION_FORMAT", "dwarf" if debug else "dwarf-with-dsym"),
            ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
            ("ENABLE_TESTABILITY", "YES" if debug else "NO"),
            ("ENABLE_USER_SCRIPT_SANDBOXING", "YES"),
            ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
            ("GCC_NO_COMMON_BLOCKS", "YES"),
            ("GCC_OPTIMIZATION_LEVEL", "0" if debug else "s"),
            ("GCC_PREPROCESSOR_DEFINITIONS", '("DEBUG=1", "$(inherited)")' if debug else '("$(inherited)")'),
            ("GCC_WARN_64_TO_32_BIT_CONVERSION", "YES"),
            ("GCC_WARN_ABOUT_RETURN_TYPE", "YES_ERROR"),
            ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
            ("GCC_WARN_UNINITIALIZED_AUTOS", "YES_AGGRESSIVE"),
            ("GCC_WARN_UNUSED_FUNCTION", "YES"),
            ("GCC_WARN_UNUSED_VARIABLE", "YES"),
            ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
            ("MTL_FAST_MATH", "YES"),
            ("ONLY_ACTIVE_ARCH", "YES" if debug else "NO"),
            ("SDKROOT", "iphoneos"),
            ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG" if debug else ""),
            ("SWIFT_COMPILATION_MODE", "singlefile" if debug else "wholemodule"),
            ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"' if debug else '"-O"'),
            ("VALIDATE_PRODUCT", "NO" if debug else "YES"),
        ]
        rendered = []
        for key, value in settings:
            if value == "":
                continue
            rendered.append(f"\t\t\t\t{key} = {value};")
        body = "\n".join(rendered)
        return (
            f"\t\t{config_id} /* {name} */ = {{\n"
            f"\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n"
            f"{body}\n"
            f"\t\t\t}};\n"
            f"\t\t\tname = {name};\n"
            f"\t\t}};"
        )

    def target_config(config_id: str, name: str) -> str:
        settings = [
            ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
            ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
            ("CODE_SIGN_STYLE", "Automatic"),
            ("CURRENT_PROJECT_VERSION", "1"),
            ("ENABLE_PREVIEWS", "YES"),
            ("GENERATE_INFOPLIST_FILE", "NO"),
            ("INFOPLIST_FILE", "NetWeiBao/App/Info.plist"),
            ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
            ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks")'),
            ("MARKETING_VERSION", "0.1"),
            ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
            ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
            ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
            ("SUPPORTS_MACCATALYST", "NO"),
            ("SWIFT_EMIT_LOC_STRINGS", "YES"),
            ("SWIFT_STRICT_CONCURRENCY", "minimal"),
            ("SWIFT_VERSION", "5.0"),
            ("TARGETED_DEVICE_FAMILY", "1"),
        ]
        rendered = "".join(f"\t\t\t\t{key} = {value};\n" for key, value in settings)
        return (
            f"\t\t{config_id} /* {name} */ = {{\n"
            f"\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n"
            f"{rendered}"
            f"\t\t\t}};\n"
            f"\t\t\tname = {name};\n"
            f"\t\t}};"
        )

    lines.append(project_config(PROJECT_DEBUG, "Debug", True))
    lines.append(project_config(PROJECT_RELEASE, "Release", False))
    lines.append(target_config(TARGET_DEBUG, "Debug"))
    lines.append(target_config(TARGET_RELEASE, "Release"))
    lines.append("/* End XCBuildConfiguration section */")

    # XCConfigurationList
    lines.append("")
    lines.append("/* Begin XCConfigurationList section */")
    lines.append(
        f"\t\t{PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"{TARGET_NAME}\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{PROJECT_DEBUG} /* Debug */,\n"
        f"\t\t\t\t{PROJECT_RELEASE} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};"
    )
    lines.append(
        f"\t\t{TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"{TARGET_NAME}\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{TARGET_DEBUG} /* Debug */,\n"
        f"\t\t\t\t{TARGET_RELEASE} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};"
    )
    lines.append("/* End XCConfigurationList section */")

    lines.append("\t};")
    lines.append(f"\trootObject = {PROJECT} /* Project object */;")
    lines.append("}")
    lines.append("")

    PROJECT_DIR.mkdir(parents=True)
    (PROJECT_DIR / "project.pbxproj").write_text(
        "\n".join(lines), encoding="utf-8", newline="\n"
    )

    scheme_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True)
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET}"
               BuildableName = "{TARGET_NAME}.app"
               BlueprintName = "{TARGET_NAME}"
               ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
    (scheme_dir / f"{TARGET_NAME}.xcscheme").write_text(
        scheme, encoding="utf-8", newline="\n"
    )

    print(f"Generated {PROJECT_DIR}")
    print(f"  {len(swift_files)} Swift files")
    print(f"  {len(all_groups)} groups")


if __name__ == "__main__":
    main()
