#!/usr/bin/env bash
# Static checks for the Omarchy plugin contract (the same rules as
# `omarchy plugin validate`), manifest/settings consistency, and QML syntax.
# qmllint cannot resolve Omarchy's runtime-only qs.* modules offline, so only
# genuine syntax errors fail the build.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "check-plugin: $*" >&2
  exit 1
}

manifest=manifest.json
jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"
jq -e '.schemaVersion == 1' "$manifest" >/dev/null || fail "schemaVersion must be the number 1"
for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$manifest" >/dev/null || fail "manifest is missing '$field'"
done

id=$(jq -r .id "$manifest")
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* && $id != omarchy.* ]] || fail "invalid plugin id '$id'"

while IFS= read -r entry; do
  [[ $entry != /* && $entry != *..* ]] || fail "entry point must be a safe relative path: $entry"
  [[ -f $entry ]] || fail "entry point not found: $entry"
done < <(jq -r '.entryPoints[]' "$manifest")

for pair in bar-widget:barWidget service:service; do
  kind=${pair%%:*} key=${pair##*:}
  if jq -e --arg k "$kind" '.kinds | index($k) != null' "$manifest" >/dev/null; then
    jq -e --arg e "$key" '.entryPoints | has($e)' "$manifest" >/dev/null || fail "kind '$kind' needs entryPoints.$key"
  fi
done

link=$(find . \( -name .git -o -name .venv -o -name node_modules \) -prune -o -type l -print -quit)
[[ -z $link ]] || fail "symlinks are not allowed in a plugin: $link"

jq -e '(.barWidget.defaults | keys | sort) == ([.barWidget.schema[].key] | sort)' "$manifest" >/dev/null \
  || fail "barWidget.defaults and barWidget.schema list different settings"
jq -e '.barWidget as $w | all($w.schema[]; .defaultValue == $w.defaults[.key])' "$manifest" >/dev/null \
  || fail "a schema defaultValue disagrees with barWidget.defaults"
jq -e 'all(.barWidget.schema[] | select(.type == "enum"); .defaultValue as $d | .options | index($d) != null)' "$manifest" >/dev/null \
  || fail "an enum default is not one of its options"

# The widget must read every setting the manifest offers, with the same default.
while IFS=$'\t' read -r key value; do
  grep -q "setting(\"$key\", $value)" BarWidget.qml || fail "BarWidget does not read setting '$key' with default $value"
done < <(jq -r '.barWidget.defaults | to_entries[] | [.key, (.value | tojson)] | @tsv' "$manifest")

# The redirect URI documented to users must be the one the helper listens on.
redirect=$(python3 -I -c 'import sys; sys.path.insert(0, "backend"); from tunemarchy import spotify; print(spotify.REDIRECT_URI)')
jq -e --arg r "$redirect" '.barWidget.schema[] | select(.key == "clientId") | .description | contains($r)' "$manifest" >/dev/null \
  || fail "clientId help text does not mention the redirect URI $redirect"
grep -qF "$redirect" README.md || fail "README does not mention the redirect URI $redirect"

version=$(jq -r .version "$manifest")
grep -q "^__version__ = \"$version\"" backend/tunemarchy/__init__.py || fail "backend version differs from manifest $version"
grep -q "^version = \"$version\"" pyproject.toml || fail "pyproject version differs from manifest $version"
grep -q "moduleName: \"$id\"" BarWidget.qml || fail "BarWidget moduleName must be $id"
grep -q "pluginId: \"$id\"" BarWidget.qml || fail "BarWidget pluginId must be $id"

# qmllint must run and report on every file. Unresolved qs.* modules only
# exist inside the running shell, so their warnings are expected; a syntax
# error (exit 255, "syntax" diagnostics) or a tool that never ran fails.
qmllint=${QMLLINT:-$(command -v qmllint6 || command -v qmllint || echo /usr/lib/qt6/bin/qmllint)}
[[ -x $qmllint ]] || fail "qmllint not found (install qt6-declarative or set QMLLINT)"
report=$(mktemp)
trap 'rm -f "$report"' EXIT
qml_files=(./*.qml)
lint_status=0
"$qmllint" --json "$report" "${qml_files[@]}" >/dev/null 2>&1 || lint_status=$?
jq -e --argjson n "${#qml_files[@]}" '(.files | length) == $n' "$report" >/dev/null 2>&1 \
  || fail "qmllint did not report on all ${#qml_files[@]} QML files (exit $lint_status)"
syntax=$(jq -r '.files[] | .filename as $f | .warnings[] | select(.id == "syntax")
  | "\($f):\(.line):\(.column): \(.message)"' "$report")
if [[ -n $syntax ]]; then
  echo "$syntax" >&2
  fail "QML syntax errors"
fi
(( lint_status == 0 )) || fail "qmllint exited with status $lint_status"

python3 -I backend/tunemarchyctl --version >/dev/null || fail "backend does not start"
echo "check-plugin: $id $version ok"
