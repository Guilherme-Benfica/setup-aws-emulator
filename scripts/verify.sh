#!/usr/bin/env bash
# Confirms the AWS CLI reaches the emulator and not a real AWS account.
set -euo pipefail

# Variables set earlier in the job win over the emulator's credentials file.
for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE; do
  if [[ -n "${!name:-}" ]]; then
    echo "::warning::${name} is set in this job and takes priority over the emulator credentials. Calls still go to the local endpoint but may fail to authenticate. Remove ${name} from this job."
  fi
done

if ! command -v aws >/dev/null 2>&1; then
  echo "::notice::AWS CLI not found on this runner, skipping the STS check. The emulator itself is healthy."
  exit 0
fi

account="$(aws sts get-caller-identity --query Account --output text)"
account="${account//$'\r'/}" # aws.exe on Windows ends lines with CRLF

if [[ "${account}" != "000000000000" ]]; then
  echo "::error::Expected the emulator account 000000000000 but got ${account}. Check that nothing else in the job overrides the AWS variables."
  exit 1
fi

echo "account-id=${account}" >>"${GITHUB_OUTPUT}"
echo "AWS Emulator ready at ${AWS_ENDPOINT_URL} (account ${account})"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### AWS Emulator is running"
    echo ""
    echo "| Endpoint | Account | Region |"
    echo "| --- | --- | --- |"
    echo "| \`${AWS_ENDPOINT_URL}\` | \`${account}\` | \`${AWS_REGION}\` |"
  } >>"${GITHUB_STEP_SUMMARY}"
fi
