#!/usr/bin/env bash
# End-to-end test of awsemu on Linux. Run it from the repository root.
set -euo pipefail

AWSEMU_SOURCE="${PWD}" bash install.sh
export PATH="${HOME}/.local/bin:${PATH}"

# Real-looking credentials in the shell must not leak into emulator calls.
export AWS_ACCESS_KEY_ID=AKIAFAKEFAKEFAKEFAKE AWS_SECRET_ACCESS_KEY=fake AWS_PROFILE=real

awsemu up
out="$(awsemu up)"
grep -q "already running" <<<"${out}"

eval "$(awsemu env)"
test "$(aws sts get-caller-identity --query Account --output text)" = "000000000000"
aws s3 mb s3://awsemu-test
awsemu status

awsemu up --port 9400 >/dev/null
(
  eval "$(awsemu env --port 9400)"
  test "${AWS_ENDPOINT_URL}" = "https://127.0.0.1:9400"
  aws s3 ls >/dev/null
)
awsemu down --port 9400
awsemu down

if awsemu status; then
  echo "awsemu status should fail after awsemu down"
  exit 1
fi
echo "awsemu Linux test passed"
