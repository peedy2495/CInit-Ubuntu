# Ubuntu Resolute Docker CE

This template builds a NoCloud cloud-init ISO for Ubuntu Resolute.
It installs Docker CE from a configurable Docker APT repository during first
boot.

## Files

- `files/meta-data.template`: cloud-init metadata template rendered with values from `files/.env`
- `files/network-config.template`: Netplan network template rendered with values from `files/.env`
- `files/user-data.template`: Ubuntu cloud-config template rendered with values from `files/.env`
- `create-env.sh`: interactive helper that collects host/network values, timezone, optional time server, Ubuntu APT repository URLs, Docker APT repository URL, passwords and SSH public keys, then writes `files/.env`
- `create-iso.sh`: renders `user-data`, `network-config`, and `meta-data`, then builds `image/cinit_UbuntuResolute_docker-ce_<hostname>.iso`

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
or `ports.ubuntu.com`, then uses the archive URL for `resolute`, `resolute-updates`,
and `resolute-backports`, and the security URL for `resolute-security`. If both
values are empty, the template leaves the Ubuntu image's existing APT sources
unchanged.

## Time Server

`create-env.sh` asks for an optional time server. If left empty, no chrony
configuration is added and the image defaults are left unchanged. If set, the
template writes `/etc/chrony/conf.d/99-cinit-timeserver.conf` with that server.

## Docker CE Repository

`create-env.sh` asks for the Docker APT repository URL. The default is:

```text
https://download.docker.com/linux/ubuntu
```

If you proxy Docker packages through Nexus, provide the full repository URL for
that proxy instead. The first-boot cloud-init config downloads the repository key
from `<Docker APT repository URL>/gpg` in `bootcmd`, stores it at
`/etc/apt/keyrings/docker.asc`, adds the Docker repository through
`apt.sources`, then installs:

- `docker-ce`
- `docker-ce-cli`
- `containerd.io`
- `docker-buildx-plugin`
- `docker-compose-plugin`

The `docker` service is enabled and started, and the `sysadmin` and `ansible`
users are added to the `docker` group.

## Insecure Registry

`create-env.sh` asks for an optional Docker registry URL to add as an insecure
registry. If left empty, no Docker daemon configuration is written. If set, the
value is normalized by removing an `http://` or `https://` prefix and any path,
then written to `/etc/docker/daemon.json` as an `insecure-registries` entry.

## Usage

1. Run `./create-env.sh`
2. Run `./create-iso.sh`

Generated files, ISOs, and the local `files/.env` are ignored by Git.
