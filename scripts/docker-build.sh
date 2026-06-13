#!/usr/bin/env bash
# Build the bun-browser Docker image (Chrome + noVNC + daemon).
# The image runs `bun install` + `bun run build` from repo source (not npm; bun-browser is not published there).
# Three Dockerfiles: nopass (open noVNC), passvnc (nginx basic auth + scripts/entrance.sh),
# or passvnc-clash (passvnc + clash-for-linux proxy + Chrome --proxy-server).
#
# Runtime: both variants mount /chrome-profile (see compose.yml). On start, stale Chrome
# SingletonLock/Socket/Cookie files are removed so a new container ID does not trip Chrome's
# "profile in use on another computer" error. Rebuild the image after changing scripts/entrance*.sh or nopass CMD.
#
# Usage:
#   bash scripts/docker-build.sh
#   bash scripts/docker-build.sh [tag]
#   bash scripts/docker-build.sh [--no-push] [tag]
#   bash scripts/docker-build.sh --variant nopass|passvnc|passvnc-clash [--no-push] [tag]
#
# Default tag (when [tag] omitted): short git commit hash (git rev-parse --short HEAD).
#
# Non-interactive (CI): set --variant or DOCKER_VARIANT=nopass|passvnc|passvnc-clash
#
# Environment — build:
#   IMAGE_NAME          Base image name (default: bun-browser). Built as ${IMAGE_NAME}-${variant}:${tag}
#   DOCKER_VARIANT      nopass | passvnc — skips menu when set
#   BUN_VERSION         Bun base image version (default: 1.3.14, see oven/bun on Docker Hub)
#   SKIP_BUILD          If 1, skip build and only tag/push existing local image
#
# Environment — push (default; use --no-push to skip):
#   DOCKER_SPACE_SORA   Registry username or full path (e.g. myuser or ghcr.io/myorg)
#   DOCKER_TOKEN_SORA   Registry password or token (stdin to docker login)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

IMAGE_NAME="bunbrowser"
PUSH=1
TAG=""
VARIANT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-push) PUSH=0; shift ;;
    --variant)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --variant requires nopass, passvnc, or passvnc-clash" >&2
        exit 1
      fi
      VARIANT="$2"
      shift 2
      ;;
    *)
      TAG="${1}"
      shift
      ;;
  esac
done

if [[ -z "${VARIANT}" && -n "${DOCKER_VARIANT:-}" ]]; then
  VARIANT="${DOCKER_VARIANT}"
fi

if [[ -z "${VARIANT}" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Error: non-interactive shell requires --variant nopass|passvnc|passvnc-clash or DOCKER_VARIANT=nopass|passvnc|passvnc-clash" >&2
    exit 1
  fi
  echo ""
  echo "bun-browser Docker build — choose variant:"
  echo "  1) nopass        — noVNC without auth (Dockerfile: ./nopass)"
  echo "  2) passvnc       — noVNC + nginx basic auth (Dockerfile: ./passvnc, needs scripts/entrance.sh)"
  echo "  3) passvnc-clash — passvnc + clash-for-linux proxy (Dockerfile: ./passvnc-clash, needs scripts/entrance-clash.sh)"
  read -r -p "Enter 1, 2, or 3 [1]: " choice
  case "${choice:-1}" in
    3|passvnc-clash) VARIANT="passvnc-clash" ;;
    2|passvnc) VARIANT="passvnc" ;;
    1|nopass|"") VARIANT="nopass" ;;
    *)
      echo "Error: invalid choice" >&2
      exit 1
      ;;
  esac
fi

case "${VARIANT}" in
  nopass|passvnc|passvnc-clash) ;;
  *)
    echo "Error: variant must be nopass, passvnc, or passvnc-clash, got: ${VARIANT}" >&2
    exit 1
    ;;
esac

DOCKERFILE="${VARIANT}"
if [[ ! -f "${ROOT}/${DOCKERFILE}" ]]; then
  echo "Error: Dockerfile not found: ${ROOT}/${DOCKERFILE}" >&2
  exit 1
fi

if [[ "${VARIANT}" == "passvnc" && ! -f "${ROOT}/scripts/entrance.sh" ]]; then
  echo "Error: passvnc build requires ./scripts/entrance.sh" >&2
  exit 1
fi

if [[ "${VARIANT}" == "passvnc-clash" && ! -f "${ROOT}/scripts/entrance-clash.sh" ]]; then
  echo "Error: passvnc-clash build requires ./scripts/entrance-clash.sh" >&2
  exit 1
fi

# dist/ is built inside the Docker image (see nopass / passvnc Dockerfiles).

# Version tag = git commit (short hash) unless overridden on the command line
if [[ -z "${TAG}" ]]; then
  TAG="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo latest)"
fi

LOCAL_IMAGE="${IMAGE_NAME}-${VARIANT}:${TAG}"
BUN_VERSION="${BUN_VERSION:-1.3.14}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building ${LOCAL_IMAGE} (Dockerfile=${DOCKERFILE}, tag=${TAG}, bun=${BUN_VERSION})..."
  docker build --pull \
    --build-arg "BUN_VERSION=${BUN_VERSION}" \
    -f "${DOCKERFILE}" \
    -t "${LOCAL_IMAGE}" \
    "${ROOT}"
  echo "OK: ${LOCAL_IMAGE}"
fi

if [[ "${PUSH}" != "1" ]]; then
  exit 0
fi

DOCKER_REGISTRY="${DOCKER_SPACE_SORA:-}"
DOCKER_TOKEN="${DOCKER_TOKEN_SORA:-}"

if [[ -z "${DOCKER_REGISTRY}" || -z "${DOCKER_TOKEN}" ]]; then
  echo "Error: push requires DOCKER_SPACE_SORA and DOCKER_TOKEN_SORA (use --no-push to skip)" >&2
  exit 1
fi

REMOTE_IMAGE="${DOCKER_REGISTRY}/${IMAGE_NAME}-${VARIANT}:${TAG}"
echo "Tagging and pushing ${REMOTE_IMAGE}..."

if [[ "${DOCKER_REGISTRY}" == *"/"* ]]; then
  REGISTRY_HOST="${DOCKER_REGISTRY%%/*}"
  echo "${DOCKER_TOKEN}" | docker login "${REGISTRY_HOST}" -u "${DOCKER_REGISTRY#*/}" --password-stdin
else
  echo "${DOCKER_TOKEN}" | docker login -u "${DOCKER_REGISTRY}" --password-stdin
fi

docker tag "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"
docker push "${REMOTE_IMAGE}"

REMOTE_LATEST="${DOCKER_REGISTRY}/${IMAGE_NAME}-${VARIANT}:latest"
docker tag "${LOCAL_IMAGE}" "${REMOTE_LATEST}"
docker push "${REMOTE_LATEST}"

echo "Published ${REMOTE_IMAGE} and ${REMOTE_LATEST}"

echo "https://hub.docker.com/r/sorajez/bunbrowser"