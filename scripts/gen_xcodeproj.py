#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 SubLens.xcodeproj/project.pbxproj 与共享 Scheme。

用法：python3 scripts/gen_xcodeproj.py
（如果本机装了 XcodeGen，也可以直接 xcodegen generate，project.yml 是等价的）
"""

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "SubLens"
APP_TARGET = "SubLens"
EXT_TARGET = "ScreenBroadcastExtension"

APP_SOURCES = [
    "SubLens/App/SubLensApp.swift",
    "SubLens/App/AppEnvironment.swift",
    "SubLens/Core/Models.swift",
    "SubLens/Core/LanguageDetector.swift",
    "SubLens/Core/SharedBus.swift",
    "SubLens/Core/BridgeTransport.swift",
    "SubLens/Translation/Translator.swift",
    "SubLens/Speech/SpeechService.swift",
    "SubLens/Speech/SpeechSynthesizer.swift",
    "SubLens/Screen/ScreenSubtitleService.swift",
    "SubLens/Screen/SilentAudioKeeper.swift",
    "SubLens/Screen/PiPSubtitleController.swift",
    "SubLens/Image/ImageOCRService.swift",
    "SubLens/UI/Components.swift",
    "SubLens/UI/RootView.swift",
    "SubLens/UI/LiveView.swift",
    "SubLens/UI/ScreenView.swift",
    "SubLens/UI/RegionPickerSheet.swift",
    "SubLens/UI/ImageTranslateView.swift",
    "SubLens/UI/SettingsView.swift",
    "SubLens/UI/LanguagePickerSheet.swift",
]

APP_RESOURCES = ["SubLens/Resources/Assets.xcassets"]

EXT_SOURCES = [
    "ScreenBroadcastExtension/SampleHandler.swift",
    "ScreenBroadcastExtension/ScreenOCRWorker.swift",
    "ScreenBroadcastExtension/AudioRelayWorker.swift",
    "SubLens/Core/SharedBus.swift",
    "SubLens/Core/BridgeTransport.swift",
]

APP_CONFIG_FILES = [
    "SubLens/Resources/Info.plist",
    "SubLens/Resources/SubLens.entitlements",
]

EXT_CONFIG_FILES = [
    "ScreenBroadcastExtension/Info.plist",
    "ScreenBroadcastExtension/ScreenBroadcastExtension.entitlements",
]

ALL_FILES = APP_SOURCES + APP_RESOURCES + APP_CONFIG_FILES + EXT_CONFIG_FILES + \
    [p for p in EXT_SOURCES if p not in APP_SOURCES]


def oid(key):
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


PROJECT_ID = oid("project")
APP_TARGET_ID = oid("target.app")
EXT_TARGET_ID = oid("target.ext")
APP_PRODUCT_ID = oid("product.app")
EXT_PRODUCT_ID = oid("product.ext")
MAIN_GROUP_ID = oid("group.main")
PRODUCTS_GROUP_ID = oid("group.products")
APP_GROUP_ID = oid("group.sublens")
EXT_GROUP_ID = oid("group.extension")
APP_CONFIG_LIST_ID = oid("configlist.app")
EXT_CONFIG_LIST_ID = oid("configlist.ext")
PROJECT_CONFIG_LIST_ID = oid("configlist.project")
APP_SOURCES_PHASE_ID = oid("phase.app.sources")
APP_RESOURCES_PHASE_ID = oid("phase.app.resources")
APP_FRAMEWORKS_PHASE_ID = oid("phase.app.frameworks")
APP_EMBED_PHASE_ID = oid("phase.app.embed")
EXT_SOURCES_PHASE_ID = oid("phase.ext.sources")
EXT_FRAMEWORKS_PHASE_ID = oid("phase.ext.frameworks")
EXT_RESOURCES_PHASE_ID = oid("phase.ext.resources")
TARGET_DEPENDENCY_ID = oid("dependency.ext")
CONTAINER_PROXY_ID = oid("proxy.ext")
EMBED_BUILD_FILE_ID = oid("buildfile.embed.ext")


def ref(path):
    return oid("fileref:" + path)


def bf(path, target):
    return oid("buildfile:" + target + ":" + path)


def base(path):
    return os.path.basename(path)


def declared_type(path):
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".entitlements"):
        return "text.plist.entitlements"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    return "text"


# ------------------------------------------------------------------ groups


def groups_section():
    lines = []

    def group(gid, name, path, children, is_main=False):
        child_lines = "".join("\t\t\t\t%s /* %s */,\n" % (cid, cname) for cid, cname in children)
        path_line = "" if path is None else "\t\t\tpath = %s;\n" % path
        name_line = "\t\t\tname = %s;\n" % name if is_main else ""
        lines.append(
            "\t\t%s /* %s */ = {\n"
            "\t\t\tisa = PBXGroup;\n"
            "\t\t\tchildren = (\n%s\t\t\t);\n%s\t\t\tsourceTree = \"<group>\";\n%s"
            "\t\t};\n" % (gid, name, child_lines, name_line, path_line)
        )

    # 收集 SubLens 下的两层目录
    folders = {}
    root_files = []
    for path in APP_SOURCES + APP_RESOURCES + APP_CONFIG_FILES:
        parts = path.split("/")
        if len(parts) == 2:
            root_files.append(path)
        else:
            folders.setdefault(parts[1], {"files": [], "subs": {}})
            if len(parts) == 3:
                folders[parts[1]]["files"].append(path)
            else:
                folders[parts[1]]["subs"].setdefault(parts[2], []).append(path)

    app_children = []
    for folder, info in sorted(folders.items()):
        sub_children = [(ref(p), base(p)) for p in sorted(info["files"])]
        for sub, sub_files in sorted(info["subs"].items()):
            sub_id = oid("group:SubLens/" + folder + "/" + sub)
            group(sub_id, sub, sub, [(ref(p), base(p)) for p in sorted(sub_files)])
            sub_children.append((sub_id, sub))
        folder_id = oid("group:SubLens/" + folder)
        group(folder_id, folder, folder, sub_children)
        app_children.append((folder_id, folder))

    for path in sorted(root_files):
        app_children.append((ref(path), base(path)))

    group(APP_GROUP_ID, "SubLens", "SubLens", app_children)

    # 注意：SharedBus.swift 物理位置在 SubLens/Core，不能挂到扩展目录下，
    # 否则 Xcode 会按扩展组的相对路径去找文件。它只通过 buildfile 被扩展 target 引用。
    ext_children = [(ref(p), base(p)) for p in sorted(EXT_CONFIG_FILES)]
    for p in EXT_SOURCES:
        if p not in APP_SOURCES:
            ext_children.append((ref(p), base(p)))
    group(EXT_GROUP_ID, EXT_TARGET, EXT_TARGET, ext_children)
    group(PRODUCTS_GROUP_ID,
          "Products",
          None,
          [(APP_PRODUCT_ID, "SubLens.app"), (EXT_PRODUCT_ID, EXT_TARGET + ".appex")],
          is_main=True)
    group(MAIN_GROUP_ID, "Main", None,
          [(APP_GROUP_ID, "SubLens"), (EXT_GROUP_ID, EXT_TARGET), (PRODUCTS_GROUP_ID, "Products")],
          is_main=True)

    return "".join(lines)


# ------------------------------------------------------------------ sections


def build_file_section():
    lines = []
    for path in APP_SOURCES:
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
                     % (bf(path, "app"), base(path), ref(path), base(path)))
    for path in APP_RESOURCES:
        lines.append("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
                     % (bf(path, "app"), base(path), ref(path), base(path)))
    lines.append(
        "\t\t%s /* %s.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = %s /* %s.appex */; "
        "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };\n"
        % (EMBED_BUILD_FILE_ID, EXT_TARGET, EXT_PRODUCT_ID, EXT_TARGET))
    for path in EXT_SOURCES:
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
                     % (bf(path, "ext"), base(path), ref(path), base(path)))
    return "".join(lines)


def file_reference_section():
    lines = []
    for path in ALL_FILES:
        lines.append("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; "
                     "sourceTree = \"<group>\"; };\n"
                     % (ref(path), base(path), declared_type(path), base(path)))
    lines.append("\t\t%s /* SubLens.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; "
                 "includeInIndex = 0; path = SubLens.app; sourceTree = BUILT_PRODUCTS_DIR; };\n" % APP_PRODUCT_ID)
    lines.append("\t\t%s /* %s.appex */ = {isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; "
                 "includeInIndex = 0; path = %s.appex; sourceTree = BUILT_PRODUCTS_DIR; };\n"
                 % (EXT_PRODUCT_ID, EXT_TARGET, EXT_TARGET))
    return "".join(lines)


def sources_phase(phase_id, target, paths):
    files = "".join("\t\t\t\t%s /* %s in Sources */,\n" % (bf(p, target), base(p)) for p in paths)
    return ("\t\t%s /* Sources */ = {\n"
            "\t\t\tisa = PBXSourcesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n%s\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t};\n" % (phase_id, files))


def empty_phase(phase_id, name, isa):
    return ("\t\t%s /* %s */ = {\n"
            "\t\t\tisa = %s;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t};\n" % (phase_id, name, isa))


def resources_phase(phase_id, target, paths):
    files = "".join("\t\t\t\t%s /* %s in Resources */,\n" % (bf(p, target), base(p)) for p in paths)
    return ("\t\t%s /* Resources */ = {\n"
            "\t\t\tisa = PBXResourcesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n%s\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t};\n" % (phase_id, files))


def embed_phase():
    return ("\t\t%s /* Embed App Extensions */ = {\n"
            "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tdstPath = \"\";\n"
            "\t\t\tdstSubfolderSpec = 13;\n"
            "\t\t\tfiles = (\n"
            "\t\t\t\t%s /* %s.appex in Embed App Extensions */,\n"
            "\t\t\t);\n"
            "\t\t\tname = \"Embed App Extensions\";\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t};\n" % (APP_EMBED_PHASE_ID, EMBED_BUILD_FILE_ID, EXT_TARGET))


def target_section():
    app = ("\t\t%s /* SubLens */ = {\n"
           "\t\t\tisa = PBXNativeTarget;\n"
           "\t\t\tbuildConfigurationList = %s;\n"
           "\t\t\tbuildPhases = (\n"
           "\t\t\t\t%s /* Sources */,\n"
           "\t\t\t\t%s /* Frameworks */,\n"
           "\t\t\t\t%s /* Resources */,\n"
           "\t\t\t\t%s /* Embed App Extensions */,\n"
           "\t\t\t);\n"
           "\t\t\tbuildRules = (\n\t\t\t);\n"
           "\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n\t\t\t);\n"
           "\t\t\tname = SubLens;\n"
           "\t\t\tproductName = SubLens;\n"
           "\t\t\tproductReference = %s /* SubLens.app */;\n"
           "\t\t\tproductType = \"com.apple.product-type.application\";\n"
           "\t\t};\n"
           % (APP_TARGET_ID, APP_CONFIG_LIST_ID,
              APP_SOURCES_PHASE_ID, APP_FRAMEWORKS_PHASE_ID, APP_RESOURCES_PHASE_ID, APP_EMBED_PHASE_ID,
              TARGET_DEPENDENCY_ID, APP_PRODUCT_ID))

    ext = ("\t\t%s /* %s */ = {\n"
           "\t\t\tisa = PBXNativeTarget;\n"
           "\t\t\tbuildConfigurationList = %s;\n"
           "\t\t\tbuildPhases = (\n"
           "\t\t\t\t%s /* Sources */,\n"
           "\t\t\t\t%s /* Frameworks */,\n"
           "\t\t\t\t%s /* Resources */,\n"
           "\t\t\t);\n"
           "\t\t\tbuildRules = (\n\t\t\t);\n"
           "\t\t\tdependencies = (\n\t\t\t);\n"
           "\t\t\tname = %s;\n"
           "\t\t\tproductName = %s;\n"
           "\t\t\tproductReference = %s /* %s.appex */;\n"
           "\t\t\tproductType = \"com.apple.product-type.app-extension\";\n"
           "\t\t};\n"
           % (EXT_TARGET_ID, EXT_TARGET, EXT_CONFIG_LIST_ID,
              EXT_SOURCES_PHASE_ID, EXT_FRAMEWORKS_PHASE_ID, EXT_RESOURCES_PHASE_ID,
              EXT_TARGET, EXT_TARGET, EXT_PRODUCT_ID, EXT_TARGET))
    return app + ext


def project_section():
    return ("\t\t%s /* Project object */ = {\n"
            "\t\t\tisa = PBXProject;\n"
            "\t\t\tattributes = {\n"
            "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
            "\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
            "\t\t\t\tLastUpgradeCheck = 1600;\n"
            "\t\t\t\tTargetAttributes = {\n"
            "\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t};\n"
            "\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t};\n"
            "\t\t\t\t};\n"
            "\t\t\t};\n"
            "\t\t\tbuildConfigurationList = %s;\n"
            "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
            "\t\t\tdevelopmentRegion = zh_CN;\n"
            "\t\t\thasScannedForEncodings = 0;\n"
            "\t\t\tknownRegions = (\n\t\t\t\tzh_CN,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
            "\t\t\tmainGroup = %s;\n"
            "\t\t\tproductRefGroup = %s;\n"
            "\t\t\tprojectDirPath = \"\";\n"
            "\t\t\tprojectRoot = \"\";\n"
            "\t\t\ttargets = (\n\t\t\t\t%s,\n\t\t\t\t%s,\n\t\t\t);\n"
            "\t\t};\n"
            % (PROJECT_ID, APP_TARGET_ID, EXT_TARGET_ID, PROJECT_CONFIG_LIST_ID,
               MAIN_GROUP_ID, PRODUCTS_GROUP_ID, APP_TARGET_ID, EXT_TARGET_ID))


def dependency_section():
    return ("\t\t%s /* PBXTargetDependency */ = {\n"
            "\t\t\tisa = PBXTargetDependency;\n"
            "\t\t\tcontainerPortal = %s;\n"
            "\t\t\tproxy = %s;\n"
            "\t\t\ttarget = %s;\n"
            "\t\t};\n"
            "\t\t%s /* PBXContainerItemProxy */ = {\n"
            "\t\t\tisa = PBXContainerItemProxy;\n"
            "\t\t\tcontainerPortal = %s;\n"
            "\t\t\tproxyType = 1;\n"
            "\t\t\tremoteGlobalIDString = %s;\n"
            "\t\t\tremoteInfo = %s;\n"
            "\t\t};\n"
            % (TARGET_DEPENDENCY_ID, PROJECT_ID, CONTAINER_PROXY_ID, EXT_TARGET_ID,
               CONTAINER_PROXY_ID, PROJECT_ID, EXT_TARGET_ID, EXT_TARGET))


PROJECT_DEBUG = [
    "ALWAYS_SEARCH_USER_PATHS = NO;",
    "CLANG_ANALYZER_NONNULL = YES;",
    "CLANG_ENABLE_MODULES = YES;",
    "CLANG_ENABLE_OBJC_ARC = YES;",
    "COPY_PHASE_STRIP = NO;",
    "DEBUG_INFORMATION_FORMAT = dwarf;",
    "ENABLE_TESTABILITY = YES;",
    "GCC_C_LANGUAGE_STANDARD = gnu17;",
    "GCC_DYNAMIC_NO_PIC = NO;",
    "GCC_OPTIMIZATION_LEVEL = 0;",
    "GCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\");",
    "IPHONEOS_DEPLOYMENT_TARGET = 18.0;",
    "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
    "ONLY_ACTIVE_ARCH = YES;",
    "SDKROOT = iphoneos;",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
    "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
    "SWIFT_STRICT_CONCURRENCY = minimal;",
    "SWIFT_VERSION = 5.0;",
]

PROJECT_RELEASE = [
    "ALWAYS_SEARCH_USER_PATHS = NO;",
    "CLANG_ENABLE_MODULES = YES;",
    "CLANG_ENABLE_OBJC_ARC = YES;",
    "COPY_PHASE_STRIP = NO;",
    "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
    "ENABLE_NS_ASSERTIONS = NO;",
    "GCC_C_LANGUAGE_STANDARD = gnu17;",
    "IPHONEOS_DEPLOYMENT_TARGET = 18.0;",
    "SDKROOT = iphoneos;",
    "SWIFT_COMPILATION_MODE = wholemodule;",
    "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
    "SWIFT_STRICT_CONCURRENCY = minimal;",
    "SWIFT_VERSION = 5.0;",
    "VALIDATE_PRODUCT = YES;",
]

APP_SETTINGS = [
    "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
    "CODE_SIGN_ENTITLEMENTS = SubLens/Resources/SubLens.entitlements;",
    "CODE_SIGN_STYLE = Automatic;",
    "CURRENT_PROJECT_VERSION = 1;",
    "DEVELOPMENT_TEAM = \"\";",
    "ENABLE_PREVIEWS = YES;",
    "GENERATE_INFOPLIST_FILE = NO;",
    "INFOPLIST_FILE = SubLens/Resources/Info.plist;",
    "IPHONEOS_DEPLOYMENT_TARGET = 18.0;",
    "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\");",
    "MARKETING_VERSION = 1.0;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.sublens.livetranslate;",
    "PRODUCT_NAME = \"$(TARGET_NAME)\";",
    "SWIFT_EMIT_LOC_STRINGS = YES;",
    "SWIFT_VERSION = 5.0;",
    "TARGETED_DEVICE_FAMILY = \"1,2\";",
]

EXT_SETTINGS = [
    "APPLICATION_EXTENSION_API_ONLY = YES;",
    "CODE_SIGN_ENTITLEMENTS = ScreenBroadcastExtension/ScreenBroadcastExtension.entitlements;",
    "CODE_SIGN_STYLE = Automatic;",
    "CURRENT_PROJECT_VERSION = 1;",
    "DEVELOPMENT_TEAM = \"\";",
    "GENERATE_INFOPLIST_FILE = NO;",
    "INFOPLIST_FILE = ScreenBroadcastExtension/Info.plist;",
    "IPHONEOS_DEPLOYMENT_TARGET = 18.0;",
    "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\", \"@executable_path/../../Frameworks\");",
    "MARKETING_VERSION = 1.0;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.sublens.livetranslate.ScreenBroadcast;",
    "PRODUCT_NAME = \"$(TARGET_NAME)\";",
    "SKIP_INSTALL = YES;",
    "SWIFT_VERSION = 5.0;",
    "TARGETED_DEVICE_FAMILY = \"1,2\";",
]


def config_block(key, name, settings):
    body = "".join("\t\t\t\t%s\n" % line for line in settings)
    return ("\t\t%s /* %s */ = {\n"
            "\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbuildSettings = {\n%s\t\t\t};\n"
            "\t\t\tname = %s;\n"
            "\t\t};\n" % (oid(key), name, body, name))


def config_list(key, label, debug_id, release_id):
    return ("\t\t%s /* %s */ = {\n"
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n"
            "\t\t\tdefaultConfigurationIsVisible = 0;\n"
            "\t\t\tdefaultConfigurationName = Release;\n"
            "\t\t};\n" % (oid(key), label, debug_id, release_id))


def configuration_section():
    out = []
    for name, settings in (("Debug", PROJECT_DEBUG), ("Release", PROJECT_RELEASE)):
        out.append(config_block("config.project." + name, name, settings))
        out.append(config_block("config.app." + name, name, APP_SETTINGS))
        out.append(config_block("config.ext." + name, name, EXT_SETTINGS))
    return "".join(out)


def configuration_list_section():
    return (
        config_list("configlist.project", 'Build configuration list for PBXProject "SubLens"',
                    oid("config.project.Debug"), oid("config.project.Release"))
        + config_list("configlist.app", 'Build configuration list for PBXNativeTarget "SubLens"',
                      oid("config.app.Debug"), oid("config.app.Release"))
        + config_list("configlist.ext", 'Build configuration list for PBXNativeTarget "%s"' % EXT_TARGET,
                      oid("config.ext.Debug"), oid("config.ext.Release"))
    )


def scheme_xml():
    template = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "SubLens.app" BlueprintName = "SubLens" ReferencedContainer = "container:SubLens.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "SubLens.app" BlueprintName = "SubLens" ReferencedContainer = "container:SubLens.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "SubLens.app" BlueprintName = "SubLens" ReferencedContainer = "container:SubLens.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
"""
    return template % (APP_TARGET_ID, APP_TARGET_ID, APP_TARGET_ID)


