"""Versioned, side-effect-free contracts for future KCCAutomate workers.

Python 3.8+; standard library only. Importing this module runs no conversions,
opens no folders, registers no schedules and approves no platform or tool.
"""
import copy
import datetime
import json
import math
import ntpath
import posixpath
import re

SCHEMA_VERSION = 1
PROTOCOL_VERSION = 1
TARGETS = (
    "linux-x86_64", "linux-aarch64", "windows-x86_64", "windows-arm64",
    "macos-intel", "macos-arm64", "windows7-legacy",
)
COMMANDS = ("preview", "run", "check-tools", "cleanup", "stop")
EXIT_CODES = {"completed": 0, "failed": 1, "stopped": 2, "busy": 3,
              "rejected": 4, "tools-unready": 5}
ITEM_STATES = ("waiting", "waiting-download", "converting", "converted",
               "archived", "conflict", "failed", "skipped-existing",
               "accompanying", "ignored", "originals-deleted", "stopped")
LEGACY_STATES = dict(zip(
    ("Waiting", "Waiting for download", "Converting", "Converted", "Archived",
     "Conflict", "Failed", "Skipped existing output", "Accompanying", "Ignored", "Originals deleted", "Stopped"),
    ITEM_STATES,
))
POLICIES = ("Review", "Replace", "KeepBoth", "Skip")
EXTENSIONS = (".cbz", ".pdf", ".epub", ".cbr", ".cb7")
CONVERSION_DEFAULTS = {
    "Profile": "KS", "Format": "MOBI", "Cropping": 0, "Splitter": 0,
    "MangaStyle": True, "Upscale": True, "Stretch": False, "Autolevel": False,
    "NoAutocontrast": False, "ForceColor": False, "ForcePng": False,
    "Webtoon": False, "Gamma": 0,
}
WORKFLOW_DEFAULTS = {
    "QuietMinutes": 30, "InputExtensions": [".cbz"], "DuplicateAction": "Review",
    "OutputNaming": "{name}", "ConvertJxl": True, "AutoCleanup": False,
    "SuccessRetentionDays": 7, "FailureRetentionDays": 30,
}
BUNDLING_DEFAULTS = {
    "enabled": False, "targetSourcePages": 200, "chapterPageThreshold": 100,
    "maxOutputMiB": 350, "holdShortGroups": False,
}


class ContractError(ValueError):
    pass


def _require(condition, message):
    if not condition:
        raise ContractError(message)


def _object(value, required, optional=()):
    _require(isinstance(value, dict), "Expected an object")
    _require(set(required) <= set(value), "Missing fields: " + str(set(required) - set(value)))
    _require(set(value) <= set(required) | set(optional), "Unknown contract fields")


def _string(value, empty=False):
    _require(isinstance(value, str) and "\0" not in value and (empty or bool(value)),
             "Expected a nonempty string without NUL")


def _integer(value, minimum, maximum=None):
    _require(type(value) is int and value >= minimum and
             (maximum is None or value <= maximum), "Invalid integer value")


def _boolean(value):
    _require(type(value) is bool, "Expected a boolean")


def _version(value, expected):
    _require(type(value) is int and value == expected, "Unsupported contract version")


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, "Duplicate JSON field: " + key)
        result[key] = value
    return result


def _float(text):
    value = float(text)
    _require(math.isfinite(value), "Non-finite JSON number")
    return value


def read_json(text):
    """Read a bounded UTF-8 JSON document, accepting a Windows UTF-8 BOM."""
    if isinstance(text, bytes):
        _require(len(text) <= 4 * 1024 * 1024, "JSON document too large")
        text = text.decode("utf-8-sig")
    _string(text)
    _require(len(text.encode("utf-8")) <= 4 * 1024 * 1024, "JSON document too large")
    try:
        return json.loads(text.lstrip("\ufeff"), object_pairs_hook=_pairs,
                          parse_float=_float,
                          parse_constant=lambda value: (_ for _ in ()).throw(
                              ContractError("Non-finite JSON number: " + value)))
    except (ValueError, RecursionError) as error:
        raise ContractError(str(error)) from error


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False)


