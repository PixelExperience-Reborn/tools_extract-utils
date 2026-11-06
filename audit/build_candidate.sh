#!/usr/bin/env bash
# Prepare an isolated, two-parent Git history integration candidate.
# SOURCE-ONLY: do not build or execute extracted OEM binaries.
set -euo pipefail

TARGET=${1:?usage: build_candidate.sh <empty-working-directory>}
PE_REPO=https://github.com/PixelExperience-Reborn/tools_extract-utils.git
UPSTREAM=https://github.com/LineageOS/android_tools_extract-utils.git
PE_BRANCH=integrate/a17-python-extract-utils-20261106
PE_COMMIT=74d64169def22130dde0103844260cd4d7498085
UPSTREAM_COMMIT=78ba5d58c4b06712e18bb387a2a72eac8fbc8d70
UPSTREAM_TREE=00c1a5a4a08c8e4854992879c181c47f4c71dc19

if [[ -e "$TARGET" ]]; then
    echo "FAIL: candidate checkout path must not already exist" >&2
    exit 1
fi

git clone -q --filter=blob:none --branch "$PE_BRANCH" "$PE_REPO" "$TARGET"
head=$(git -C "$TARGET" rev-parse HEAD)
if [[ "$head" != "$PE_COMMIT" ]]; then
    echo "FAIL: integration branch moved ($head); do not overwrite existing work" >&2
    exit 1
fi

# Fetch the pinned *commit*, never a floating upstream branch.
git -C "$TARGET" fetch --quiet --no-tags --depth=1 "$UPSTREAM" "$UPSTREAM_COMMIT"
source_commit=$(git -C "$TARGET" rev-parse 'FETCH_HEAD^{commit}')
source_tree=$(git -C "$TARGET" rev-parse 'FETCH_HEAD^{tree}')
if [[ "$source_commit" != "$UPSTREAM_COMMIT" || "$source_tree" != "$UPSTREAM_TREE" ]]; then
    echo "FAIL: upstream commit/tree mismatch" >&2
    exit 1
fi

git -C "$TARGET" config user.name "PixelExperience-Reborn source import"
git -C "$TARGET" config user.email "noreply@users.noreply.github.com"

# Record both parents without guessing conflicting Bash/Python behavior.
# Do NOT leave old extract_utils.sh or old shell templates in the new tree.
git -C "$TARGET" merge -q --allow-unrelated-histories --no-ff \
    --no-commit -s ours "$UPSTREAM_COMMIT"

git -C "$TARGET" ls-files -z | xargs -0 -r git -C "$TARGET" rm -q --
git -C "$TARGET" checkout -q "$UPSTREAM_COMMIT" -- .
tree=$(git -C "$TARGET" write-tree)
if [[ "$tree" != "$UPSTREAM_TREE" ]]; then
    echo "FAIL: staged source tree differs from pinned upstream ($tree)" >&2
    exit 1
fi
if [[ -e "$TARGET/extract_utils.sh" ]] || [[ -e "$TARGET/templates/single-device/extract-files.sh" ]]; then
    echo "FAIL: old PE shell extraction scripts survived" >&2
    exit 1
fi

# Statically verify Python files can be parsed by the host interpreter.
# Avoid writing bytecode or importing modules that may execute external tools.
python3 - "$TARGET" <<'PY'
import ast
from pathlib import Path
import sys
source = Path(sys.argv[1])
files = sorted(source.rglob('*.py'))
assert len(files) >= 30, f"unexpected modern Python file count: {len(files)}"
for file in files:
    ast.parse(file.read_text(encoding='utf-8'), filename=str(file))
print(f"PASS: syntax of {len(files)} modern Python source files")
PY

# Assert public APIs used by the *read-only* LF52406 mondrian and sm8450
# reference scripts, without claiming the A17 device/vendor ABI is supported.
python3 - "$TARGET" <<'PY'
import ast
from pathlib import Path
import sys
root = Path(sys.argv[1])
checks = {
    "extract_utils/main.py": ("ExtractUtils", {"device", "device_with_common", "device_with_commons"}),
    "extract_utils/module.py": ("ExtractUtilsModule", set()),
    "extract_utils/fixups_blob.py": ("blob_fixup", {"apktool_patch", "replace_needed", "add_needed", "regex_replace", "clear_symbol_version"}),
}
for filename, (class_name, methods) in checks.items():
    module = ast.parse((root / filename).read_text(encoding="utf-8"))
    matches = [n for n in module.body if isinstance(n, ast.ClassDef) and n.name == class_name]
    assert len(matches) == 1, f"{filename} missing {class_name}"
    found = {n.name for n in matches[0].body if isinstance(n, ast.FunctionDef)}
    assert methods.issubset(found), f"{filename} missing {sorted(methods - found)}"
module = ast.parse((root / "extract_utils/module.py").read_text(encoding="utf-8"))
cls = next(n for n in module.body if isinstance(n, ast.ClassDef) and n.name == "ExtractUtilsModule")
init = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == "__init__")
defaults = init.args.defaults
assert any(isinstance(n, ast.Constant) and n.value is True for n in defaults), (
    "default ELF check must be audited, not silently switched off"
)
print("PASS: modern Python extractor exposes the APIs required by existing read-only mondrian references")
PY

git -C "$TARGET" -c commit.gpgsign=false commit -qm \
    "tools: import reviewed modern Python extraction source for Android 17

Preserve old PixelExperience source history and upstream LineageOS 24.0
history as two Git parents. The content is an EXACT upstream source tree:
$UPSTREAM_TREE from $UPSTREAM_COMMIT.

SOURCE ONLY. No PE mondrian device tree, proprietary prebuilts, product
module, or default Android17 manifest import. Runtime vendor extraction
and external host dependencies are not yet accepted."

parents=$(git -C "$TARGET" rev-list --parents -n 1 HEAD)
read -r commit parent1 parent2 extra <<< "$parents"
if [[ -n "${extra:-}" || "$parent1" != "$PE_COMMIT" || "$parent2" != "$UPSTREAM_COMMIT" ]]; then
    echo "FAIL: resulting commit does not have exact PE and modern upstream parents" >&2
    exit 1
fi
if [[ "$(git -C "$TARGET" rev-parse 'HEAD^{tree}')" != "$UPSTREAM_TREE" ]]; then
    echo "FAIL: committed tree is not the exact reviewed modern source" >&2
    exit 1
fi

printf 'PASS: exact upstream source tree %s\n' "$UPSTREAM_TREE"
printf 'PASS: PE legacy parent %s\n' "$parent1"
printf 'PASS: upstream modern parent %s\n' "$parent2"
printf 'PASS: local candidate merge %s (not pushed)\n' "$commit"
