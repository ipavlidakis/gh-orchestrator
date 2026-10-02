import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("updater", SCRIPT_DIR / "update_homebrew_cask.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class HomebrewReleaseTests(unittest.TestCase):
    def test_only_verified_latest_stable_assets_change_the_cask(self):
        cases = ["stable", "idempotent", "draft", "prerelease", "older", "rollback", "superseded", "bad_checksum", "empty_checksum", "missing_asset", "malformed_cask", "invalid_tag"]
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                cask = Path(directory) / "cask.rb"
                dmg = b"independent release artifact fixture"
                digest = hashlib.sha256(dmg).hexdigest()
                current = "0.5.3" if case == "idempotent" else "0.5.4" if case == "rollback" else "0.5.2"
                original = f'cask "gh-orchestrator" do\n  version "{current}"\n  sha256 "{digest if case == "idempotent" else "0" * 64}"\n  name "GHOrchestrator"\nend\n'
                if case == "malformed_cask":
                    original += '  sha256 "duplicate"\n'
                cask.write_text(original)
                tag = "v0.5.3" if case == "invalid_tag" else "0.5.3"
                release = {"id": 1, "tag_name": tag, "draft": case == "draft", "prerelease": case == "prerelease"}
                newer = {"id": 2, "tag_name": "0.5.4"}
                responses = [release, newer if case == "older" else release, newer if case == "superseded" else release]

                def download(command, check):
                    if case == "missing_asset":
                        raise subprocess.CalledProcessError(1, command)
                    target = Path(command[-1])
                    (target / "GHOrchestrator-0.5.3.dmg").write_bytes(dmg)
                    checksum = "0" * 64 if case == "bad_checksum" else digest
                    (target / "GHOrchestrator-0.5.3.dmg.sha256.txt").write_text("" if case == "empty_checksum" else f"{checksum}  GHOrchestrator-0.5.3.dmg\n")

                with patch.object(updater, "github_json", side_effect=responses), patch.object(updater.subprocess, "run", side_effect=download):
                    if case in {"bad_checksum", "empty_checksum", "malformed_cask", "invalid_tag", "missing_asset"}:
                        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                            updater.update_cask("ipavlidakis/gh-orchestrator", tag, cask)
                    else:
                        updater.update_cask("ipavlidakis/gh-orchestrator", tag, cask)
                if case == "stable":
                    self.assertEqual(cask.read_text(), f'cask "gh-orchestrator" do\n  version "0.5.3"\n  sha256 "{digest}"\n  name "GHOrchestrator"\nend\n')
                else:
                    self.assertEqual(cask.read_text(), original)

    def test_release_publication_waits_for_both_asset_uploads(self):
        for case in ["public", "draft", "failed_upload", "failed_publish"]:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                script = root / "script/release_dmg.sh"
                script.parent.mkdir()
                script.write_bytes((SCRIPT_DIR / "release_dmg.sh").read_bytes())
                tools = root / "bin"
                tools.mkdir()
                fake = tools / "fake"
                fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
tool = pathlib.Path(sys.argv[0]).name
state_path = pathlib.Path(os.environ["RELEASE_TEST_STATE"])
state = json.loads(state_path.read_text()) if state_path.exists() else []
if tool == "xcodebuild":
    archive = pathlib.Path(args[args.index("-archivePath") + 1])
    (archive / "Products/Applications/GHOrchestrator.app").mkdir(parents=True)
elif tool == "hdiutil":
    pathlib.Path(args[-1]).write_bytes(b"test DMG")
elif tool == "curl":
    method = args[args.index("--request") + 1]
    url = args[-1]
    output = pathlib.Path(args[args.index("--output") + 1])
    status, payload = "200", {}
    if method == "GET":
        status = "404"
    elif method == "POST" and url.endswith("/releases"):
        body = json.loads(pathlib.Path(args[args.index("--data-binary") + 1][1:]).read_text())
        state.append("create_draft" if body["draft"] else "create_public")
        payload = {"id": 1, "draft": body["draft"], "upload_url": "https://uploads.github.com/releases/1/assets{?name,label}"}
        status = "201"
    elif method == "POST":
        name = url.split("name=")[1]
        state.append("upload:" + name)
        status = "500" if os.environ["RELEASE_TEST_FAIL"] == "failed_upload" and name.endswith(".txt") else "201"
        payload = {"browser_download_url": "https://github.com/test/asset"}
    elif method == "PATCH":
        assert state == ["create_draft", "upload:GHOrchestrator-0.5.3.dmg", "upload:GHOrchestrator-0.5.3.dmg.sha256.txt"]
        state.append("publish")
        status = "500" if os.environ["RELEASE_TEST_FAIL"] == "failed_publish" else "200"
        payload = {"draft": False}
    state_path.write_text(json.dumps(state))
    output.write_text(json.dumps(payload))
    print(status, end="")
''')
                fake.chmod(0o755)
                for name in ["tuist", "xcodebuild", "codesign", "ditto", "hdiutil", "curl"]:
                    (tools / name).symlink_to(fake)
                config = root / "release.json"
                config.write_text(json.dumps({"draft": case == "draft", "createRelease": True, "upload": True, "appleDeveloperTeamID": "TEST", "appleDeveloperIDApplication": "TEST", "githubOAuthClientID": "TEST", "githubToken": "TEST"}))
                subprocess.run(["git", "init", "--quiet", str(root)], check=True)
                environment = os.environ.copy()
                environment.update(PATH=f"{tools}:{environment['PATH']}", RELEASE_TEST_STATE=str(root / "state.json"), RELEASE_TEST_FAIL=case)
                for name in ["GITHUB_TOKEN", "GH_ORCHESTRATOR_GITHUB_CLIENT_ID", "APPLE_DEVELOPER_TEAM_ID", "APPLE_DEVELOPER_ID_APPLICATION"]:
                    environment.pop(name, None)
                result = subprocess.run(["bash", str(script), "--config", str(config), "--version", "0.5.3", "--build", "50", "--allow-dirty", "--skip-notarization"], env=environment, cwd=root, capture_output=True, text=True)
                events = json.loads((root / "state.json").read_text())
                self.assertEqual(result.returncode == 0, case in {"public", "draft"}, result.stdout + result.stderr)
                self.assertEqual(events, ["create_draft", "upload:GHOrchestrator-0.5.3.dmg", "upload:GHOrchestrator-0.5.3.dmg.sha256.txt"] + (["publish"] if case in {"public", "failed_publish"} else []))


if __name__ == "__main__":
    unittest.main()
