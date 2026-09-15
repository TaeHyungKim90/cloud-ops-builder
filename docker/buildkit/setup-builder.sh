#!/usr/bin/env bash
# WSL: Zscaler/사내 CA를 넣은 BuildKit 이미지로 multiarch buildx 빌더를 재생성한다.
#
# Usage (WSL):
#   cd /mnt/c/project/cloud-ops-builder
#   bash docker/buildkit/setup-builder.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BK_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="${BK_DIR}/certs"
IMAGE_TAG="${BUILDKIT_CA_IMAGE:-cloud-ops-builder-buildkit:with-ca}"
BUILDER_NAME="${BUILDKIT_BUILDER_NAME:-multiarch}"
SRC_CA_DIR="${SSL_CERT_SOURCE:-/usr/local/share/ca-certificates}"

echo "[buildkit-ca] copy CA from ${SRC_CA_DIR} → ${CERT_DIR}"
mkdir -p "${CERT_DIR}"
shopt -s nullglob
copied=0
for f in "${SRC_CA_DIR}"/*.crt "${SRC_CA_DIR}"/*.pem; do
  [ -f "$f" ] || continue
  cp -f "$f" "${CERT_DIR}/"
  echo "  + $(basename "$f")"
  copied=$((copied + 1))
done
shopt -u nullglob
if [ "${copied}" -eq 0 ]; then
  echo "[buildkit-ca] ERROR: no .crt/.pem in ${SRC_CA_DIR}" >&2
  echo "  WSL에 Zscaler/사내 루트를 먼저 설치하세요." >&2
  exit 1
fi

if ! docker image inspect moby/buildkit:buildx-stable-1 >/dev/null 2>&1; then
  echo "[buildkit-ca] pulling moby/buildkit:buildx-stable-1 (needs working TLS or local cache)"
  docker pull moby/buildkit:buildx-stable-1
fi

echo "[buildkit-ca] build ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" -f "${BK_DIR}/Dockerfile" "${BK_DIR}"

echo "[buildkit-ca] recreate buildx builder '${BUILDER_NAME}'"
docker buildx rm -f "${BUILDER_NAME}" 2>/dev/null || true
docker buildx create \
  --name "${BUILDER_NAME}" \
  --driver docker-container \
  --driver-opt "image=${IMAGE_TAG}" \
  --use
docker buildx inspect --bootstrap

echo "[buildkit-ca] done. example:"
echo "  docker buildx build --platform linux/amd64 \\"
echo "    -t nexus.sk-inc.com:8081/cr/cloud-ops-builder:v1.2.0 --load ."
