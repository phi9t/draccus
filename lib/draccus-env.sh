#!/usr/bin/env bash
# Resolve DRACCUS_BUNDLE when unset: parent of lib/ (repository / bundle root).
# Launchers and scripts source this file so the tree works when moved or cloned.
if [[ -z "${DRACCUS_BUNDLE:-}" ]]; then
  _draccus_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DRACCUS_BUNDLE="$(cd "${_draccus_lib}/.." && pwd)"
  unset _draccus_lib
fi
export DRACCUS_BUNDLE
