#!/usr/bin/env python3
"""App Store preflight for the iOS app: checks that need no Mac.

Run from the repository root (CI runs it before every iOS build):
    python3 mobile_app/tool/ios_preflight.py [--bundle-id ID] [--strict]

It checks what App Review and App Store Connect reject a build for:
- Info.plist: a purpose string for every permission a plugin can ask for,
  the export-compliance key, portrait only on an iPhone-only app;
- the privacy manifest exists, has no tracking, and is in the Runner target;
- Release and Profile sign with the production push environment;
- iPhone only (TARGETED_DEVICE_FAMILY = 1), deployment target;
- the bundle id the app is built with matches the Firebase iOS app
  (FIREBASE_IOS_BUNDLE_ID in firebase.defines.json); otherwise iOS push is
  never delivered (APNs DeviceTokenNotForTopic);
- the version in pubspec.yaml.

Problems that must be fixed before an App Store build are errors; with
--strict (the signed build) they fail the run.
"""
import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", help="the bundle id the build overrides with (repo variable IOS_BUNDLE_ID)")
    ap.add_argument("--strict", action="store_true", help="fail on errors (signed App Store builds)")
    args = ap.parse_args()

    info = plistlib.loads((IOS / "Runner/Info.plist").read_bytes())
    pbx = (IOS / "Runner.xcodeproj/project.pbxproj").read_text()
    pubspec = (ROOT / "pubspec.yaml").read_text()

    # Purpose strings: each plugin that can ask for a permission needs its key.
    needs = {
        "mobile_scanner": ["NSCameraUsageDescription"],
        "image_picker": ["NSCameraUsageDescription", "NSPhotoLibraryUsageDescription"],
        "local_auth": ["NSFaceIDUsageDescription"],
        "flutter_contacts": ["NSContactsUsageDescription"],
        "contacts_service": ["NSContactsUsageDescription"],
        "gal": ["NSPhotoLibraryAddUsageDescription"],
        "image_gallery_saver": ["NSPhotoLibraryAddUsageDescription"],
        "geolocator": ["NSLocationWhenInUseUsageDescription"],
        "record": ["NSMicrophoneUsageDescription"],
    }
    for plugin, keys in needs.items():
        if re.search(rf"^\s+{plugin}:", pubspec, re.M):
            for k in keys:
                if not str(info.get(k, "")).strip():
                    err(f"Info.plist: {k} is missing (needed by {plugin}).")
    if "app_tracking_transparency" in pubspec and not info.get("NSUserTrackingUsageDescription"):
        err("Info.plist: NSUserTrackingUsageDescription is missing (app_tracking_transparency).")

    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        err("Info.plist: ITSAppUsesNonExemptEncryption must be false (the app only uses HTTPS/TLS from iOS).")
    if info.get("CFBundleShortVersionString") != "$(FLUTTER_BUILD_NAME)" or info.get("CFBundleVersion") != "$(FLUTTER_BUILD_NUMBER)":
        err("Info.plist: the version keys must come from pubspec.yaml (FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER).")
    if "UIScene" not in json.dumps(info.get("UIApplicationSceneManifest", {})):
        err("Info.plist: no UIScene configuration (apps built with the iOS 26 SDK must adopt the scene life cycle).")
    orient = info.get("UISupportedInterfaceOrientations", [])
    if orient != ["UIInterfaceOrientationPortrait"]:
        warn(f"Info.plist: iPhone orientations are {orient}; the layouts are portrait-only.")

    # Privacy manifest.
    pm = IOS / "Runner/PrivacyInfo.xcprivacy"
    if not pm.exists():
        err("ios/Runner/PrivacyInfo.xcprivacy is missing.")
    else:
        manifest = plistlib.loads(pm.read_bytes())
        if manifest.get("NSPrivacyTracking") is not False:
            err("PrivacyInfo.xcprivacy: NSPrivacyTracking must be false.")
        if not manifest.get("NSPrivacyAccessedAPITypes"):
            err("PrivacyInfo.xcprivacy: no required-reason API declarations.")
        if "PrivacyInfo.xcprivacy in Resources" not in pbx:
            err("PrivacyInfo.xcprivacy is not in the Runner target's Copy Bundle Resources.")

    # Push environment per configuration.
    for name in ("Release", "Profile"):
        blocks = re.findall(r"\{\s*isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\};\s*name = " + name + ";", pbx, re.S)
        runner = [b for b in blocks if "CODE_SIGN_ENTITLEMENTS" in b]
        for b in runner:
            path = re.search(r"CODE_SIGN_ENTITLEMENTS = ([^;]+);", b).group(1).strip('"')
            ent = plistlib.loads((IOS / path).read_bytes())
            if ent.get("aps-environment") != "production":
                err(f"{name} signs with {path}, whose aps-environment is not production.")
    if 'TARGETED_DEVICE_FAMILY = "1,2"' in pbx:
        warn("TARGETED_DEVICE_FAMILY includes iPad: iPad screenshots and iPad review become required.")

    m = re.search(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);", pbx)
    if m and float(m.group(1)) < 13:
        err(f"IPHONEOS_DEPLOYMENT_TARGET {m.group(1)} is below what Flutter supports.")

    # Bundle id vs Firebase's iOS app.
    ids = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z0-9.\-]+);", pbx)) - {
        i for i in re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z0-9.\-]+);", pbx) if i.endswith("RunnerTests")}
    bundle = args.bundle_id or (sorted(ids)[0] if len(ids) == 1 else None)
    if not bundle:
        err(f"Runner has several bundle ids: {sorted(ids)}.")
    defines_path = ROOT / "firebase.defines.json"
    if defines_path.exists():
        defines = json.loads(defines_path.read_text())
        fb = defines.get("FIREBASE_IOS_BUNDLE_ID") or bundle
        if bundle and fb != bundle:
            err(f"Bundle id mismatch: the app is built as {bundle}, but the Firebase iOS app is {fb}. "
                "APNs rejects the device tokens and iOS gets no push. Register the Firebase iOS app under the "
                "App Store bundle id (or set the repository variable IOS_BUNDLE_ID to the Firebase one), "
                "then remove FIREBASE_IOS_BUNDLE_ID.")
        for k in ("FIREBASE_PROJECT_ID", "FIREBASE_MESSAGING_SENDER_ID", "FIREBASE_IOS_APP_ID", "FIREBASE_IOS_API_KEY"):
            if not defines.get(k):
                err(f"firebase.defines.json: {k} is empty (no iOS push).")
    else:
        err("mobile_app/firebase.defines.json is missing: the build would have no push notifications.")

    v = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)", pubspec, re.M)
    if not v:
        err("pubspec.yaml: version must be MAJOR.MINOR.PATCH+BUILD.")

    print(f"bundle id: {bundle}  version: {v.group(1) + ' (' + v.group(2) + ')' if v else '?'}")
    for w in warnings:
        print(f"::warning::{w}")
    for e in errors:
        print(f"::{'error' if args.strict else 'warning'}::{e}")
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if (errors and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
