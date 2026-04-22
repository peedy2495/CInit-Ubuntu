# Ubuntu Noble Generic

This template builds a NoCloud cloud-init ISO for Ubuntu 24.04 LTS (Noble).
It is intended as a reusable baseline for many server cases and does not install
or configure application-specific roles such as FreeIPA.

## Files

- `files/meta-data.template`: cloud-init metadata template rendered with values from `files/.env`
- `files/network-config.template`: Netplan network template rendered with values from `files/.env`
- `files/user-data.template`: Ubuntu cloud-config template rendered with values from `files/.env`
- `create-env.sh`: interactive helper that collects host/network values, timezone, passwords and SSH public keys, then writes `files/.env`
- `create-iso.sh`: renders `user-data`, `network-config`, and `meta-data`, then builds `image/cinit_UbuntuNoble_generic.iso`

## Requirements

On an Ubuntu workstation, install the helper tools with:

```bash
sudo apt install cloud-image-utils gettext-base whois
```

## Nexus APT Structure

Use Nexus as APT mirror/repository endpoints, not as a generic HTTP proxy.
The client template can use two full Nexus URLs:

```text
NEXUS_APT_ARCHIVE_URL=http://nexus.example.com/repository/apt-ubuntu-archive/
NEXUS_APT_SECURITY_URL=http://nexus.example.com/repository/apt-ubuntu-security/
```

Recommended Nexus repositories:

- `apt-ubuntu-archive`: proxy repository for `http://archive.ubuntu.com/ubuntu/`
- `apt-ubuntu-security`: proxy repository for `http://security.ubuntu.com/ubuntu/`

When both values are set, the generated Ubuntu client config disables native
Ubuntu source files that point at `archive.ubuntu.com`, `security.ubuntu.com`,
or `ports.ubuntu.com`, then uses the archive URL for `noble`, `noble-updates`,
and `noble-backports`, and the security URL for `noble-security`. If both
values are empty, the template leaves the Ubuntu image's existing APT sources
unchanged.

## Usage

1. Run `./create-env.sh`
2. Run `./create-iso.sh`

Generated files, ISOs, and the local `files/.env` are ignored by Git.
