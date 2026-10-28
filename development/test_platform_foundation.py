"""Contract and inventory tests; no converter, scheduler or library access."""
import ast
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "app/shared/contracts.py"
spec = importlib.util.spec_from_file_location("contracts", MODULE)
contracts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contracts)


def load(relative):
    return contracts.read_json((ROOT / relative).read_bytes())


class FoundationTests(unittest.TestCase):
    def setUp(self):
        self.legacy = load("development/contracts/examples/legacy-windows.example.json")
        self.settings = load("development/contracts/examples/settings-v1.example.json")
        self.request = load("development/contracts/examples/request-v1.example.json")

    def rejects(self, operation, value):
        with self.assertRaises((contracts.ContractError, ValueError)):
            operation(value)

    def test_examples_and_python38_syntax(self):
        ast.parse(MODULE.read_text(encoding="utf-8"), feature_version=(3, 8))
        contracts.validate_settings(self.settings)
        contracts.validate_request(self.request)
        contracts.validate_receipt(load("development/contracts/examples/receipt-v1.example.json"))
        self.assertEqual(0, contracts.validate_event_stream(
            load("development/contracts/examples/events-v1.example.json"), "example-preview"))

    def test_lossless_nonmutating_import(self):
        before = copy.deepcopy(self.legacy)
        migrated = contracts.import_windows_settings(self.legacy)
        self.assertEqual(self.settings, migrated)
        self.assertEqual(before, self.legacy)
        self.assertEqual(before, migrated["extensions"]["legacyWindowsSettings"])
        self.assertEqual("Replace", migrated["workflow"]["DuplicateAction"])
        self.assertEqual("manual", migrated["schedule"]["Activation"])
        self.assertEqual("powershell-like-v1", migrated["folderRules"][0]["PatternSyntax"])
        self.assertEqual(before["FolderRules"][0]["Pattern"], migrated["folderRules"][0]["Pattern"])
        migrated["extensions"]["legacyWindowsSettings"]["CustomPreference"]["keep"] = False
        self.assertTrue(self.legacy["CustomPreference"]["keep"])

    def test_import_does_not_guess_future_versions_or_remap_platforms(self):
        self.legacy["Version"] = 2
        self.rejects(contracts.import_windows_settings, self.legacy)
        self.rejects(lambda value: contracts.import_windows_settings(value, "linux-x86_64"), self.settings)

    def test_optional_chapter_grouping_survives_import(self):
        self.legacy.update(BundleChapters=True, BundleTargetPages=200,
                           ChapterPageThreshold=100, BundleMaxMiB=350, HoldShortBundles=True)
        migrated = contracts.import_windows_settings(self.legacy)
        self.assertEqual(dict(contracts.BUNDLING_DEFAULTS, enabled=True, holdShortGroups=True), migrated["bundling"])
        self.assertTrue(migrated["extensions"]["legacyWindowsSettings"]["BundleChapters"])
        for key, value in (("targetSourcePages", 0), ("chapterPageThreshold", 201),
                           ("maxOutputMiB", 400), ("enabled", "true")):
            invalid = copy.deepcopy(migrated)
            invalid["bundling"][key] = value
            self.rejects(contracts.validate_settings, invalid)

    def test_optional_reader_organization_and_volume_grouping(self):
        self.legacy.update(BookTitleStyle="NumberFirst", CoverNumberBadge=True,
                           SeriesAliases={"Long Series": "Short"}, BundleVolumes=True, VolumeTargetPages=600)
        migrated = contracts.import_windows_settings(self.legacy)
        self.assertEqual("Short", migrated["organization"]["seriesAliases"]["Long Series"])
        self.assertTrue(migrated["bundling"]["combineVolumes"])
        self.assertEqual(600, migrated["bundling"]["volumeTargetSourcePages"])
        migrated["bundling"]["volumeTargetSourcePages"] = 0
        self.rejects(contracts.validate_settings, migrated)

    def test_original_removal_requires_acknowledgement(self):
        self.legacy.update(OriginalsAction="Delete", DeleteOriginalsConfirmed=False, ArchiveFolder="")
        self.rejects(contracts.import_windows_settings, self.legacy)
        self.legacy["DeleteOriginalsConfirmed"] = True
        migrated = contracts.import_windows_settings(self.legacy)
        self.assertEqual("Delete", migrated["originalHandling"]["action"])
        migrated["originalHandling"]["deleteConfirmed"] = "yes"
        self.rejects(contracts.validate_settings, migrated)

    def test_scribe_compatibility_and_stopped_state(self):
        self.legacy["ScribeCompatibility"] = True
        migrated = contracts.import_windows_settings(self.legacy)
        self.assertTrue(migrated["conversion"]["ScribeCompatibility"])
        migrated["conversion"]["ScribeCompatibility"] = "true"
        self.rejects(contracts.validate_settings, migrated)
        self.assertEqual("stopped", contracts.LEGACY_STATES["Stopped"])

    def test_clean_filename_style_survives_import(self):
        self.legacy["BookTitleStyle"] = "Clean"
        migrated = contracts.import_windows_settings(self.legacy)
        self.assertEqual("Clean", migrated["organization"]["titleStyle"])
        contracts.validate_settings(migrated)

    def test_unknown_fields_versions_and_integer_types(self):
        for key, replacement in (("schemaVersion", 2), ("schemaVersion", True),
                                 ("targetId", "linux-i386")):
            value = copy.deepcopy(self.settings)
            value[key] = replacement
            self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["silentlyIgnoredSetting"] = True
        self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["conversion"]["Cropping"] = True
        self.rejects(contracts.validate_settings, value)

    def test_platform_paths_and_overlap_checks(self):
        value = copy.deepcopy(self.settings)
        value["folders"]["originals"] = "c:/books/incoming/../INCOMING/archive"
        self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["folders"]["working"] = "C:\\"
        self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["targetId"] = "linux-x86_64"
        value["folders"] = {key: "/mounted/books/" + key for key in value["folders"]}
        value["tools"] = {key: None for key in value["tools"]}
        contracts.validate_settings(value)
        value["folders"]["working"] = "\\\\server\\share\\work"
        self.rejects(contracts.validate_settings, value)

    def test_command_prefix_is_an_argument_array(self):
        self.settings["tools"]["kcc"] = {"program": "C:\\Python\\python.exe", "prefixArgs": ["C:\\KCC source\\kcc-c2e.py"]}
        contracts.validate_settings(self.settings)
        self.settings["tools"]["kcc"]["prefixArgs"] = '"C:\\KCC source\\kcc-c2e.py"'
        self.rejects(contracts.validate_settings, self.settings)

    def test_selected_retry_scope_is_explicit_and_contained(self):
        self.request["command"] = "run"
        for paths in ([], ["../outside.cbz"], ["/outside.cbz"], ["C:/outside.cbz"], ["Series\\book.cbz"]):
            self.request["selection"] = {"relativePaths": paths, "duplicateActionOverride": "Replace"}
            self.rejects(contracts.validate_request, self.request)
        self.request["selection"] = {"relativePaths": ["漫画 [A]/book.cbz"], "duplicateActionOverride": "KeepBoth"}
        contracts.validate_request(self.request)
        self.request["command"] = "preview"
        self.rejects(contracts.validate_request, self.request)

    def test_stop_targets_an_owned_run(self):
        self.request["command"] = "stop"
        self.rejects(contracts.validate_request, self.request)
        self.request["runId"] = "owned-run"
        contracts.validate_request(self.request)

    def test_invalid_conversion_preset_and_schedule(self):
        value = copy.deepcopy(self.settings)
        value["conversion"]["Profile"] = "KoC"
        self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["folderRules"][0]["Options"] = {"KccExe": "C:\\unexpected.exe"}
        self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["schedule"]["Activation"] = "automatic"
        self.rejects(contracts.validate_settings, value)
        value = copy.deepcopy(self.settings)
        value["schedule"]["Times"] = ["25:00"]
        self.rejects(contracts.validate_settings, value)

    def test_receipts_reject_traversal_and_incomplete_output_sets(self):
        receipt = load("development/contracts/examples/receipt-v1.example.json")
        receipt["outputs"][0]["relativePath"] = "../book.mobi"
        self.rejects(contracts.validate_receipt, receipt)
        receipt = load("development/contracts/examples/receipt-v1.example.json")
        receipt["outputs"] = []
        self.rejects(contracts.validate_receipt, receipt)
        receipt = load("development/contracts/examples/receipt-v1.example.json")
        receipt["outputs"][0]["sha256"] = "not-a-hash"
        self.rejects(contracts.validate_receipt, receipt)

    def test_protocol_detects_missing_or_inconsistent_terminal_results(self):
        events = load("development/contracts/examples/events-v1.example.json")
        self.rejects(lambda value: contracts.validate_event_stream(value, "example-preview"), events[:-1])
        for change in ("requestId", "sequence", "exitCode"):
            value = copy.deepcopy(events)
            if change == "requestId":
                value[-1]["requestId"] = "another-request"
            elif change == "sequence":
                value[-1]["sequence"] = 7
            else:
                value[-1]["data"]["exitCode"] = 1
            self.rejects(lambda item: contracts.validate_event_stream(item, "example-preview"), value)
        self.rejects(lambda item: contracts.validate_event_stream(item, "example-preview"), events + events)

    def test_strict_json_does_not_accept_ambiguous_or_nonfinite_values(self):
        for text in ('{"a":1,"a":2}', '{"value":NaN}', '{"value":1e9999}'):
            self.rejects(contracts.read_json, text)
        self.assertEqual({"value": "漫画"}, contracts.read_json('\ufeff{"value":"漫画"}'))

    def test_inventory_is_evidence_not_new_platform_approval(self):
        inventory = load("development/platforms/inventory.v1.json")
        evidence = load("development/platforms/kcc-12.0.0-evidence.json")
        self.assertEqual(set(contracts.TARGETS), {row["id"] for row in inventory["targets"]})
        self.assertEqual(7, len(inventory["targets"]))
        self.assertTrue(inventory["approvalsUnchanged"])
        self.assertEqual(inventory["sourceCommit"], evidence["sourceCommit"])
        self.assertRegex(inventory["sourceCommit"], r"^[a-f0-9]{40}$")
        assets = {asset["name"]: asset for asset in evidence["assets"]}
        for row in inventory["targets"]:
            self.assertFalse(row["certification"]["nativeVerified"])
            self.assertIsNone(row["certification"]["minimumOs"])
            for asset in row["upstreamAssets"]:
                self.assertEqual(assets[asset["name"]], asset)
                self.assertRegex(asset["sha256"], r"^[a-f0-9]{64}$")
                self.assertTrue(asset["url"].startswith("https://github.com/ciromattia/kcc/releases/download/v12.0.0/"))
        linux = next(row for row in inventory["targets"] if row["id"] == "linux-x86_64")
        self.assertEqual(1, linux["deliveryPriority"])
        # Dated platform evidence is independent of the user's converter choice.
        self.assertIn("tool_cli_c2e_12.0.0_AMD64.exe", assets)


if __name__ == "__main__":
    unittest.main(verbosity=2)
