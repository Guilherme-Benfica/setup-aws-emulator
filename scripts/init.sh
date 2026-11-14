#!/usr/bin/env bash
# Runs init steps after the emulator is up, in order: *.sh files with bash, and
# directories with *.tf files with terraform init + apply. Usage: init.sh PATH...
# On failure, prints the emulator log (EMULATOR_LOG) and exits 1.
set -euo pipefail

fail() {
  echo "::error::$1"
  if [[ -n "${EMULATOR_LOG:-}" && -f "${EMULATOR_LOG}" ]]; then
    echo "AWS Emulator log:"
    cat "${EMULATOR_LOG}"
  fi
  exit 1
}

for path in "$@"; do
  [[ -z "${path// /}" ]] && continue
  if [[ -f "${path}" && "${path}" == *.sh ]]; then
    echo "init: bash ${path}"
    bash "${path}" || fail "init script ${path} failed"
  elif [[ -d "${path}" ]] && compgen -G "${path}/*.tf" >/dev/null; then
    command -v terraform >/dev/null 2>&1 ||
      fail "init: ${path} is a Terraform directory. Install Terraform first, for example with hashicorp/setup-terraform."
    echo "init: terraform apply in ${path}"
    terraform -chdir="${path}" init -input=false || fail "terraform init failed in ${path}"
    terraform -chdir="${path}" apply -input=false -auto-approve || fail "terraform apply failed in ${path}"
  else
    fail "init accepts .sh files or Terraform directories, got: ${path}"
  fi
done
