#!/usr/bin/env python3

import json
import sys
from pathlib import Path


'''
metadata.json template

{
  "version_ipa": "0.0.0",
  "version_date": "2000-12-18T00:00:00Z",
  "is_beta": true,
  "release_channel": "alpha",
  "size": 0,
  "sha256": "",
  "localized_description": "Invalid Update",
  "download_url": "https://github.com/SideStore/SideStore/releases/download/0.0.0/SideStore.ipa",
  "bundle_identifier": "com.SideStore.SideStore"
}
'''


# ----------------------------------------------------------
# args
# ----------------------------------------------------------

if len(sys.argv) < 3:
    print("Usage: python3 update_apps.py <metadata.json> <source.json>")
    sys.exit(1)

metadata_file = Path(sys.argv[1])
source_file = Path(sys.argv[2])


# ----------------------------------------------------------
# load metadata
# ----------------------------------------------------------

if not metadata_file.exists():
    print(f"Missing metadata file: {metadata_file}")
    sys.exit(1)

with open(metadata_file, "r", encoding="utf-8") as f:
    meta = json.load(f)

VERSION_IPA = meta.get("version_ipa")
VERSION_DATE = meta.get("version_date")
IS_BETA = meta.get("is_beta")
RELEASE_CHANNEL = meta.get("release_channel")
SIZE = meta.get("size")
SHA256 = meta.get("sha256")
LOCALIZED_DESCRIPTION = meta.get("localized_description")
DOWNLOAD_URL = meta.get("download_url")
BUNDLE_IDENTIFIER = meta.get("bundle_identifier")

print("  ====> Required parameter list <====")
print("Bundle Identifier:", BUNDLE_IDENTIFIER)
print("Version:", VERSION_IPA)
print("Version Date:", VERSION_DATE)
print("IsBeta:", IS_BETA)
print("ReleaseChannel:", RELEASE_CHANNEL)
print("Size:", SIZE)
print("Sha256:", SHA256)
print("Localized Description:", LOCALIZED_DESCRIPTION)
print("Download URL:", DOWNLOAD_URL)


# ----------------------------------------------------------
# validation
# ----------------------------------------------------------

if (
    not BUNDLE_IDENTIFIER
    or not VERSION_IPA
    or not VERSION_DATE
    or not RELEASE_CHANNEL
    or not SIZE
    or not SHA256
    or not LOCALIZED_DESCRIPTION
    or not DOWNLOAD_URL
):
    print("One or more required metadata fields missing")
    sys.exit(1)

SIZE = int(SIZE)
RELEASE_CHANNEL = RELEASE_CHANNEL.lower()


# ----------------------------------------------------------
# load or create source.json
# ----------------------------------------------------------

if source_file.exists():
    with open(source_file, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    print("source.json missing — creating minimal structure")
    data = {
        "version": 2,
        "apps": []
    }

if int(data.get("version", 1)) < 2:
    print("Only v2 and above are supported")
    sys.exit(1)


# ----------------------------------------------------------
# ensure app entry exists
# ----------------------------------------------------------

apps = data.setdefault("apps", [])

app = next(
    (a for a in apps if a.get("bundleIdentifier") == BUNDLE_IDENTIFIER),
    None
)

if app is None:
    print("App entry missing — creating new app entry")
    app = {
        "bundleIdentifier": BUNDLE_IDENTIFIER,
        "releaseChannels": []
    }
    apps.append(app)


# ----------------------------------------------------------
# update logic 
# ----------------------------------------------------------

if RELEASE_CHANNEL == "stable":
    app.update({
        "version": VERSION_IPA,
        "versionDate": VERSION_DATE,
        "size": SIZE,
        "sha256": SHA256,
        "localizedDescription": LOCALIZED_DESCRIPTION,
        "downloadURL": DOWNLOAD_URL,
    })

channels = app.setdefault("releaseChannels", [])

new_version = {
    "version": VERSION_IPA,
    "date": VERSION_DATE,
    "localizedDescription": LOCALIZED_DESCRIPTION,
    "downloadURL": DOWNLOAD_URL,
    "size": SIZE,
    "sha256": SHA256,
}

tracks = [t for t in channels if t.get("track") == RELEASE_CHANNEL]

if len(tracks) > 1:
    print(f"Multiple tracks named {RELEASE_CHANNEL}")
    sys.exit(1)

if not tracks:
    channels.insert(0, {
        "track": RELEASE_CHANNEL,
        "releases": [new_version],
    })
else:
    tracks[0]["releases"][0] = new_version


# ----------------------------------------------------------
# save
# ----------------------------------------------------------

print("\nUpdated Sources File:\n")
print(json.dumps(data, indent=2, ensure_ascii=False))

with open(source_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print("JSON successfully updated.")