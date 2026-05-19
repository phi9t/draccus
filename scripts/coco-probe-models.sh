#!/usr/bin/env bash
# Smoke-test TraeCLI (coco) model names with anti-fallback checks via stream-json.
# Requires: coco on PATH, python3, network/API access for each provider.
#
# Usage:
#   ./scripts/coco-probe-models.sh [WORKDIR]           # probe built-in default list
#   ./scripts/coco-probe-models.sh . "ModelA" "ModelB" # probe explicit names
#
# Writes TSV to .trae/artifacts/coco-probe-latest.tsv (and copies to dated file).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKDIR="${1:-$REPO_ROOT}"
shift || true

DEFAULT_MODELS=(
  "GLM-5.1"
  "GLM-5V-Turbo"
  "GLM-5"
  "Gemini-3.1-Pro-Preview"
  "Gemini-3-Flash-Preview"
  "Kimi-K2.6"
  "Kimi-K2.5"
  "GPT-5.5"
  "GPT-5.4"
  "GPT-5.2"
)

if [[ $# -gt 0 ]]; then
  MODELS=("$@")
else
  MODELS=("${DEFAULT_MODELS[@]}")
fi

PROBE_PROMPT='Reply with exactly: PING'
QUERY_TIMEOUT="${COCO_PROBE_QUERY_TIMEOUT:-3m}"
ARTIFACT_DIR="${REPO_ROOT}/.trae/artifacts"
mkdir -p "${ARTIFACT_DIR}"

TSV_LATEST="${ARTIFACT_DIR}/coco-probe-latest.tsv"
TSV_DATED="${ARTIFACT_DIR}/coco-probe-$(date -u +%Y%m%dT%H%M%SZ).tsv"

{
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'requested_name' 'init_model' 'name_match' 'result_subtype' 'seconds' 'exit_code' 'stderr_tail'
  for m in "${MODELS[@]}"; do
    printf '%s\n' "=== probing: ${m} ===" >&2
    errf="$(mktemp)"
    start="$(date +%s)"
    set +e
    stream_out="$(cd "${WORKDIR}" && coco -c "model.name=${m}" -p "${PROBE_PROMPT}" \
      --output-format stream-json --query-timeout "${QUERY_TIMEOUT}" 2>"${errf}")"
    ec=$?
    set -e
    end="$(date +%s)"
    elapsed=$((end - start))

    parse_json="$(printf '%s\n' "${stream_out}" | python3 -c '
import json, sys
init_model = None
subtype = None
error_txt = None
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except json.JSONDecodeError:
        continue
    if o.get("type") == "system" and o.get("subtype") == "init":
        init_model = o.get("model")
    if o.get("type") == "result":
        subtype = o.get("subtype")
        error_txt = o.get("error")
out = {"init_model": init_model, "subtype": subtype, "error": error_txt}
print(json.dumps(out))
')"
    init_model="$(printf '%s' "${parse_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("init_model") or "")')"
    result_sub="$(printf '%s' "${parse_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("subtype") or "")')"
    err_body="$(printf '%s' "${parse_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error") or "")')"

    match="no"
    if [[ "${init_model}" == "${m}" ]]; then
      match="yes"
    fi

    stderr_tail="$(tail -c 400 "${errf}" | tr '\t' ' ' | tr '\n' '; ')"
    rm -f "${errf}"

    status_line="${result_sub}"
    if [[ -n "${err_body}" ]]; then
      status_line="${status_line} ${err_body}"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${m}" "${init_model}" "${match}" "${status_line}" "${elapsed}" "${ec}" "${stderr_tail}"
  done
} | tee "${TSV_LATEST}" | tee "${TSV_DATED}"

printf '\nWrote %s and %s\n' "${TSV_LATEST}" "${TSV_DATED}" >&2
