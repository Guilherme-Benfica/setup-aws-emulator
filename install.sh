#!/usr/bin/env bash
# Installs the awsemu command for the current user, from the v1 release:
#   curl -fsSL https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.sh | bash
# AWSEMU_REF picks another tag; AWSEMU_SOURCE installs from a local checkout.
set -euo pipefail

ref="${AWSEMU_REF:-v1}"
app="${HOME}/.awsemu/app"
bin="${HOME}/.local/bin"

if [[ -n "${AWSEMU_SOURCE:-}" ]]; then
  src="${AWSEMU_SOURCE}"
else
  src="$(mktemp -d)"
  trap 'rm -rf "${src}"' EXIT
  curl -fsSL "https://github.com/Guilherme-Benfica/setup-aws-emulator/archive/refs/tags/${ref}.tar.gz" |
    tar -xz -C "${src}" --strip-components=1
fi

rm -rf "${app}"
mkdir -p "${app}" "${bin}"
cp -R "${src}/bin" "${src}/scripts" "${app}/"
chmod +x "${app}/bin/awsemu"
ln -sf "${app}/bin/awsemu" "${bin}/awsemu"

echo "Installed awsemu in ${bin}"
case ":${PATH}:" in
  *":${bin}:"*) ;;
  *) echo "Add it to your PATH: export PATH=\"${bin}:\$PATH\"" ;;
esac
echo "Start the emulator with: awsemu up"
