# ansible-role-rtpengine

Ansible role for installing rtpengine

![CI](https://github.com/miarec/ansible-role-rtpengine/actions/workflows/ci.yml/badge.svg?event=push)
![Test images](https://github.com/miarec/ansible-role-rtpengine/actions/workflows/image.yml/badge.svg?event=push)

The role builds RTPEngine from source and installs it into `rtpengine_install_dir`
(default `/opt/rtpengine`). When `{{ rtpengine_install_dir }}/usr/bin/rtpengine`
already exists, the role skips the build and only configures RTPEngine. To build
again, set `rtpengine_force_install: true`.

Supported platforms: Ubuntu 22.04 (jammy) and Ubuntu 24.04 (noble).

# Dependencies

- `rsyslog`: by default, rsyslog is used for logging. It is not required, but recommended.
- `nftables`: optional. RTPEngine uses nftables only for in-kernel packet forwarding
  (`rtpengine_use_kernel_module: true`). By default, RTPEngine forwards media in user space.

# Role Variables

For a full list of variables, see [defaults/main.yml](./defaults/main.yml)

## Installation Variables

 - `rtpengine_version`: version of rtpengine to install, See https://github.com/sipwise/rtpengine/tags for available version
 - `rtpengine_user`: linux user to run the service, default = `rtpengine`
 - `rtpengine_group`: linux group the linux user belongs to, default = `rtpengine`

 - `rtpengine_cleanup_downloads`: when true, source download files will be deleted after successful install, default = `true`
 - `rtpengine_force_install`: when true, rtpengine will be installed and configured, even if rtpengine is already installed. default = `false`

## Network Settings
 - `rtpengine_addr`: IPv4 listen IP address
 - `rtpengine_advaddr`: Optional - Set advertised address of rtpengine. Useful if the rtpengine is behind a NAT firewall
 - `rtpengine_ctrl_protocol`: protocol used to communicate with Kamailio, options are: 'ng', 'tcp-ng', 'udp', 'tcp', 'http', or 'https', default is `ng`
 - `rtpengine_ctrl_port`: Port that rtpengine will listen on, default is `2223`
 - `rtpengine_min_port`: Lower limit on UDP ports range that the rtpengine uses for RTP/RTCP sessions
 - `rtpengine_max_port`: Upper limit on UDP ports range that the rtpengine uses for RTP/RTCP sessions

## Logging

- `rtpengine_log_dir`: directory for log files, default = `/var/log/rtpengine`
- `rtpengine_log_file`: name of the log file, default = `rtpengine.log`

## Configuration
 - `rtpengine_config_file`: Optional, you can supply a path to a config file with additional configuration

# Example Playbook

```yaml
# ------------------------------------------------
# Install rtpengine
# ------------------------------------------------
- name: Deploy rtpengine
  hosts: rtp
  become: true

  pre_tasks:

    - include_vars: override_vars/custom.yml
      failed_when: false

    - name: Install packages
      package:
        name: "{{ item }}"
        state: present
      with_items:
        - rsyslog  # required for logging
        - nftables # required for kernel forwarding

    - name: Enable nftables
      systemd:
        name: nftables
        enabled: true
        state: started

    - set_fact:
        rtpengine_addr: 192.168.1.10


  roles:
    - role: 'rtpengine'

  tags:
```


# Kamailio Config
to support rtpengine, the following should be provided in the kamailio config

```
#!define WITH_RTPENGINE

...

#!ifdef WITH_RTPENGINE
loadmodule "rtpengine.so"
#!else
loadmodule "rtpproxy.so"
#!endif

...

#!ifdef WITH_RTPENGINE
# ----- rtpengine params -----
modparam("rtpengine", "rtpengine_sock", "udp:172.31.9.87:2223")
#!else
# ----- rtpproxy params -----
{% for addr in rtpproxy_sock_addresses %}
modparam("rtpproxy", "rtpproxy_sock", "{{ addr }}")
{% endfor %}
#!endif

```

# Testing

This role uses [Molecule](https://molecule.readthedocs.io/) with Docker for testing.
[uv](https://docs.astral.sh/uv/) manages the Python dependencies (`pyproject.toml`
and `uv.lock`).

## Prerequisites

- Docker
- uv (install with `curl -LsSf https://astral.sh/uv/install.sh | sh`)

## Run the tests

```bash
# Lint
uv run ansible-lint

# Build RTPEngine from source in an Ubuntu 24.04 container and test it
uv run molecule test

# Test another distribution or RTPEngine version
MOLECULE_DISTRO=ubuntu2204 uv run molecule test
MOLECULE_RTPENGINE_VERSION=12.5.1.4 uv run molecule test
```

The Molecule scenario loads the role by path, so the test also works when the role
is checked out under another directory name, for example as `roles/rtpengine` in a
playbook repository.

Molecule variables:

| Variable                     | Default      | Description                                  |
|------------------------------|--------------|----------------------------------------------|
| `MOLECULE_DISTRO`            | `ubuntu2404` | Container OS: `ubuntu2204` or `ubuntu2404`   |
| `MOLECULE_RTPENGINE_VERSION` | `12.5.1.5`   | Value of `rtpengine_version`                 |
| `MOLECULE_ANSIBLE_VERBOSITY` | `0`          | Ansible verbosity, 0-3 (same as `-v`-`-vvv`) |
| `MOLECULE_IMAGE`             |              | Image to test in the `image` scenario        |

# Test images

The repository publishes systemd test images with RTPEngine already built by this
role's install tasks:

```text
ghcr.io/miarec/rtpengine:<rtpengine version>-<distribution>
```

For example, `ghcr.io/miarec/rtpengine:12.5.1.5-ubuntu2404`. Each image is
multi-arch (`linux/amd64` and `linux/arm64`) and starts from
`ghcr.io/miarec/<distribution>-systemd`. The per-architecture tags (for example
`12.5.1.5-ubuntu2404-arm64`) are intermediate build results.

Use the images in tests of playbooks that use this role. When the role runs against
a container from the image, it finds `/opt/rtpengine/usr/bin/rtpengine`, skips the
build, and only configures and starts RTPEngine. Run the container the same way as
the systemd base image, for example in Molecule:

```yaml
platforms:
  - name: rtpengine
    image: ghcr.io/miarec/rtpengine:12.5.1.5-ubuntu2404
    command: ""
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    cgroupns_mode: host
    privileged: true
    pre_build_image: true
```

The image contains the RTPEngine binaries, the `rtpengine` user and group, the build
dependencies (without `pandoc`, `dkms`, and the kernel headers), `rsyslog`, and
`nftables`. The `rtpengine` service is not installed until the role runs. The image
has no kernel module: RTPEngine forwards media in user space. Do not use the images
in production: production hosts build RTPEngine with the role.

## Versions

`image/versions.json` lists the RTPEngine versions and distributions to build. The
`Test images` workflow (`.github/workflows/image.yml`) builds every combination:

- On pull requests, it builds and smoke-tests the images, but does not push them.
- On pushes to `master`, it builds, smoke-tests, and pushes the images.
- When run manually (`workflow_dispatch`) on `master`, it builds and pushes the
  versions in `image/versions.json`, or only the version in the
  `rtpengine_version` input. A manual run on another branch only builds and
  smoke-tests.

The first push creates the GHCR package `miarec/rtpengine`. GHCR makes a new
package private, so an organization owner must make it public once (package
settings, "Change visibility"). After that, anyone can pull the images without
logging in.

To add a version, add it to `image/versions.json` and merge the change to `master`.
To build a version once without changing the file:

```bash
gh workflow run image.yml -f rtpengine_version=12.5.1.6
```

## Build an image locally

`image/build.sh` starts a container from the systemd base image, runs the Molecule
converge playbook (`molecule/default/converge.yml`) in it, removes the `rtpengine`
service unit and the build-only packages, and commits the container for the
architecture of your Docker host. The `image` Molecule scenario runs the role
against a container from the new image. It fails if the role builds RTPEngine
again, if the image holds another RTPEngine version, or if the service does not
start.

```bash
image/build.sh 12.5.1.5 ubuntu2404 ghcr.io/miarec/rtpengine:12.5.1.5-ubuntu2404
MOLECULE_IMAGE=ghcr.io/miarec/rtpengine:12.5.1.5-ubuntu2404 uv run molecule test -s image
```