def _native_path(value, target):
    _string(value)
    if target.startswith("windows"):
        path = ntpath.normpath(value)
        drive, tail = ntpath.splitdrive(path)
        _require(bool(drive) and tail.startswith("\\"), "Use a full Windows path")
        return path.casefold(), drive.casefold() + "\\", "\\"
    _require(value.startswith("/") and not value.startswith("//"), "Use an absolute mounted POSIX path")
    return posixpath.normpath(value), "/", "/"


def relative_path(value):
    _string(value)
    _require(not value.startswith("/") and "\\" not in value and
             not ntpath.splitdrive(value)[0] and
             all(part not in ("", ".", "..") for part in value.split("/")),
             "Use a contained relative path with forward slashes")
    return value


def _naming(value):
    _string(value)
    remaining = value
    for token in ("{name}", "{profile}", "{format}"):
        remaining = remaining.replace(token, "")
    _require(not re.search(r'[<>:"/\\|?*\x00-\x1f{}]', remaining) and
             not value.endswith((".", " ")), "Invalid output naming template")


def _conversion(value, partial=False):
    _object(value, () if partial else CONVERSION_DEFAULTS,
            tuple(CONVERSION_DEFAULTS) + ("ScribeCompatibility",) if partial else ("ScribeCompatibility",))
    for key, item in value.items():
        if key == "Profile":
            _require(isinstance(item, str) and re.fullmatch(r"[A-Za-z0-9]+", item), "Invalid reader profile")
        elif key == "Format":
            _require(item in ("MOBI", "EPUB", "CBZ", "PDF"), "Unsupported output format")
        elif key in ("Cropping", "Splitter"):
            _integer(item, 0, 2)
        elif key == "Gamma":
            _require(type(item) in (int, float) and math.isfinite(item) and item >= 0,
                     "Gamma must be a finite nonnegative number")
        else:
            _boolean(item)


def _kindle_format(conversion):
    if conversion["Format"] == "MOBI":
        _require(re.match(r"^K(?!o)", conversion["Profile"]) is not None,
                 "MOBI requires a Kindle profile")


