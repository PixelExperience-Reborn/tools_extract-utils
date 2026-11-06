#!/usr/bin/env python3
"""Guard the Android17 extractor integration against missing host dependencies.

Intentionally source/metadata-only. Never execute OEM inputs, old prebuilts
or Lineage-specific helper scripts. The old Git tree URL is immutable.
"""
import ast
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

OLD_TOOLS_TREE = "d075fe2289fab010490e30f5f1454f88a74b793d"
REQUIRED_MISSING = {
    "linux-x86/bin/patchelf-0_18",
    "linux-x86/bin/stripzip",
    "common/apktool/apktool.jar",
}
REQUIRED_EXISTING = {
    "linux-x86/bin/ota_extractor",
    "linux-x86/bin/patchelf-0_17_2",
}


def require(ok, msg):
    if not ok:
        raise RuntimeError(msg)


def main():
    require(len(sys.argv) == 4,
            "usage: check_host_gaps.py PYTHON_SOURCE_ROOT AOSP17_MANIFEST_ROOT OLD_GIT_TREE_JSON")
    source, manifest, old_json = [Path(p).resolve() for p in sys.argv[1:]]
    require((source / "extract_utils/tools.py").is_file(), "missing Python helper")
    require((manifest / "aosp17_reference.xml").is_file(), "missing A17 manifest")
    data = json.loads(old_json.read_text(encoding="utf-8"))
    require(data.get("sha") == OLD_TOOLS_TREE and data.get("truncated") is False,
            "old binary tools tree is wrong/incomplete")
    paths = {x.get("path") for x in data.get("tree", []) if x.get("type") == "blob"}
    require(REQUIRED_MISSING.isdisjoint(paths),
            "a previously absent binary has appeared; dependency audit must be redone")
    require(REQUIRED_EXISTING.issubset(paths),
            "old extractor archive provenance differs from audited snapshot")
    print("PASS: three required modern host-tool files absent from audited 2023 PE archive")
    print("OPEN: obtain pinned, licensed, supported patchelf-0_18, stripzip, apktool.jar")

    raw = (source / "extract_utils/tools.py").read_text(encoding="utf-8")
    module = ast.parse(raw)
    # Make sure the declared default cannot silently regress to 2019-era
    # patchelf and never infer runtime tool availability from its path alone.
    defaults = [
        node for node in module.body
        if isinstance(node, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == "DEFAULT_PATCHELF_VERSION"
                for t in node.targets)
    ]
    require(len(defaults) == 1 and
            isinstance(defaults[0].value, ast.Constant) and
            defaults[0].value.value == "0_18",
            "modern Python helper changed its selected patchelf version")
    for needle in ("stripzip_path", "apktool_path", "lineage_scripts_dir",
                   "carriersettings_extractor_path", "fbpacktool_path"):
        require(needle in raw, f"unreviewed change to mandatory/optional host helper {needle}")

    module_py = ast.parse(
        (source / "extract_utils/module.py").read_text(encoding="utf-8")
    )
    cls = next(n for n in module_py.body
               if isinstance(n, ast.ClassDef) and n.name == "ExtractUtilsModule")
    init = next(n for n in cls.body
                if isinstance(n, ast.FunctionDef) and n.name == "__init__")
    names = [a.arg for a in init.args.args]
    defaults = dict(zip(names[-len(init.args.defaults):], init.args.defaults))
    require(isinstance(defaults.get("check_elf"), ast.Constant)
            and defaults["check_elf"].value is True,
            "modern ELF check is not default-enabled")
    print("PASS: modern default check_elf=True; historic PE skip-ELF not imported")

    policy = (source / "extract_utils/prohibited_files.py").read_text(
        encoding="utf-8"
    )
    require("SenseTime" in policy and "Megvii" in policy,
            "modern restricted-license blob policy unexpectedly removed")

    base = ET.parse(manifest / "aosp17_reference.xml").getroot()
    owners = {
        p.get("path") or p.get("name"): p.get("name")
        for p in base.findall("project")
    }
    require("tools/extract-utils" not in owners and "lineage/scripts" not in owners
            and "prebuilts/extract-tools" not in owners,
            "helper is prematurely imported into Android17 ROM source graph")
    require(owners.get("prebuilts/jdk/jdk21") ==
            "platform/prebuilts/jdk/jdk21",
            "official Java21 host dependency owner missing")
    print("PASS: Android17 keeps extractor and Lineage-specific scripts out of ROM")
    print("NOT TESTED: host executable ABI, OTA/super extraction, vendor blob fixups or mondrian")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, ValueError, RuntimeError, ET.ParseError) as err:
        print(f"FAIL: {err}", file=sys.stderr)
        sys.exit(1)
