#!/bin/bash
set -euo pipefail

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5000"
IMAGE_NAME="spring-boot-app"
IMAGE_TAG="0.0.1"
PUSH_REGISTRY_HOST="localhost"

LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
REGISTRY_IMAGE="${PUSH_REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"

echo ">>> Verifico che il registry locale sia attivo..."
if ! docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
  echo "!!! Registry ${REGISTRY_NAME} non attivo. Esegui prima: ./create-registry.sh"
  exit 1
fi

echo ">>> Build immagine Docker locale: ${LOCAL_IMAGE}"
docker build -t "${LOCAL_IMAGE}" .

echo ">>> Tag immagine per il registry locale: ${REGISTRY_IMAGE}"
docker tag "${LOCAL_IMAGE}" "${REGISTRY_IMAGE}"

echo ">>> Push immagine nel registry locale"
docker push "${REGISTRY_IMAGE}"

echo ">>> Verifico che l'immagine sia pubblicata nel registry"
curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog" || true

echo ""
echo "Push completato."
echo "Image pushata come: ${REGISTRY_IMAGE}"
echo "Image da usare in Kubernetes: ${REGISTRY_NAME}:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"