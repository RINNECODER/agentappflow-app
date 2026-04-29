#!/bin/sh
set -eu

resolve_source_framework() {
  if [ -n "${AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH:-}" ] && [ -d "${AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH}" ]; then
    printf '%s\n' "${AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH}"
    return 0
  fi

  if [ -n "${DEVELOPER_DIR:-}" ] && [ -d "${DEVELOPER_DIR}/Library/Frameworks/Python3.framework" ]; then
    printf '%s\n' "${DEVELOPER_DIR}/Library/Frameworks/Python3.framework"
    return 0
  fi

  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [ -n "${developer_dir}" ] && [ -d "${developer_dir}/Library/Frameworks/Python3.framework" ]; then
    printf '%s\n' "${developer_dir}/Library/Frameworks/Python3.framework"
    return 0
  fi

  return 1
}

source_framework="$(resolve_source_framework || true)"
if [ -z "${source_framework}" ] || [ ! -d "${source_framework}" ]; then
  echo "error: Unable to locate Python3.framework for bundling." >&2
  echo "error: Set AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH to an embedded CPython framework path if needed." >&2
  exit 1
fi

destination_root="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
destination_framework="${destination_root}/Python3.framework"

mkdir -p "${destination_root}"
rm -rf "${destination_framework}"
ditto "${source_framework}" "${destination_framework}"
