# Android 17 source migration audit — tools/extract-utils (matrix row 161)

**Scope**: Modernise the archived PixelExperience extraction utility source **in a separate branch**, preserve historical Git ancestry, and review the interface needed for a future independent PE-Reborn `mondrian` device. This is NOT a completed blob extraction, ROM build or device tree.

## Why the legacy `seventeen` branch is not Android 17

- The historical PE `seventeen` and `fourteen` branches point to **`74d64169def22130dde0103844260cd4d7498085`** (2023-11-02), root tree **`fbd293a6eb787ad9ffbd37411e17d12e1fbb096d`**.
- It contains `extract_utils.sh` (76,575 B), `sdat2img.py`, `sort-blobs-list.py` and several Bash extraction/makefile-generation templates. It is the historical Android 14-era vendor tool workflow, **not** a modern A17 Python package.
- The final PE-only commit *disabled ELF checks by default* unless `TARGET_ENABLE_CHECKELF=true`. That legacy behavior must **not** be silently preserved when moving to modern code.
- Its `extract_utils.sh` directly expects `prebuilts/extract-tools/${HOST}-x86/bin/{simg2img,lpunpack,ota_extractor,SigScan,patchelf-*}`, old smali JARs and VDEX tools. The 2019–2023 binaries were audited separately in matrix row 158 and are not accepted into the active A17 build.
- Do NOT attempt to execute old binaries, run `extract_utils.sh` on an Android17 tree, or claim generic PE shell features are device-ready.

## Reviewed modern reference and preservation of ancestry

The review uses the immutable **LineageOS `android_tools_extract-utils` `lineage-24.0` commit**:

