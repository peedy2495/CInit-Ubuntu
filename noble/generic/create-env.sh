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

  read -r -p "${prompt_label} [${default_value}]: " value
  if [[ -z "${value}" ]]; then
    printf '%s' "${default_value}"
    return 0
  fi
  printf '%s' "${value}"
}

prompt_text_optional() {
  local prompt_label="$1"
  local value

  read -r -p "${prompt_label}: " value
  printf '%s' "${value}"
}

prompt_mac() {
  local prompt_label="$1"
  local value

  while true; do
    read -r -p "${prompt_label}: " value
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

if [[ ! -f "${template_file}" ]]; then
  printf 'Template file not found: %s\n' "${template_file}" >&2
  exit 1
fi

fqdn="$(prompt_text "FQDN (example: host.example.com)")"
interface_mac="$(prompt_mac "Interface MAC address (example: 52:54:00:12:34:56)")"
static_ip_cidr="$(prompt_text "Static IP with CIDR (example: 192.168.0.100/24)")"
gateway_ip="$(prompt_text "Gateway IP (example: 192.168.0.1)")"
nameservers_csv="$(prompt_text "Nameservers comma separated (example: 192.168.0.1,1.1.1.1)")"
timezone="$(prompt_text_default "Timezone" "Europe/Berlin")"
nexus_apt_archive_url="$(prompt_text_optional "Nexus APT archive URL (empty keeps Ubuntu image defaults)")"
nexus_apt_security_url="$(prompt_text_optional "Nexus APT security URL (empty keeps Ubuntu image defaults)")"

root_password="$(prompt_secret "Root password")"
sysadmin_password="$(prompt_secret "sysadmin password")"
sysadmin_pubkey="$(prompt_pubkey "sysadmin SSH public key")"
ansible_pubkey="$(prompt_pubkey "ansible SSH public key")"

root_hash="$(generate_yescrypt_hash "${root_password}")"
sysadmin_hash="$(generate_yescrypt_hash "${sysadmin_password}")"

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
NEXUS_APT_ARCHIVE_URL='$(escape_squote "${nexus_apt_archive_url}")'
NEXUS_APT_SECURITY_URL='$(escape_squote "${nexus_apt_security_url}")'
ROOT_PASSWORD_HASH='$(escape_squote "${root_hash}")'
SYSADMIN_PASSWORD_HASH='$(escape_squote "${sysadmin_hash}")'
SYSADMIN_SSH_PUBKEY='$(escape_squote "${sysadmin_pubkey}")'
ANSIBLE_SSH_PUBKEY='$(escape_squote "${ansible_pubkey}")'
EOF

chmod 600 "${env_file}"
printf 'Wrote %s with host/network/timezone, password hashes and SSH public keys.\n' "${env_file}"
