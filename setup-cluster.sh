#!/bin/bash
set -e  # Blocca lo script se un comando fallisce

# =============================================================================
# SCRIPT DI SETUP CLUSTER KUBERNETES (kind) CON INGRESS NGINX
# =============================================================================
# Questo script:
#   1. Crea un cluster kind con porte mappate verso l'host
#   2. Installa ingress-nginx come controller per le rotte HTTP
#   3. Deployia due applicazioni di test con Service e Ingress
# =============================================================================


# -----------------------------------------------------------------------------
# STEP 1: CREARE IL FILE DI CONFIGURAZIONE DEL CLUSTER
# -----------------------------------------------------------------------------
# kind usa un file YAML per configurare il cluster prima di crearlo.
# Qui definiamo:
#   - Un solo nodo con ruolo "control-plane" (cluster single-node)
#   - L'etichetta "ingress-ready=true" necessaria perché ingress-nginx
#     sappia su quale nodo girare (tramite nodeSelector)
#   - Il mapping delle porte: la porta 80 del container (nginx) viene
#     esposta sulla porta 9800 della macchina host, e la 443 sulla 44300

echo ">>> [1/5] Creazione file di configurazione del cluster..."

cat <<EOF > ./newConfig.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kind
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 9800
    protocol: TCP
  - containerPort: 443
    hostPort: 44300
    protocol: TCP
- role: worker   # worker 1: esegue i pod applicativi
- role: worker   # worker 2: esegue i pod applicativi (ridondanza e bilanciamento)
EOF


# -----------------------------------------------------------------------------
# STEP 2: CREARE IL CLUSTER
# -----------------------------------------------------------------------------
# kind crea un nodo Kubernetes dentro un container Docker.
# Al termine imposta automaticamente il contesto kubectl su "kind-kind".

echo ">>> [2/5] Creazione del cluster kind..."
kind create cluster --config newConfig.yaml


# -----------------------------------------------------------------------------
# STEP 3: INSTALLARE INGRESS-NGINX
# -----------------------------------------------------------------------------
# ingress-nginx è il controller che gestisce le risorse "Ingress" di Kubernetes.
# Senza di esso, le regole Ingress esistono ma non vengono applicate.
# Il manifest specifico per kind configura anche il toleration e il nodeSelector
# necessari per girare sul nodo control-plane con il label "ingress-ready=true".
#
# Dopo l'apply, aspettiamo che il pod del controller sia in stato "Ready"
# prima di procedere, altrimenti gli Ingress creati subito dopo potrebbero
# non essere registrati correttamente.

echo ">>> [3/5] Installazione ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "    Attendo che il controller ingress-nginx sia pronto..."
# sleep necessario: i pod impiegano qualche secondo ad essere schedulati
# prima che kubectl wait possa trovarli
sleep 5
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Attesa aggiuntiva: il webhook di admission di ingress-nginx impiega
# qualche secondo in più per essere operativo dopo che il pod è Ready.
# Senza questo sleep la creazione degli Ingress fallisce con "connection refused".
sleep 10


# -----------------------------------------------------------------------------
# STEP 4: DEPLOY APPLICAZIONE 1 (test-app → /app)
# -----------------------------------------------------------------------------
# Creiamo tre risorse Kubernetes in un unico file YAML (separate da ---):
#
#   Pod:     l'unità base che esegue il container. Usiamo "hashicorp/http-echo"
#            che risponde a qualsiasi richiesta HTTP con il testo specificato.
#
#   Service: espone il Pod all'interno del cluster su una porta stabile.
#            Il selector "app: test-app" collega il Service al Pod.
#            Senza il Service, l'Ingress non sa dove mandare il traffico.
#
#   Ingress: regola di routing HTTP gestita da ingress-nginx.
#            Dice: "tutte le richieste con path /app → manda a test-service:5678"
#            ingressClassName: nginx specifica quale controller deve gestirlo.

echo ">>> [4/5] Deploy applicazione 1 (path: /app)..."

cat <<EOF > ./test-deployment.yaml
kind: Pod
apiVersion: v1
metadata:
  name: test-app
  labels:
    app: test-app        # etichetta usata dal Service per trovare il Pod
spec:
  containers:
  - name: test-app
    image: hashicorp/http-echo:latest
    args:
    - "-text=The test has been successful!"
