# Spring Boot 3 su Kind — Registry locale + ConfigMap esterna

Applicazione REST Spring Boot 3 deployata su un cluster [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker).  
L'immagine viene pubblicata su un **registry Docker locale** e la configurazione del profilo `prod` viene iniettata tramite una **ConfigMap** Kubernetes montata come file esterno.

---

## Architettura

```
┌─────────────────────────────────────────────────────────┐
│  Host                                                   │
│                                                         │
│  localhost:9800  ──►  ingress-nginx  ──►  spring-boot   │
│                                              pod        │
│  kind-registry:5000                                     │
│  (Docker container registry)                            │
└─────────────────────────────────────────────────────────┘
```

Il cluster Kind espone la porta `80` del nodo control-plane sulla porta `9800` dell'host.  
Il registry locale è un container Docker (`kind-registry`) raggiungibile dai nodi Kind tramite la rete Docker `kind`.

---

## Struttura del progetto

```
spring-boot-app/
├── Dockerfile                  # Build multi-stage (Maven → JRE 21)
├── pom.xml
├── create-registry.sh          # Crea/avvia il registry Docker locale
├── push-to-registry.sh         # Build Docker + push al registry locale
├── setup-cluster.sh            # Crea il cluster Kind + installa ingress-nginx
├── deploy-kind.sh              # Orchestra l'intero deploy (registry → image → k8s)
├── delete-cluster.sh           # Elimina il cluster Kind
├── k8s/
│   └── spring-boot-registry.yaml   # ConfigMap + Deployment + Service + Ingress
└── src/
    └── main/
        ├── java/…/AppController.java   # Endpoint REST
        └── resources/application.yaml  # Config di default
```

---

## Prerequisiti

| Strumento | Note |
|-----------|-------|
| Docker    | Engine attivo |
| `kind`    | ≥ v0.20 |
| `kubectl` | configurato sull'utente corrente |
| Maven     | non necessario in locale (la build avviene dentro Docker) |

---

## Quick start — deploy completo

```bash
# 1. Crea il cluster Kind con ingress-nginx
./setup-cluster.sh

# 2. Esegui il deploy completo
./deploy-kind.sh
```

`deploy-kind.sh` esegue in sequenza:

1. **`create-registry.sh`** — crea (o riavvia) il container `kind-registry` sulla porta `5000` e lo collega alla rete Docker `kind`
2. **`push-to-registry.sh`** — esegue `docker build` e pubblica `spring-boot-app:0.0.1` su `localhost:5000`
3. Configura i nodi Kind per il pull HTTP dal registry locale (aggiorna `containerd`)
4. `kubectl apply -f k8s/spring-boot-registry.yaml`
5. Attende il rollout e verifica l'endpoint

---

## Endpoint REST

| Metodo | Path | Descrizione |
|--------|------|-------------|
| `GET` | `/api/hello` | Ritorna `appName`, messaggio e timestamp |

### Risposta di esempio

```json
{
  "message": "Hello from Spring Boot 3 on Kind",
  "appName": "spring-kind-prod",
  "timestamp": "2026-03-02T10:00:00.000Z"
}
```

Raggiungibile dall'host tramite Ingress:

```bash
curl localhost:9800/spring/api/hello
```

---

## Configurazione esterna (profilo `prod`)

Spring Boot carica un `application-prod.yaml` esterno montato nel container da una ConfigMap Kubernetes.

Il Deployment imposta queste variabili d'ambiente:

```
SPRING_PROFILES_ACTIVE=prod
SPRING_CONFIG_ADDITIONAL_LOCATION=file:/config/
```

Il file montato in `/config/application-prod.yaml` (definito in `k8s/spring-boot-registry.yaml`) sovrascrive `app.name` con il valore `spring-kind-prod`.

---

## Risorse Kubernetes (`k8s/spring-boot-registry.yaml`)

| Risorsa | Nome | Descrizione |
|---------|------|-------------|
| `ConfigMap` | `spring-boot-prod-config` | Contiene `application-prod.yaml` |
| `Deployment` | `spring-boot-app` | 1 replica, immagine da registry locale |
| `Service` | `spring-boot-service` | ClusterIP, porta 8080 |
| `Ingress` | `spring-boot-ingress` | Path `/spring(/|$)(.*)` → riscrittura con nginx |

---

## Script disponibili

### `setup-cluster.sh`
Crea il cluster Kind con:
- 1 nodo control-plane (label `ingress-ready=true`, porte `80→9800`, `443→44300`)
- 2 worker node
- Installazione di `ingress-nginx`

### `create-registry.sh`
Avvia il container `kind-registry` (Docker registry v2) sulla porta `5000` e lo collega alla rete `kind`.

### `push-to-registry.sh`
Esegue la build Docker dell'applicazione e pusha l'immagine `spring-boot-app:0.0.1` nel registry locale.

### `deploy-kind.sh`
Orchestratore completo: registry → build/push → configura containerd sui nodi → `kubectl apply` → verifica rollout e endpoint.

### `delete-cluster.sh`
Elimina il cluster Kind.

---

## Comandi utili

```bash
# Stato dei pod
kubectl get pods

# Log dell'applicazione
kubectl logs deployment/spring-boot-app --tail=100

# Verificare che il profilo prod sia attivo
kubectl logs deployment/spring-boot-app --tail=200 | grep "Application started"

# Immagini nel registry locale
curl http://localhost:5000/v2/_catalog

# Eliminare il cluster
./delete-cluster.sh
```

---

## Dockerfile

Build multi-stage: la compilazione Maven avviene in un container `maven:3.9.9-eclipse-temurin-21`, il runtime usa `eclipse-temurin:21-jre` (immagine più leggera).

```dockerfile
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/spring-boot-app-0.0.1-SNAPSHOT.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```