- Source commit **`78ba5d58c4b06712e18bb387a2a72eac8fbc8d70`** (2026-10-17).
- Exact upstream root tree **`00c1a5a4a08c8e4854992879c181c47f4c71dc19`** with **47 Git blobs** across the modern Python package, templates, source manifests and license text.
- Main Python package `extract_utils/`, entrypoint `extract.py`, `convert_dump.py`, `sdat2img.py`, `sort-blobs-list.py`, Python templates, `LICENSES/` and `REUSE.toml`. There is a source symlink `templates/multi-device/common -> ../single-device`.
- Historic PE `seventeen` sources remain **preserved in Git history**. The isolated integration branch contains a genuine **two-parent Git merge** at [`3cdbdc12946667fc1a9b1ebff79125ed23957fb7`](https://github.com/PixelExperience-Reborn/tools_extract-utils/commit/3cdbdc12946667fc1a9b1ebff79125ed23957fb7): first parent the original PE SHA; second parent the pinned modern upstream SHA. The integrated root tree is **`90c1cb94816aa224cb4bc8146b1913b7bdcd6c5b`**, exactly the upstream functional sources **minus two upstream-only Gerrit GitHub Actions files** (`.github/workflows/build/action.yml`, `.github/workflows/gerrit.yml`). Those two exclusions are required to avoid importing unrelated CI integrations; no Python code, license, template or source file was edited. Source parity is verified by an exact two-file Git diff.
- The upstream work is an **extraction host utility**, not a decision to base the new PE-Reborn ROM/frameworks/device trees on LineageOS. Keep its original copyright and license headers intact. Review any later independent PE-specific modifications separately.
- Pinning this snapshot does not imply it stays current forever; future upstream updates require separate review.

## Mondrian technical references — do not change device trees

Read-only existing LF52406 device/common `lineage-24.0` files:

- `mondrian/extract-files.py`: invokes `ExtractUtils.device_with_common(module, 'sm8450-common', module.vendor)`; uses `blob_fixup().regex_replace(...)`, `replace_needed`, `add_needed`, and `clear_symbol_version`.
- `sm8450-common/extract-files.py`: uses `ExtractUtils.device(module)`; WFD JAR fixup calls `blob_fixup().apktool_patch(...)` and other vendor `patchelf` operations.
- Both use `#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3`. This establishes the **API compatibility target** and modern source path layout. It does NOT prove boot/ABI compatibility or authorize copying existing LineageOS device configs into PE.
- Modern `ExtractUtilsModule(..., check_elf=True)` defaults to ELF checking. The old PE opt-out behavior is not automatically migrated; future vendor-specific ELF exceptions should be explicitly documented, minimised and verified against A17 Soong/VINTF/ABI.

## Crucial unresolved host dependencies (NO automatic manifest import)

The modern Python `extract_utils/tools.py` contains **hardcoded host paths**:

- `prebuilts/extract-tools/linux-x86/bin/patchelf-0_18` (new default), `ota_extractor` and `stripzip`.
- `prebuilts/extract-tools/common/apktool/apktool.jar`.
- `prebuilts/build-tools/linux-x86/bin/brotli`, `prebuilts/jdk/jdk21/linux-x86/bin/java`, LLVM utilities, and `system/tools/mkbootimg/unpack_bootimg.py`.
- **Lineage-specific** `lineage/scripts/carriersettings-extractor/carriersettings_extractor.py` and `lineage/scripts/fbpacktool/fbpacktool.py`.

The archived `prebuilts_extract-tools` at row 158 contains **neither `patchelf-0_18` nor `stripzip` nor `apktool.jar`**. Also, `lineage/scripts` is not present in the deliberately isolated PE-Reborn Android17 baseline. Importing the Python source into the active manifest **without solving these dependencies and examining reachable features** would give broken extraction tooling.

**Do not** reactivate the old binary prebuilt repos or blindly clone `lineage/scripts`. Prefer choosing verified host tools from trusted upstream source with pinned revisions, correct licenses, ELF/host ABI and input integrity testing when new PE device source design begins. Avoid assuming `prebuilts/build-tools` is a drop-in for missing `prebuilts/extract-tools` paths.

## CI/source-only acceptance

1. The exact upstream SHA/tree is independently verified, with original PE head first parent; import is a **real two-parent merge**, not a branch rename or shallow content copy. Historical SHA `74d64169`, modern SHA `78ba5d58`, imported merge SHA `3cdbdc1` and sanitized tree SHA `90c1cb9` are all verified on GitHub.
2. Candidate matches the pinned upstream tree **before excluding the two unrelated upstream CI files**; the final sanitized source tree differs from the upstream by exactly those two deletions, and all modern extraction code/templates/licenses match. Old Bash extractor/template files must not remain active.
3. Parse every Python file and statically verify the API `ExtractUtils.device_with_common`, `ExtractUtils.device`, `ExtractUtilsModule`, and `blob_fixup` methods used by read-only mondrian/common.
4. Assert ELF checking defaults to enabled and record the host tool/Lineage script path gap; test metadata must be explicit.
5. Keep AOSP17 `default.xml` unchanged, with **no** `tools/extract-utils` owner, no PE device tree, no old `prebuilts/extract-tools`, no old `prebuilts/tools-custom`, and no duplicate projects. AOSP17 manifest validator now explicitly rejects premature extractor import and includes a negative regression test. All 25 reviewed source profiles, **12 regression tests** and the official `repo manifest` graph (1069 selected projects) passed in [CI #42249252301](https://github.com/PixelExperience-Reborn/tools_extract-utils/actions/runs/42249252301).
6. The isolated integration branch was pushed after initial source preflight PASS, and its exact two-parent ancestry and tree were confirmed via GitHub API. Subsequent workflow runs are idempotent and refuse unknown commits. The original `seventeen` SHA is unchanged; no automatic PR merge.

## Remaining work, not falsely marked complete

- Rework host paths and support scripts without relying on `lineage/scripts`; choose and verify exact external dependencies.
- Decide how the new PE-Reborn **mondrian-only** device/common/vendor trees call extraction and generate Android17-appropriate Soong modules and fixups; add source regression fixtures and clean vendor OTA/dump test inputs.
- Check proprietary file hashes, sparse/super/EROFS and payload extraction, patchelf ABI and JAR transforms, VINTF/SELinux; rerun on legal known-good test firmware.
- Full AOSP17 `repo sync`, Soong/Make, kernel 5.10/modules, actual recovery/boot hardware tests and release signing are open. No server/device ROM build was run.

## References

- Historical PixelExperience: https://github.com/PixelExperience-Reborn/tools_extract-utils/tree/seventeen
- Upstream pinned modern Python source: https://github.com/LineageOS/android_tools_extract-utils/tree/78ba5d58c4b06712e18bb387a2a72eac8fbc8d70
- Modern host dependency locations: https://github.com/LineageOS/android_tools_extract-utils/blob/78ba5d58c4b06712e18bb387a2a72eac8fbc8d70/extract_utils/tools.py
- Existing device references (read-only): https://github.com/LF52406/mondrian_android_device_xiaomi_mondrian/blob/lineage-24.0/extract-files.py and https://github.com/LF52406/mondrian_android_device_xiaomi_sm8450-common/blob/lineage-24.0/extract-files.py
- Reviewed AOSP17 manifest: https://github.com/PixelExperience-Reborn/manifest/tree/port/a17-aosp17-manifest-20261102

**Status (verified 2026-11-06):** modern Python source imported into an **isolated Draft PR**, with 36 Python source syntax checks and source/manifest CI PASS. Three required host binaries, Lineage-specific helper path, OTA/vendor extraction and device/Soong integration remain OPEN. Not an accepted Android17 ROM/device extraction workflow.