---
kind: Service
apiVersion: v1
metadata:
  name: test-service
spec:
  selector:
    app: test-app        # collega il Service al Pod con questo label
  ports:
  - port: 5678           # porta interna al cluster su cui ascolta il Service
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
spec:
  ingressClassName: nginx  # usa il controller ingress-nginx installato prima
  rules:
  - http:
      paths:
      - pathType: Prefix
        path: "/app"       # tutte le richieste che iniziano con /app
        backend:
          service:
            name: test-service
            port:
              number: 5678
EOF

kubectl apply -f test-deployment.yaml


# -----------------------------------------------------------------------------
# STEP 5: DEPLOY APPLICAZIONE 2 (test-app1 → /app1)
# -----------------------------------------------------------------------------
# Stessa struttura dell'applicazione 1, ma con nome, label e path diversi.
# Dimostra che ingress-nginx può gestire più applicazioni sullo stesso cluster
# differenziate solo dal path URL.

echo ">>> [5/5] Deploy applicazione 2 (path: /app1)..."

cat <<EOF > ./test-deployment1.yaml
kind: Pod
apiVersion: v1
metadata:
  name: test-app1
  labels:
    app: test-app1
spec:
  containers:
  - name: test-app1
    image: hashicorp/http-echo:latest
    args:
    - "-text=The test has been successful1111111!"
---
kind: Service
apiVersion: v1
metadata:
  name: test-service1
spec:
  selector:
    app: test-app1
  ports:
  - port: 5678
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress1
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - pathType: Prefix
        path: "/app1"
        backend:
          service:
            name: test-service1
            port:
              number: 5678
EOF

kubectl apply -f test-deployment1.yaml


# -----------------------------------------------------------------------------
# VERIFICA FINALE
# -----------------------------------------------------------------------------
# Aspettiamo che entrambi i Pod siano in stato Running/Ready,
# poi facciamo due curl per verificare che le rotte HTTP funzionino.

echo ""
echo ">>> Attendo che i pod siano pronti..."
kubectl wait --for=condition=ready pod/test-app pod/test-app1 --timeout=60s

# Attesa aggiuntiva: ingress-nginx impiega qualche secondo a sincronizzare
# le regole Ingress dopo la loro creazione. Senza questo sleep il curl
# restituisce 503 anche se i pod sono già Running.
echo "    Attendo sincronizzazione regole ingress..."
sleep 8

echo ""
echo ">>> Test curl localhost:9800/app"
curl -s localhost:9800/app

echo ""
echo ">>> Test curl localhost:9800/app1"
curl -s localhost:9800/app1

echo ""
echo "=== Setup completato! ==="
echo "    /app  → http://localhost:9800/app"
echo "    /app1 → http://localhost:9800/app1"


# -----------------------------------------------------------------------------
# STATO DEL CLUSTER
# -----------------------------------------------------------------------------
# Riepilogo visivo di tutte le risorse create nel namespace default
# e nel namespace ingress-nginx.

echo ""
echo ">>> Stato dei nodi del cluster:  [kubectl get nodes -o wide]"
# Mostra i 3 nodi: 1 control-plane + 2 worker con il loro stato Ready/NotReady
kubectl get nodes -o wide

echo ""
echo ">>> Stato dei Pod (namespace default):  [kubectl get pods -o wide]"
# Mostra nome, stato (Running/Pending/Error), numero di restart e età
kubectl get pods -o wide

echo ""
echo ">>> Stato dei Service (namespace default):  [kubectl get services]"
# Mostra i service con le porte esposte internamente al cluster
kubectl get services

echo ""
echo ">>> Stato degli Ingress (namespace default):  [kubectl get ingress]"
# Mostra le regole di routing HTTP con host e path configurati
kubectl get ingress

echo ""
echo ">>> Stato del controller ingress-nginx:  [kubectl get pods -n ingress-nginx]"
# Verifica che il controller nginx sia Running nel suo namespace dedicato
kubectl get pods -n ingress-nginx

echo ""
echo ">>> Descrizione dettagliata pod test-app:  [kubectl describe pod test-app]"
# Utile per diagnosticare problemi: mostra eventi, nodo assegnato, IP, volumi
kubectl describe pod test-app

echo ""
echo ">>> Descrizione dettagliata pod test-app1:  [kubectl describe pod test-app1]"
kubectl describe pod test-app1
