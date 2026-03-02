#!/bin/bash
set -euo pipefail

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5000"

echo ">>> Verifico se il container registry esiste..."
if ! docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
  echo ">>> Creo il registry locale (${REGISTRY_NAME}) su porta ${REGISTRY_PORT}..."
  docker run -d \
    --restart=always \
    -p "${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2
else
  echo ">>> Registry già presente: provo ad avviarlo se fermo..."
  docker start "${REGISTRY_NAME}" >/dev/null 2>&1 || true
fi

echo ">>> Collego il registry alla rete Docker di kind..."
if docker network inspect kind >/dev/null 2>&1; then
  docker network connect kind "${REGISTRY_NAME}" 2>/dev/null || true
else
  echo "!!! Rete 'kind' non trovata. Crea prima il cluster kind."
fi

echo ">>> Stato registry:"
docker ps --filter "name=${REGISTRY_NAME}" --format 'name={{.Names}} | status={{.Status}} | ports={{.Ports}}'

echo ""
echo "Usa questa immagine nel deployment Kubernetes:"
echo "  image: ${REGISTRY_NAME}:${REGISTRY_PORT}/spring-boot-app:0.0.1"