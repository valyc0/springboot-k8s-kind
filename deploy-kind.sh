#!/bin/bash
set -euo pipefail

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5000"

echo ">>> Avvio/controllo registry locale"
./create-registry.sh

echo ">>> Build e push immagine Spring nel registry"
./push-to-registry.sh

echo ">>> Configuro i nodi kind per pull HTTP dal registry locale"
for node in kind-control-plane kind-worker kind-worker2; do
	docker exec "$node" mkdir -p "/etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}"
	docker exec "$node" /bin/sh -c "cat > /etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}/hosts.toml <<'EOF'
server = \"http://${REGISTRY_NAME}:${REGISTRY_PORT}\"

[host.\"http://${REGISTRY_NAME}:${REGISTRY_PORT}\"]
	capabilities = [\"pull\", \"resolve\", \"push\"]
	skip_verify = true
EOF"
	docker exec "$node" /bin/sh -c 'systemctl restart containerd'
done

echo ">>> Deploy risorse Kubernetes"
kubectl apply -f k8s/spring-boot-registry.yaml

echo ">>> Attendo rollout deployment"
kubectl rollout status deployment/spring-boot-app --timeout=120s

echo ">>> Attendo log startup con app.name"
for i in {1..30}; do
	if kubectl logs deployment/spring-boot-app --tail=200 2>/dev/null | grep -q "Application started with app.name"; then
		break
	fi
	if [[ "$i" -eq 30 ]]; then
		echo "!!! Startup log non trovato entro il timeout"
		exit 1
	fi
	sleep 2
done

echo ""
echo ">>> Log applicazione (deve mostrare app.name da application-prod.yaml)"
kubectl logs deployment/spring-boot-app --tail=100 | grep "Application started with app.name"

echo ""
echo ">>> Test endpoint via ingress (path /spring/api/hello) con retry"
for i in {1..30}; do
	response=$(curl -fsS localhost:9800/spring/api/hello 2>/dev/null || true)
	if echo "$response" | grep -q '"appName"'; then
		echo "$response"
		break
	fi
	if [[ "$i" -eq 30 ]]; then
		echo "!!! Endpoint non pronto entro il timeout"
		exit 1
	fi
	sleep 2
done