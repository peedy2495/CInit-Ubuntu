#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files_dir="${script_dir}/files"
env_file="${files_dir}/.env"
template_file="${files_dir}/.env.example"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

generate_yescrypt_hash() {
  local password="$1"
  local hash=''

  require_cmd mkpasswd

  hash="$(printf '%s' "${password}" | mkpasswd --method=yescrypt --stdin 2>/dev/null | head -n1)"
  if [[ "${hash}" == \$y\$* ]]; then
    printf '%s' "${hash}"
    return 0
  fi

  printf 'Unable to generate yescrypt hash with mkpasswd.\n' >&2
  exit 1
}

prompt_secret() {
  local prompt_label="$1"
  local value

  while true; do
    read -r -s -p "${prompt_label}: " value
    printf '\n' >&2
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    printf 'Value cannot be empty.\n' >&2
  done
}

valid_yescrypt_hash() {
  local value="${1:-}"

  [[ "${value}" == \$y\$* && "${value}" != *replace_with* ]]
}

valid_pubkey() {
  local value="${1:-}"

  [[ "${value}" == ssh-* && "${value}" != *AAAA...* ]]
}

prompt_secret_hash_default() {
  local prompt_label="$1"
  local current_hash="${2:-}"
  local value

  if valid_yescrypt_hash "${current_hash}"; then
    read -r -s -p "${prompt_label} [keep existing]: " value
    printf '\n' >&2
    if [[ -z "${value}" ]]; then
      printf '%s' "${current_hash}"
      return 0
    fi
    generate_yescrypt_hash "${value}"
    return 0
  fi

  value="$(prompt_secret "${prompt_label}")"
  generate_yescrypt_hash "${value}"
}

prompt_pubkey() {
  local prompt_label="$1"
  local value

  while true; do
    read -r -p "${prompt_label}: " value
    if [[ "${value}" == ssh-* ]]; then
      printf '%s' "${value}"
      return 0
    fi
    printf 'Please provide a valid SSH public key starting with ssh-.\n' >&2
  done
}

prompt_pubkey_default() {
  local prompt_label="$1"
  local default_value="${2:-}"
  local value

  while true; do
    if valid_pubkey "${default_value}"; then
      read -r -p "${prompt_label} [keep existing]: " value
      if [[ -z "${value}" ]]; then
        printf '%s' "${default_value}"
        return 0
      fi
    else
      read -r -p "${prompt_label}: " value
    fi

    if valid_pubkey "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    printf 'Please provide a valid SSH public key starting with ssh-.\n' >&2
  done
}

prompt_text() {
  local prompt_label="$1"
  local value

  while true; do
    read -r -p "${prompt_label}: " value
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    printf 'Value cannot be empty.\n' >&2
  done
}

prompt_text_default() {
  local prompt_label="$1"
  local default_value="$2"
  local value

  while true; do
    if [[ -n "${default_value}" ]]; then
      read -r -p "${prompt_label} [${default_value}]: " value
      if [[ -z "${value}" ]]; then
        printf '%s' "${default_value}"
        return 0
      fi
    else
      read -r -p "${prompt_label}: " value
      if [[ -z "${value}" ]]; then
        printf 'Value cannot be empty.\n' >&2
        continue
      fi
    fi

    printf '%s' "${value}"
    return 0
  done
}

prompt_text_optional_default() {
  local prompt_label="$1"
  local default_value="${2:-}"
  local value

  if [[ -n "${default_value}" ]]; then
    read -r -p "${prompt_label} [${default_value}]: " value
    if [[ -z "${value}" ]]; then
      printf '%s' "${default_value}"
      return 0
    fi
  else
    read -r -p "${prompt_label}: " value
  fi

  printf '%s' "${value}"
}