def main():
    def section(title, body):
        return "/* Begin %s section */\n%s/* End %s section */\n\n" % (title, body, title)
        # 注意：以下为不可达代码，保留占位以防误改

    content = "// !$*UTF8*$!\n{\n"
    content += "\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n\n"
    content += section("PBXBuildFile", build_file_section())
    content += section("PBXContainerItemProxy", 
                       "\t\t%s /* PBXContainerItemProxy */ = {\n"
                       "\t\t\tisa = PBXContainerItemProxy;\n"
                       "\t\t\tcontainerPortal = %s;\n"
                       "\t\t\tproxyType = 1;\n"
                       "\t\t\tremoteGlobalIDString = %s;\n"
                       "\t\t\tremoteInfo = %s;\n"
                       "\t\t};\n"
                       % (CONTAINER_PROXY_ID, PROJECT_ID, EXT_TARGET_ID, EXT_TARGET))
    content += section("PBXCopyFilesBuildPhase", embed_phase())
    content += section("PBXFileReference", file_reference_section())
    content += section("PBXFrameworksBuildPhase",
                       empty_phase(APP_FRAMEWORKS_PHASE_ID, "Frameworks", "PBXFrameworksBuildPhase")
                       + empty_phase(EXT_FRAMEWORKS_PHASE_ID, "Frameworks", "PBXFrameworksBuildPhase"))
    content += section("PBXGroup", groups_section())
    content += section("PBXNativeTarget", target_section())
    content += section("PBXProject", project_section())
    content += section("PBXResourcesBuildPhase",
                       resources_phase(APP_RESOURCES_PHASE_ID, "app", APP_RESOURCES)
                       + empty_phase(EXT_RESOURCES_PHASE_ID, "Resources", "PBXResourcesBuildPhase"))
    content += section("PBXSourcesBuildPhase",
                       sources_phase(APP_SOURCES_PHASE_ID, "app", APP_SOURCES)
                       + sources_phase(EXT_SOURCES_PHASE_ID, "ext", EXT_SOURCES))
    content += section("PBXTargetDependency", dependency_section().split("\t\t%s /* PBXContainerItemProxy" % CONTAINER_PROXY_ID)[0])
    content += section("XCBuildConfiguration", configuration_section())
    content += section("XCConfigurationList", configuration_list_section())
    content += "\t};\n\trootObject = %s /* Project object */;\n}\n" % PROJECT_ID

    project_path = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj", "project.pbxproj")
    os.makedirs(os.path.dirname(project_path), exist_ok=True)
    with open(project_path, "w", encoding="utf-8") as handle:
        handle.write(content)

    scheme_path = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj", "xcshareddata", "xcschemes", PROJECT_NAME + ".xcscheme")
    os.makedirs(os.path.dirname(scheme_path), exist_ok=True)
    with open(scheme_path, "w", encoding="utf-8") as handle:
        handle.write(scheme_xml())

    print("project written:", project_path)
    print("scheme written :", scheme_path)


if __name__ == "__main__":
    main()
