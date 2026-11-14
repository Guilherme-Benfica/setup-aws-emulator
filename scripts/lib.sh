#!/usr/bin/env bash
# Helpers shared by the scripts. On Windows runners the scripts run inside WSL 1,
# so files the emulator writes must land in the Windows profile, and paths handed
# back to the runner must be Windows paths.

in_wsl() {
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

# Home folder the emulator writes ~/.aws/emulator/<port>/ into.
emulator_home() {
  if in_wsl; then
    # USERPROFILE arrives through WSLENV, already translated to /mnt/c/...
    printf '%s\n' "${USERPROFILE:?USERPROFILE must be passed through WSLENV}"
  else
    printf '%s\n' "${HOME}"
  fi
}

# A path as the runner's own shell, SDKs and tools must see it.
runner_path() {
  if in_wsl; then
    wslpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

# Folder for files this tool writes (log, pid, certificates, env). Created if missing.
# AWSEMU_HOME wins; in GitHub Actions it is under $RUNNER_TEMP, elsewhere ~/.awsemu.
work_dir() {
  local base
  if [[ -n "${AWSEMU_HOME:-}" ]]; then
    base="${AWSEMU_HOME}"
  elif [[ -n "${RUNNER_TEMP:-}" ]]; then
    base="$(unix_path "${RUNNER_TEMP}")/aws-emulator"
  else
    base="${HOME}/.awsemu"
  fi
  mkdir -p "${base}/$1"
  printf '%s\n' "${base}/$1"
}

# Sets a step output when running in GitHub Actions; does nothing elsewhere.
set_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >>"${GITHUB_OUTPUT}"
  fi
}

# In Git Bash on Windows, converts between Windows paths and the shell's own paths, so
# file commands get a path the shell understands and Windows programs get C:\... paths.
# Elsewhere, returns the path unchanged.
unix_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
}
windows_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}
