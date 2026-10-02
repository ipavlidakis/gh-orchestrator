#!/usr/bin/env python3
"""Update the cask from the latest published release, verifying downloaded bytes."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote


def github_json(endpoint):
    return json.loads(subprocess.check_output(["gh", "api", endpoint], text=True))


def update_cask(repository, tag, cask_path):
    release = github_json(f"repos/{repository}/releases/tags/{quote(tag, safe='')}")
    if release["draft"] or release["prerelease"]:
        print(f"Skipping draft or prerelease {tag}.")
        return
    latest = github_json(f"repos/{repository}/releases/latest")
    if release["id"] != latest["id"]:
        print(f"Skipping {tag}: latest stable release is {latest['tag_name']}.")
        return
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Stable release tags must match the cask version, e.g. 0.5.3")

    content = cask_path.read_text(encoding="utf-8")
    current = re.search(r'^  version "([0-9]+\.[0-9]+\.[0-9]+)"$', content, re.MULTILINE)
    if current is None:
        raise ValueError("Expected one numeric cask version")
    if tuple(map(int, tag.split("."))) < tuple(map(int, current[1].split("."))):
        print(f"Skipping {tag}: cask already has newer version {current[1]}.")
        return

    dmg_name = f"GHOrchestrator-{tag}.dmg"
    checksum_name = f"{dmg_name}.sha256.txt"
    with tempfile.TemporaryDirectory(prefix="ghorchestrator-homebrew-") as directory:
        subprocess.run([
            "gh", "release", "download", tag, "--repo", repository,
            "--pattern", dmg_name, "--pattern", checksum_name, "--dir", directory,
        ], check=True)
        checksum_fields = (Path(directory) / checksum_name).read_text(encoding="utf-8").split()
        if not checksum_fields:
            raise ValueError("Release checksum asset is empty")
        checksum = checksum_fields[0]
        digest = hashlib.sha256((Path(directory) / dmg_name).read_bytes()).hexdigest()
        if not re.fullmatch(r"[0-9a-f]{64}", checksum) or checksum != digest:
            raise ValueError("Downloaded DMG does not match the release checksum")

    # Recheck after downloading so a newer release cannot be overwritten by this run.
    if github_json(f"repos/{repository}/releases/latest")["id"] != release["id"]:
        print(f"Skipping {tag}: a newer stable release was published during verification.")
        return
    content, versions = re.subn(r'^  version "[^"]+"$', f'  version "{tag}"', content, flags=re.MULTILINE)
    content, hashes = re.subn(r'^  sha256 "[^"]+"$', f'  sha256 "{digest}"', content, flags=re.MULTILINE)
    if versions != 1 or hashes != 1:
        raise ValueError("Expected exactly one cask version and SHA-256")
    cask_path.write_text(content, encoding="utf-8")
    print(f"Verified Homebrew cask {tag}: SHA-256 {digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    update_cask(args.repo, args.tag, Path(__file__).resolve().parents[1] / "Casks/gh-orchestrator.rb")
