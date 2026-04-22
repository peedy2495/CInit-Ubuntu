#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files_dir="${script_dir}/files"
image_dir="${script_dir}/image"
env_file="${files_dir}/.env"
user_data_template="${files_dir}/user-data.template"
network_config_template="${files_dir}/network-config.template"
meta_data_template="${files_dir}/meta-data.template"
rendered_user_data="${files_dir}/user-data"
rendered_network_config="${files_dir}/network-config"
rendered_meta_data="${files_dir}/meta-data"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_cmd envsubst
require_cmd cloud-localds

if [[ ! -f "${env_file}" ]]; then
  printf 'Missing %s. Run ./create-env.sh first.\n' "${env_file}" >&2
  exit 1
fi

for template_file in "${user_data_template}" "${network_config_template}" "${meta_data_template}"; do
  if [[ ! -f "${template_file}" ]]; then
    printf 'Missing template file: %s\n' "${template_file}" >&2
    exit 1
  fi
done

mkdir -p "${image_dir}"

set -a
source "${env_file}"
set +a

iso_name="cinit_UbuntuNoble_generic_${HOSTNAME_SHORT}.iso"
iso_path="${image_dir}/${iso_name}"

required_vars=(
  FQDN
  HOSTNAME_SHORT
  INTERFACE_MAC
  STATIC_IP_CIDR
  STATIC_IP
  GATEWAY_IP
  NAMESERVERS_YAML
  TIMEZONE
  ROOT_PASSWORD_HASH
  SYSADMIN_PASSWORD_HASH
  SYSADMIN_SSH_PUBKEY
  ANSIBLE_SSH_PUBKEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    printf 'Required variable %s is not set in %s\n' "${var_name}" "${env_file}" >&2
    exit 1
  fi
done

if [[ -z "${NEXUS_APT_ARCHIVE_URL+x}" ]]; then
  printf 'Required variable NEXUS_APT_ARCHIVE_URL is not set in %s\n' "${env_file}" >&2
  exit 1
fi

if [[ -z "${NEXUS_APT_SECURITY_URL+x}" ]]; then
  printf 'Required variable NEXUS_APT_SECURITY_URL is not set in %s\n' "${env_file}" >&2
  exit 1
fi

APT_BOOTCMD_BLOCK=''
APT_SOURCES_BLOCK=''
if [[ -n "${NEXUS_APT_ARCHIVE_URL}" || -n "${NEXUS_APT_SECURITY_URL}" ]]; then
  if [[ -z "${NEXUS_APT_ARCHIVE_URL}" || -z "${NEXUS_APT_SECURITY_URL}" ]]; then
    printf 'Set both NEXUS_APT_ARCHIVE_URL and NEXUS_APT_SECURITY_URL, or leave both empty.\n' >&2
    exit 1
  fi

  APT_BOOTCMD_BLOCK="$(cat <<'EOF'
bootcmd:
  - |
    set -eu
    disabled_dir=/etc/apt/native-sources.disabled
    mkdir -p "${disabled_dir}"
    for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [ -e "${source_file}" ] || continue
      if grep -Eq '(archive|security|ports)\.ubuntu\.com/ubuntu' "${source_file}"; then
        mv "${source_file}" "${disabled_dir}/$(basename "${source_file}").cloud-image"
      fi
    done
EOF
)"

  APT_SOURCES_BLOCK="$(cat <<EOF
  preserve_sources_list: false
  sources_list: |
    deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] ${NEXUS_APT_ARCHIVE_URL} noble main restricted universe multiverse
    deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] ${NEXUS_APT_ARCHIVE_URL} noble-updates main restricted universe multiverse
    deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] ${NEXUS_APT_ARCHIVE_URL} noble-backports main restricted universe multiverse
    deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] ${NEXUS_APT_SECURITY_URL} noble-security main restricted universe multiverse
EOF
)"
fi
export APT_BOOTCMD_BLOCK
export APT_SOURCES_BLOCK

HOSTNAME_SHORT="${FQDN%%.*}"
export HOSTNAME_SHORT

if [[ "${ROOT_PASSWORD_HASH}" != \$y\$* ]]; then
  printf 'ROOT_PASSWORD_HASH must be yescrypt (start with $y$). Re-run ./create-env.sh\n' >&2
  exit 1
fi

if [[ "${SYSADMIN_PASSWORD_HASH}" != \$y\$* ]]; then
  printf 'SYSADMIN_PASSWORD_HASH must be yescrypt (start with $y$). Re-run ./create-env.sh\n' >&2
  exit 1
fi

envsubst < "${user_data_template}" > "${rendered_user_data}"
envsubst < "${network_config_template}" > "${rendered_network_config}"
envsubst < "${meta_data_template}" > "${rendered_meta_data}"
chmod 600 "${rendered_user_data}"

rm -f "${iso_path}"
cloud-localds \
  --filesystem=iso \
  --network-config="${rendered_network_config}" \
  "${iso_path}" \
  "${rendered_user_data}" \
  "${rendered_meta_data}"

printf 'Created %s\n' "${iso_path}"
