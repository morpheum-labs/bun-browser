#!/usr/bin/env bash
# Build the bun-browser Docker image (Chrome + noVNC + daemon).
# The image runs `bun install` + `bun run build` from repo source (not npm; bun-browser is not published there).
# Two Dockerfiles: nopass (open noVNC) or passvnc (nginx basic auth + entrance.sh).
#
# Usage:
#   bash docker-build.sh
#   bash docker-build.sh [tag]
#   bash docker-build.sh [--push] [tag]
#   bash docker-build.sh --variant nopass|passvnc [--push] [tag]
#
# Default tag (when [tag] omitted): short git commit hash (git rev-parse --short HEAD).
#
# Non-interactive (CI): set --variant or DOCKER_VARIANT=nopass|passvnc
#
# Environment — build:
#   IMAGE_NAME          Base image name (default: bun-browser). Built as ${IMAGE_NAME}-${variant}:${tag}
#   DOCKER_VARIANT      nopass | passvnc — skips menu when set
#   SKIP_BUILD          If 1, skip build and only tag/push existing local image
#
# Environment — push (--push):
#   DOCKER_SPACE_SORA   Registry username or full path (e.g. myuser or ghcr.io/myorg)
#   DOCKER_TOKEN_SORA   Registry password or token (stdin to docker login)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

IMAGE_NAME="bunbrowser"
PUSH=0
TAG=""
VARIANT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1; shift ;;
    --variant)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --variant requires nopass or passvnc" >&2
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
    echo "Error: non-interactive shell requires --variant nopass|passvnc or DOCKER_VARIANT=nopass|passvnc" >&2
    exit 1
  fi
  echo ""
  echo "bun-browser Docker build — choose variant:"
  echo "  1) nopass   — noVNC without auth (Dockerfile: ./nopass)"
  echo "  2) passvnc  — noVNC + nginx basic auth (Dockerfile: ./passvnc, needs entrance.sh)"
  read -r -p "Enter 1 or 2 [1]: " choice
  case "${choice:-1}" in
    2|passvnc) VARIANT="passvnc" ;;
    1|nopass|"") VARIANT="nopass" ;;
    *)
      echo "Error: invalid choice" >&2
      exit 1
      ;;
  esac
fi

case "${VARIANT}" in
  nopass|passvnc) ;;
  *)
    echo "Error: variant must be nopass or passvnc, got: ${VARIANT}" >&2
    exit 1
    ;;
esac

DOCKERFILE="${VARIANT}"
if [[ ! -f "${ROOT}/${DOCKERFILE}" ]]; then
  echo "Error: Dockerfile not found: ${ROOT}/${DOCKERFILE}" >&2
  exit 1
fi

if [[ "${VARIANT}" == "passvnc" && ! -f "${ROOT}/entrance.sh" ]]; then
  echo "Error: passvnc build requires ./entrance.sh" >&2
  exit 1
fi

# Extension and dist/ are built inside the Docker image (see nopass / passvnc Dockerfiles).

# Version tag = git commit (short hash) unless overridden on the command line
if [[ -z "${TAG}" ]]; then
  TAG="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo latest)"
fi

LOCAL_IMAGE="${IMAGE_NAME}-${VARIANT}:${TAG}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building ${LOCAL_IMAGE} (Dockerfile=${DOCKERFILE}, tag=${TAG})..."
  docker build -f "${DOCKERFILE}" -t "${LOCAL_IMAGE}" "${ROOT}"
  echo "OK: ${LOCAL_IMAGE}"
fi

if [[ "${PUSH}" != "1" ]]; then
  exit 0
fi

DOCKER_REGISTRY="${DOCKER_SPACE_SORA:-}"
DOCKER_TOKEN="${DOCKER_TOKEN_SORA:-}"

if [[ -z "${DOCKER_REGISTRY}" || -z "${DOCKER_TOKEN}" ]]; then
  echo "Error: --push requires DOCKER_SPACE_SORA and DOCKER_TOKEN_SORA" >&2
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