#!/usr/bin/env bash
# Installs AWS Emulator from the official Debian package on a Linux runner.
set -euo pipefail

if [[ "${RUNNER_OS:-Linux}" != "Linux" ]]; then
  echo "::error::setup-aws-emulator supports Linux runners only. On macOS and Windows, AWS Emulator runs through Docker."
  exit 1
fi

case "${RUNNER_ARCH:-$(uname -m)}" in
  X64 | x86_64) deb_arch="amd64" ;;
  ARM64 | aarch64) deb_arch="arm64" ;;
  *)
    echo "::error::Unsupported runner architecture: ${RUNNER_ARCH:-$(uname -m)}"
    exit 1
    ;;
esac

if command -v aws-emulator >/dev/null 2>&1; then
  echo "AWS Emulator is already installed: $(aws-emulator -v)"
  exit 0
fi

url="https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/latest/aws-emulator_${deb_arch}.deb"
tmp_dir="$(mktemp -d)"

echo "Downloading ${url}"
curl -fsSL --retry 3 -o "${tmp_dir}/aws-emulator.deb" "${url}"
sudo apt-get install -y "${tmp_dir}/aws-emulator.deb"

aws-emulator -v
