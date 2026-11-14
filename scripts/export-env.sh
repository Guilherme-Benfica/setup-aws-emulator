#!/usr/bin/env bash
# Exports the variables that point the AWS CLI, SDKs and Terraform at the emulator
# for every later step of the job.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${EMULATOR_PORT:-9297}"
region="${EMULATOR_REGION:-us-east-1}"
emulator_dir="$(emulator_home)/.aws/emulator/${port}"

{
  echo "AWS_ENDPOINT_URL=https://127.0.0.1:${port}"
  echo "AWS_SHARED_CREDENTIALS_FILE=$(runner_path "${emulator_dir}/emulator_credentials")"
  echo "AWS_CONFIG_FILE=$(runner_path "${emulator_dir}/config")"
  echo "AWS_CA_BUNDLE=$(runner_path "${emulator_dir}/ca.pem")"
  echo "AWS_EC2_METADATA_DISABLED=true"
  echo "AWS_DISABLE_HOST_PREFIX_INJECTION=true"
  echo "AWS_REGION=${region}"
  echo "AWS_DEFAULT_REGION=${region}"
} >>"${GITHUB_ENV}"

