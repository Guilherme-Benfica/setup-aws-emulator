#!/usr/bin/env bash
# Makes SDKs that ignore AWS_CA_BUNDLE trust the emulator: Node, .NET and Rust on Linux,
# and Java. Runs in the runner's own shell (Git Bash on Windows), after env.sh.
# Prints KEY=VALUE pairs on stdout; everything else goes to stderr.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${EMULATOR_PORT:-9297}"
ca="$(unix_path "${EMULATOR_CA:-${AWS_CA_BUNDLE:?AWS_CA_BUNDLE must point at the emulator ca.pem}}")"
java_tool_options="${JAVA_TOOL_OPTIONS_ENABLED:-false}"
dir="$(work_dir "${port}")"

# Node adds NODE_EXTRA_CA_CERTS to its own roots, so the emulator CA alone is right.
echo "NODE_EXTRA_CA_CERTS=$(windows_path "${ca}")"

# SSL_CERT_FILE replaces OpenSSL's roots, so it gets the system roots plus the emulator CA:
# npm, NuGet and curl keep working. .NET on Windows ignores it, so it is Linux only.
if [[ "$(uname -s)" == Linux ]]; then
  system_roots=""
  for candidate in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
    if [[ -f "${candidate}" ]]; then
      system_roots="${candidate}"
      break
    fi
  done
  if [[ -n "${system_roots}" ]]; then
    cat "${system_roots}" "${ca}" >"${dir}/ca-bundle.pem"
    echo "SSL_CERT_FILE=${dir}/ca-bundle.pem"
    set_output ca-bundle-combined "${dir}/ca-bundle.pem"
  else
    echo "::warning::No system CA bundle found, so SSL_CERT_FILE is not set. .NET and Rust may not trust the emulator." >&2
  fi
fi

# Java: a trust store with the JDK's roots plus the emulator CA.
if command -v keytool >/dev/null 2>&1; then
  keytool_path="$(command -v keytool)"
  java_home="${JAVA_HOME:-$(cd "$(dirname "$(readlink -f "${keytool_path}")")/.." && pwd)}"
  cacerts="$(unix_path "${java_home}")/lib/security/cacerts"
  store="${dir}/truststore.p12"
  rm -f "${store}"
  if [[ -f "${cacerts}" ]]; then
    keytool -importkeystore -noprompt -srckeystore "$(windows_path "${cacerts}")" -srcstorepass changeit \
      -destkeystore "$(windows_path "${store}")" -deststoretype PKCS12 -deststorepass changeit >/dev/null 2>&1
  fi
  keytool -importcert -noprompt -alias aws-emulator -file "$(windows_path "${ca}")" \
    -keystore "$(windows_path "${store}")" -storetype PKCS12 -storepass changeit >/dev/null 2>&1
  opts="-Djavax.net.ssl.trustStore=$(windows_path "${store}") -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
  echo "AWS_EMULATOR_JAVA_OPTS=${opts}"
  if [[ "${java_tool_options}" == true ]]; then
    echo "JAVA_TOOL_OPTIONS=${opts}"
  fi
  set_output java-truststore "$(windows_path "${store}")"
else
  echo "keytool not found, skipping the Java trust store." >&2
fi