def validate_settings(value):
    """Validate structure and lexical paths only; live readiness is separate."""
    _object(value, ("schemaVersion", "targetId", "folders", "tools", "conversion",
                    "workflow", "folderRules", "schedule", "extensions"), ("bundling", "organization", "originalHandling"))
    _version(value["schemaVersion"], SCHEMA_VERSION)
    _require(value["targetId"] in TARGETS, "Target is outside the KCC inventory")
    target = value["targetId"]
    _object(value["folders"], ("incoming", "converted", "originals", "working"))
    handling = value.get("originalHandling", {"action": "Archive", "deleteConfirmed": False})
    _object(handling, ("action", "deleteConfirmed"))
    _require(handling["action"] in ("Archive", "Delete"), "Unknown original handling action")
    _boolean(handling["deleteConfirmed"])
    _require(handling["action"] != "Delete" or handling["deleteConfirmed"], "Deleting originals requires acknowledgement")
    _string(value["folders"]["originals"], empty=True)
    paths = [_native_path(path, target) for key, path in value["folders"].items()
             if key != "originals" or handling["action"] == "Archive"]
    for path, root, separator in paths:
        _require(path != root, "Choose subfolders, not filesystem/share roots")
    for index, (left, _, separator) in enumerate(paths):
        for right, _, _ in paths[index + 1:]:
            _require(left != right and not left.startswith(right.rstrip(separator) + separator)
                     and not right.startswith(left.rstrip(separator) + separator),
                     "Book/work folders must be separate and non-nested")
    _object(value["tools"], ("kcc", "djxl", "kindlegen", "sevenZip"))
    for command in value["tools"].values():
        if command is None:
            continue
        _object(command, ("program", "prefixArgs"))
        _native_path(command["program"], target)
        _require(isinstance(command["prefixArgs"], list), "Tool arguments must be an array")
        for argument in command["prefixArgs"]:
            _string(argument, empty=True)
    _conversion(value["conversion"])
    _kindle_format(value["conversion"])
    workflow = value["workflow"]
    _object(workflow, WORKFLOW_DEFAULTS)
    _integer(workflow["QuietMinutes"], 0, 1440)
    _integer(workflow["SuccessRetentionDays"], 1)
    _integer(workflow["FailureRetentionDays"], 1)
    _require(workflow["DuplicateAction"] in POLICIES, "Unknown duplicate policy")
    extensions = workflow["InputExtensions"]
    _require(isinstance(extensions, list) and extensions and
             all(isinstance(item, str) and item in EXTENSIONS for item in extensions)
             and len(set(extensions)) == len(extensions), "Choose distinct supported inputs")
    _boolean(workflow["ConvertJxl"])
    _boolean(workflow["AutoCleanup"])
    _naming(workflow["OutputNaming"])
    if "organization" in value:
        organization = value["organization"]
        _object(organization, ("titleStyle", "coverNumberBadge", "seriesAliases"))
        _require(organization["titleStyle"] in ("Original", "SeriesFirst", "NumberFirst", "Clean"), "Unknown title style")
        _boolean(organization["coverNumberBadge"])
        _require(isinstance(organization["seriesAliases"], dict), "Series aliases must be an object")
        for original, alias in organization["seriesAliases"].items():
            _string(original)
            _string(alias)
            _require(not re.search(r'[<>:"/\\|?*\x00-\x1f]', alias), "Invalid short series name")
    if "bundling" in value:
        bundling = value["bundling"]
        _object(bundling, BUNDLING_DEFAULTS, ("combineVolumes", "volumeTargetSourcePages"))
        _boolean(bundling["enabled"])
        _boolean(bundling["holdShortGroups"])
        _integer(bundling["targetSourcePages"], 50, 1000)
        _integer(bundling["chapterPageThreshold"], 1, bundling["targetSourcePages"])
        _integer(bundling["maxOutputMiB"], 10, 390)
        if "combineVolumes" in bundling:
            _boolean(bundling["combineVolumes"])
        if "volumeTargetSourcePages" in bundling:
            _integer(bundling["volumeTargetSourcePages"], 100, 5000)
    _require(isinstance(value["folderRules"], list), "Folder rules must be an array")
    for rule in value["folderRules"]:
        _object(rule, ("Pattern", "PatternSyntax", "PresetName", "Options"))
        _string(rule["Pattern"])
        _require(rule["PatternSyntax"] in ("powershell-like-v1", "glob-v1"), "Unknown rule syntax")
        _string(rule["PresetName"], empty=True)
        _require(isinstance(rule["Options"], dict), "Rule options must be an object")
        options = dict(rule["Options"])
        naming = options.pop("OutputNaming", workflow["OutputNaming"])
        _naming(naming)
        _conversion(options, partial=True)
        effective = dict(value["conversion"], **options)
        _kindle_format(effective)
    schedule = value["schedule"]
    _object(schedule, ("Times", "WakeComputer", "Activation"))
    _require(schedule["Activation"] == "manual", "Importing settings must not activate a schedule")
    _require(isinstance(schedule["Times"], list) and schedule["Times"] and
             all(isinstance(time, str) and re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", time)
                 for time in schedule["Times"]), "Use daily times in HH:mm format")
    _require(len(set(schedule["Times"])) == len(schedule["Times"]), "Duplicate schedule time")
    _boolean(schedule["WakeComputer"])
    _require(isinstance(value["extensions"], dict), "Extensions must be an object")
    canonical_json(value)
    return value


