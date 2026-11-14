"""Write the SideStore/AltStore source (source.json) that points at the IPA of this build's GitHub release.

Usage: sidestore_source.py <app Info.plist> <ipa path> <owner/repo> <release tag> <output path>
SideStore offers an update when the first entry of `versions` differs from the installed version or build number,
so every CI build gets its own build number (the run number) and its own release.
"""
import datetime
import json
import os
import plistlib
import sys

info_path, ipa_path, repo, tag, out_path = sys.argv[1:6]
with open(info_path, "rb") as f:
    info = plistlib.load(f)

source = {
    "name": "RunCoach",
    "subtitle": "App de course à pied personnelle",
    "website": f"https://github.com/{repo}",
    "apps": [{
        "name": "RunCoach",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "RunCoach",
        "subtitle": "Coach, plan et replay, avec ta montre Garmin",
        "localizedDescription": "Import Garmin, plan d'entraînement et coach IA, envoi des séances sur la montre, replay sur carte. Guide : README du dépôt.",
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "tintColor": "#FF6A1F",
        "category": "lifestyle",
        "versions": [{
            "version": info["CFBundleShortVersionString"],
            "buildVersion": info["CFBundleVersion"],
            "date": datetime.date.today().isoformat(),
            "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/RunCoach.ipa",
            "size": os.path.getsize(ipa_path),
            "minOSVersion": info.get("MinimumOSVersion", "18.0"),
        }],
        # Pas d'entitlement ni d'autorisation de confidentialité (NS…UsageDescription) dans l'app.
        "appPermissions": {"entitlements": [], "privacy": {}},
    }],
    "news": [],
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=1)
print(json.dumps(source["apps"][0]["versions"][0]))
