#!/usr/bin/env bash
# Installs AWS Emulator from the official Debian package. Runs on a Linux runner,
# or inside WSL on a Windows runner.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "$(uname -m)" in
  x86_64) deb_arch="amd64" ;;
  aarch64) deb_arch="arm64" ;;
  *)
    echo "::error::Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

sudo=()
if [[ "${EUID}" -ne 0 ]]; then
  sudo=(sudo)
fi

version="${EMULATOR_VERSION:-latest}"
base_url="https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS"

if [[ "${version}" == "latest" ]]; then
  url="${base_url}/latest/aws-emulator_${deb_arch}.deb"
elif [[ "${version}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(\.[0-9]+)?$ ]]; then
  # versions.json lists 1.0.351.1, but the package file is named after 1.0.351.
  url="${base_url}/aws-emulator_${BASH_REMATCH[1]}-1_${deb_arch}.deb"
else
  echo "::error::version must be \"latest\" or a version such as 1.0.351 (see ${base_url}/versions.json), got: ${version}"
  exit 1
fi

if command -v aws-emulator >/dev/null 2>&1; then
  installed="$(aws-emulator -v | sed -n 's/^Version: //p')"
  echo "AWS Emulator ${installed} is already installed"
  set_output version "${installed}"
  exit 0
fi
tmp_dir="$(mktemp -d)"

echo "Downloading ${url}"
if ! curl -fsSL --retry 3 -o "${tmp_dir}/aws-emulator.deb" "${url}"; then
  echo "::error::Could not download ${url}. Check that the version exists in ${base_url}/versions.json"
  exit 1
fi
"${sudo[@]}" apt-get install -y "${tmp_dir}/aws-emulator.deb"

installed="$(aws-emulator -v | sed -n 's/^Version: //p')"
echo "Installed AWS Emulator ${installed}"
set_output version "${installed}"