prompt_mac_default() {
  local prompt_label="$1"
  local default_value="${2:-}"
  local value

  while true; do
    if [[ -n "${default_value}" ]]; then
      read -r -p "${prompt_label} [${default_value}]: " value
      if [[ -z "${value}" ]]; then
        value="${default_value}"
      fi
    else
      read -r -p "${prompt_label}: " value
    fi
    value="${value,,}"
    if [[ "${value}" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
    printf 'Please provide a valid MAC address like 52:54:00:12:34:56.\n' >&2
  done
}

trim_text() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

escape_squote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

nameservers_yaml_to_csv() {
  local yaml="${1:-}"
  local line
  local ns
  local result=''

  while IFS= read -r line; do
    line="$(trim_text "${line}")"
    if [[ "${line}" == "- "* ]]; then
      ns="$(trim_text "${line#- }")"
      if [[ -n "${ns}" ]]; then
        if [[ -n "${result}" ]]; then
          result+=","
        fi
        result+="${ns}"
      fi
    fi
  done <<< "${yaml}"

  printf '%s' "${result}"
}

if [[ ! -f "${template_file}" ]]; then
  printf 'Template file not found: %s\n' "${template_file}" >&2
  exit 1
fi

have_env_file=false
set -a
source "${template_file}"
template_timezone="${TIMEZONE:-Europe/Berlin}"
template_timeserver="${TIMESERVER:-}"
if [[ -f "${env_file}" ]]; then
  source "${env_file}"
  have_env_file=true
fi
set +a

if [[ "${have_env_file}" == true ]]; then
  nameservers_csv_default="$(nameservers_yaml_to_csv "${NAMESERVERS_YAML:-}")"
  fqdn_default="${FQDN:-}"
  interface_mac_default="${INTERFACE_MAC:-}"
  static_ip_cidr_default="${STATIC_IP_CIDR:-}"
  gateway_ip_default="${GATEWAY_IP:-}"
  nexus_apt_archive_url_default="${NEXUS_APT_ARCHIVE_URL:-}"
  nexus_apt_security_url_default="${NEXUS_APT_SECURITY_URL:-}"
  docker_apt_repository_url_default="${DOCKER_APT_REPOSITORY_URL:-}"
  docker_insecure_registry_default="${DOCKER_INSECURE_REGISTRY:-}"
else
  nameservers_csv_default=''
  fqdn_default=''
  interface_mac_default=''
  static_ip_cidr_default=''
  gateway_ip_default=''
  nexus_apt_archive_url_default=''
  nexus_apt_security_url_default=''
  docker_apt_repository_url_default=''
  docker_insecure_registry_default=''
  TIMEZONE="${template_timezone}"
  TIMESERVER="${template_timeserver}"
  ROOT_PASSWORD_HASH=''
  SYSADMIN_PASSWORD_HASH=''
  SYSADMIN_SSH_PUBKEY=''
  ANSIBLE_SSH_PUBKEY=''
fi

fqdn="$(prompt_text_default "FQDN (example: host.example.com)" "${fqdn_default}")"
interface_mac="$(prompt_mac_default "Interface MAC address (example: 52:54:00:12:34:56)" "${interface_mac_default}")"
static_ip_cidr="$(prompt_text_default "Static IP with CIDR (example: 192.168.0.100/24)" "${static_ip_cidr_default}")"
gateway_ip="$(prompt_text_default "Gateway IP (example: 192.168.0.1)" "${gateway_ip_default}")"
nameservers_csv="$(prompt_text_default "Nameservers comma separated (example: 192.168.0.1,1.1.1.1)" "${nameservers_csv_default}")"
timezone="$(prompt_text_default "Timezone" "${TIMEZONE:-Europe/Berlin}")"
timeserver="$(prompt_text_optional_default "Time server (empty keeps image defaults)" "${TIMESERVER:-}")"
nexus_apt_archive_url="$(prompt_text_optional_default "Nexus APT archive URL (empty keeps Ubuntu image defaults)" "${nexus_apt_archive_url_default}")"
nexus_apt_security_url="$(prompt_text_optional_default "Nexus APT security URL (empty keeps Ubuntu image defaults)" "${nexus_apt_security_url_default}")"
docker_apt_repository_url="$(prompt_text_default "Docker APT repository URL" "${docker_apt_repository_url_default}")"
docker_apt_repository_url="${docker_apt_repository_url%/}"
docker_insecure_registry="$(prompt_text_optional_default "Docker registry URL for insecure registry (empty keeps Docker defaults)" "${docker_insecure_registry_default}")"
docker_insecure_registry="${docker_insecure_registry#http://}"
docker_insecure_registry="${docker_insecure_registry#https://}"
docker_insecure_registry="${docker_insecure_registry%%/*}"

root_hash="$(prompt_secret_hash_default "Root password" "${ROOT_PASSWORD_HASH:-}")"
sysadmin_hash="$(prompt_secret_hash_default "sysadmin password" "${SYSADMIN_PASSWORD_HASH:-}")"
sysadmin_pubkey="$(prompt_pubkey_default "sysadmin SSH public key" "${SYSADMIN_SSH_PUBKEY:-}")"
ansible_pubkey="$(prompt_pubkey_default "ansible SSH public key" "${ANSIBLE_SSH_PUBKEY:-}")"

hostname_short="${fqdn%%.*}"
static_ip="${static_ip_cidr%%/*}"

nameservers_yaml=''
IFS=',' read -r -a nameservers_array <<< "${nameservers_csv}"
for ns in "${nameservers_array[@]}"; do
  ns_trimmed="$(trim_text "${ns}")"
  if [[ -n "${ns_trimmed}" ]]; then
    nameservers_yaml+="        - ${ns_trimmed}"$'\n'
  fi
done

if [[ -z "${nameservers_yaml}" ]]; then
  printf 'At least one nameserver must be provided.\n' >&2
  exit 1
fi

cat > "${env_file}" <<EOF
FQDN='$(escape_squote "${fqdn}")'
HOSTNAME_SHORT='$(escape_squote "${hostname_short}")'
INTERFACE_MAC='$(escape_squote "${interface_mac}")'
STATIC_IP_CIDR='$(escape_squote "${static_ip_cidr}")'
STATIC_IP='$(escape_squote "${static_ip}")'
GATEWAY_IP='$(escape_squote "${gateway_ip}")'
NAMESERVERS_YAML='$(escape_squote "${nameservers_yaml}")'
TIMEZONE='$(escape_squote "${timezone}")'
TIMESERVER='$(escape_squote "${timeserver}")'
NEXUS_APT_ARCHIVE_URL='$(escape_squote "${nexus_apt_archive_url}")'
NEXUS_APT_SECURITY_URL='$(escape_squote "${nexus_apt_security_url}")'
DOCKER_APT_REPOSITORY_URL='$(escape_squote "${docker_apt_repository_url}")'
DOCKER_INSECURE_REGISTRY='$(escape_squote "${docker_insecure_registry}")'
ROOT_PASSWORD_HASH='$(escape_squote "${root_hash}")'
SYSADMIN_PASSWORD_HASH='$(escape_squote "${sysadmin_hash}")'
SYSADMIN_SSH_PUBKEY='$(escape_squote "${sysadmin_pubkey}")'
ANSIBLE_SSH_PUBKEY='$(escape_squote "${ansible_pubkey}")'
EOF

chmod 600 "${env_file}"
printf 'Wrote %s with host/network/timezone, APT repository URLs, password hashes and SSH public keys.\n' "${env_file}"
