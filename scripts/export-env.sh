#!/usr/bin/env bash
# Exports the variables that point the AWS CLI, SDKs and Terraform at the emulator
# for every later step of the job.
set -euo pipefail

port="${EMULATOR_PORT:-9297}"
region="${EMULATOR_REGION:-us-east-1}"
emulator_dir="${HOME}/.aws/emulator/${port}"

{
  echo "AWS_ENDPOINT_URL=https://127.0.0.1:${port}"
  echo "AWS_SHARED_CREDENTIALS_FILE=${emulator_dir}/emulator_credentials"
  echo "AWS_CONFIG_FILE=${emulator_dir}/config"
  echo "AWS_CA_BUNDLE=${emulator_dir}/ca.pem"
  echo "AWS_EC2_METADATA_DISABLED=true"
  echo "AWS_DISABLE_HOST_PREFIX_INJECTION=true"
  echo "AWS_REGION=${region}"
  echo "AWS_DEFAULT_REGION=${region}"
} >>"${GITHUB_ENV}"

# Variables set earlier in the job win over the emulator's credentials file.
for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE; do
  if [[ -n "${!name:-}" ]]; then
    echo "::warning::${name} is set in this job and takes priority over the emulator credentials. Calls still go to the local endpoint but may fail to authenticate. Remove ${name} from this job."
  fi
done