def import_windows_settings(legacy, target_id="windows-x86_64"):
    """Return a new envelope; never read/write settings or register a task."""
    _require(isinstance(legacy, dict), "Expected Windows settings object")
    _version(legacy.get("Version", 1), 1)
    _require(target_id in TARGETS and target_id.startswith("windows"),
             "Windows settings need an explicit Windows target; remap other OS paths manually")
    conversion = {key: copy.deepcopy(legacy.get(key, default))
                  for key, default in CONVERSION_DEFAULTS.items()}
    if "ScribeCompatibility" in legacy:
        conversion["ScribeCompatibility"] = copy.deepcopy(legacy["ScribeCompatibility"])
    workflow = {key: copy.deepcopy(legacy.get(key, default))
                for key, default in WORKFLOW_DEFAULTS.items()}
    if not legacy.get("DuplicateAction"):
        workflow["DuplicateAction"] = "Replace" if legacy.get("OverwriteConverted", False) else "Review"
    tools = {}
    for key, old_key in (("kcc", "KccExe"), ("djxl", "DjxlExe"),
                         ("kindlegen", "KindlegenExe"), ("sevenZip", "SevenZipExe")):
        program = legacy.get(old_key, "")
        tools[key] = {"program": program, "prefixArgs": []} if program else None
    rules = []
    for rule in legacy.get("FolderRules", []) or []:
        _require(isinstance(rule, dict), "Invalid legacy folder rule")
        options = rule.get("Options", {})
        _require(isinstance(options, dict), "Invalid legacy folder-rule options")
        _require(set(options) <= set(CONVERSION_DEFAULTS) | {"OutputNaming", "ScribeCompatibility"},
                 "Legacy rule has unsupported options; review before migration")
        rules.append({"Pattern": rule.get("Pattern", ""), "PatternSyntax": "powershell-like-v1",
                      "PresetName": rule.get("PresetName", ""), "Options": copy.deepcopy(options)})
    value = {
        "schemaVersion": SCHEMA_VERSION, "targetId": target_id,
        "folders": {"incoming": legacy.get("WatchFolder", ""),
                    "converted": legacy.get("ConvertedFolder", ""),
                    "originals": legacy.get("ArchiveFolder", ""),
                    "working": legacy.get("WorkFolder", "")},
        "tools": tools, "conversion": conversion, "workflow": workflow, "folderRules": rules,
        "schedule": {"Times": [time.strip() for time in legacy.get(
            "ScheduleTimes", "08:00, 14:00, 20:00").split(",")],
                     "WakeComputer": legacy.get("WakeComputer", False), "Activation": "manual"},
        "extensions": {"legacyWindowsSettings": copy.deepcopy(legacy)},
    }
    fields = (("enabled", "BundleChapters"), ("targetSourcePages", "BundleTargetPages"),
              ("chapterPageThreshold", "ChapterPageThreshold"),
              ("maxOutputMiB", "BundleMaxMiB"), ("holdShortGroups", "HoldShortBundles"))
    if any(old_key in legacy for _, old_key in fields):
        value["bundling"] = {key: copy.deepcopy(legacy.get(old_key, BUNDLING_DEFAULTS[key]))
                             for key, old_key in fields}
    if "BundleVolumes" in legacy or "VolumeTargetPages" in legacy:
        value.setdefault("bundling", copy.deepcopy(BUNDLING_DEFAULTS))
        value["bundling"].update(combineVolumes=legacy.get("BundleVolumes", False),
                                 volumeTargetSourcePages=legacy.get("VolumeTargetPages", 600))
    if any(key in legacy for key in ("BookTitleStyle", "CoverNumberBadge", "SeriesAliases")):
        value["organization"] = {"titleStyle": legacy.get("BookTitleStyle", "Original"),
                                 "coverNumberBadge": legacy.get("CoverNumberBadge", False),
                                 "seriesAliases": copy.deepcopy(legacy.get("SeriesAliases", {}))}
    if "OriginalsAction" in legacy or "DeleteOriginalsConfirmed" in legacy:
        value["originalHandling"] = {"action": legacy.get("OriginalsAction", "Archive"),
                                      "deleteConfirmed": legacy.get("DeleteOriginalsConfirmed", False)}
    return validate_settings(value)


