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
