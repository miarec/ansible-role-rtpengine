#!/usr/bin/env bash
# Build a test image with RTPEngine already built by this role.
#
# The script starts a systemd container from ghcr.io/miarec/<distro>-systemd,
# runs the Molecule converge playbook against it (the same playbook that
# `molecule test` runs), removes the service unit and the build-only packages,
# and commits the container as an image. The image holds an installed but
# unconfigured RTPEngine.
#
# Usage: image/build.sh <rtpengine-version> <distro> <image-tag>
# Example: image/build.sh 12.5.1.5 ubuntu2404 ghcr.io/miarec/rtpengine:12.5.1.5-ubuntu2404
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <rtpengine-version> <distro> <image-tag>" >&2
  exit 2
fi

version=$1
distro=$2
tag=$3
base_image="ghcr.io/miarec/${distro}-systemd:latest"
container="rtpengine-image-build-${distro}-$$"
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
revision=${IMAGE_REVISION:-$(git -C "$repo_dir" rev-parse HEAD)}

cleanup() {
  docker rm --force --volumes "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting ${container} from ${base_image}"
docker pull --quiet "$base_image"
# The same container options as the Molecule scenario. SIGRTMIN+3 makes
# systemd shut down cleanly on "docker stop".
docker run --detach --name "$container" \
  --privileged --cgroupns=host \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --stop-signal SIGRTMIN+3 \
  "$base_image"

echo "Building RTPEngine ${version} with the role"
start=$(date +%s)
RTPENGINE_VERSION="$version" uv run --project "$repo_dir" ansible-playbook \
  --inventory "${container}," \
  --connection community.docker.docker \
  "$repo_dir/molecule/default/converge.yml"
echo "Role converge from scratch took $(($(date +%s) - start)) s"

# The role configures and starts RTPEngine for 127.0.0.1. Remove the unit so
# that the role creates it again, as on a new host, when it configures a
# container from the image. Pandoc (documentation) and dkms with the kernel
# headers (kernel module) are needed only to build. The purge also removes
# their dependencies that nothing else needs, such as kmod; together they take
# about 260-330 MB.
echo "Removing the service configuration and build-only packages"
docker exec "$container" sh -c '
  set -e
  systemctl disable --now rtpengine
  rm -f /etc/systemd/system/rtpengine.service
  systemctl daemon-reload
  truncate -s 0 /var/log/rtpengine/rtpengine.log
  DEBIAN_FRONTEND=noninteractive apt-get purge --yes --auto-remove pandoc dkms
  apt-get clean
  rm -rf /root/.ansible /var/log/journal/*
  /opt/rtpengine/usr/bin/rtpengine --version
'
docker stop "$container"

echo "Committing ${container} as ${tag}"
docker commit \
  --change 'CMD ["/lib/systemd/systemd"]' \
  --change "LABEL org.opencontainers.image.title=rtpengine" \
  --change "LABEL org.opencontainers.image.description=\"RTPEngine ${version} built by ansible-role-rtpengine on ${distro}, for tests\"" \
  --change "LABEL org.opencontainers.image.version=${version}" \
  --change "LABEL org.opencontainers.image.source=https://github.com/miarec/ansible-role-rtpengine" \
  --change "LABEL org.opencontainers.image.revision=${revision}" \
  --change "LABEL org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --change "LABEL org.opencontainers.image.licenses=MIT" \
  --change "LABEL org.opencontainers.image.base.name=${base_image}" \
  "$container" "$tag"

echo "Built ${tag}"