def validate_request(value):
    _object(value, ("protocolVersion", "requestId", "command", "settings"),
            ("selection", "runId"))
    _version(value["protocolVersion"], PROTOCOL_VERSION)
    _require(isinstance(value["requestId"], str) and
             re.fullmatch(r"[A-Za-z0-9._-]{1,128}", value["requestId"]), "Invalid request ID")
    _require(value["command"] in COMMANDS, "Unknown command")
    validate_settings(value["settings"])
    if "selection" in value:
        _require(value["command"] == "run", "Selection is only allowed for run")
        selection = value["selection"]
        _object(selection, ("relativePaths",), ("duplicateActionOverride",))
        paths = selection["relativePaths"]
        _require(isinstance(paths, list) and paths, "An explicit selection must not be empty")
        for path in paths:
            relative_path(path)
        _require(len(paths) == len(set(paths)), "Duplicate selected path")
        if "duplicateActionOverride" in selection:
            _require(selection["duplicateActionOverride"] in POLICIES, "Unknown one-run policy")
    if value["command"] == "stop":
        _require(isinstance(value.get("runId"), str) and
                 re.fullmatch(r"[A-Za-z0-9._-]{1,128}", value["runId"]), "Stop needs the owned run ID")
    else:
        _require("runId" not in value, "runId is only supplied for stop")
    return value


def validate_receipt(value):
    _object(value, ("schemaVersion", "source", "effectiveSettingsSha256", "outputs"))
    _version(value["schemaVersion"], SCHEMA_VERSION)
    digest = re.compile(r"[a-f0-9]{64}\Z")
    _require(isinstance(value["effectiveSettingsSha256"], str) and
             digest.fullmatch(value["effectiveSettingsSha256"]), "Invalid settings digest")
    records = [value["source"]]
    _require(isinstance(value["outputs"], list) and value["outputs"], "Receipt needs verified outputs")
    records.extend(value["outputs"])
    for record in records:
        _object(record, ("relativePath", "sha256", "sizeBytes"))
        relative_path(record["relativePath"])
        _require(isinstance(record["sha256"], str) and digest.fullmatch(record["sha256"]), "Invalid file digest")
        _integer(record["sizeBytes"], 1)
    names = [record["relativePath"] for record in value["outputs"]]
    _require(len(names) == len(set(names)), "Duplicate receipt output")
    return value


def validate_event_stream(events, request_id):
    """Validate one completed JSONL exchange, including its terminal result."""
    _require(isinstance(events, list) and events, "Worker produced no protocol events")
    run_id = None
    for index, event in enumerate(events):
        _object(event, ("protocolVersion", "requestId", "runId", "sequence", "timestampUtc", "type", "data"))
        _version(event["protocolVersion"], PROTOCOL_VERSION)
        _require(event["requestId"] == request_id, "Unexpected request ID")
        _require(isinstance(event["runId"], str) and re.fullmatch(r"[A-Za-z0-9._-]{1,128}", event["runId"]), "Invalid run ID")
        if run_id is None:
            run_id = event["runId"]
        _require(event["runId"] == run_id, "Run ID changed within one exchange")
        _integer(event["sequence"], index + 1, index + 1)
        stamp = event["timestampUtc"]
        _require(isinstance(stamp, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", stamp), "Use a UTC timestamp")
        try:
            datetime.datetime.fromisoformat(stamp[:-1] + "+00:00")
        except ValueError as error:
            raise ContractError("Invalid event timestamp") from error
        kind, data = event["type"], event["data"]
        if kind == "item":
            _object(data, ("sourceRelativePath", "state"), ("detail",))
            relative_path(data["sourceRelativePath"])
            _require(data["state"] in ITEM_STATES, "Unknown item state")
            if "detail" in data:
                _string(data["detail"], empty=True)
        elif kind == "progress":
            _object(data, ("phase", "completed", "total"))
            _string(data["phase"])
            _integer(data["total"], 0)
            _integer(data["completed"], 0, data["total"])
        elif kind == "result":
            _object(data, ("status", "exitCode", "counts"), ("detail",))
            _require(data["status"] in EXIT_CODES and type(data["exitCode"]) is int and
                     data["exitCode"] == EXIT_CODES[data["status"]], "Result status/exit code disagree")
            _object(data["counts"], ("converted", "archived", "failed", "conflicts", "waiting", "skipped"))
            for count in data["counts"].values():
                _integer(count, 0)
            if "detail" in data:
                _string(data["detail"], empty=True)
            _require(index == len(events) - 1, "Result must be the final event")
        else:
            raise ContractError("Unknown worker event type")
    _require(events[-1]["type"] == "result", "Worker ended without a terminal result")
    return events[-1]["data"]["exitCode"]
