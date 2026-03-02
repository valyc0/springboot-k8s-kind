#!/bin/bash
set -e

# =============================================================================
# SCRIPT DI ELIMINAZIONE CLUSTER KIND
# =============================================================================
# Questo script elimina il cluster kind e rimuove i file yaml generati
# durante il setup.
# =============================================================================


# -----------------------------------------------------------------------------
# STEP 1: VERIFICA CHE IL CLUSTER ESISTA
# -----------------------------------------------------------------------------
# "kind get clusters" restituisce i nomi dei cluster attivi.
# Se "kind" non è nell'elenco, non c'è nulla da eliminare.

if ! kind get clusters 2>/dev/null | grep -q "^kind$"; then
  echo ">>> Nessun cluster 'kind' attivo. Nulla da eliminare."
  exit 0
fi


# -----------------------------------------------------------------------------
# STEP 2: ELIMINA IL CLUSTER
# -----------------------------------------------------------------------------
# kind delete cluster rimuove il container Docker che fa da nodo
# e pulisce il contesto kubectl associato.

echo ">>> Eliminazione cluster kind..."
kind delete cluster
echo "    Cluster eliminato."


# -----------------------------------------------------------------------------
# STEP 3: RIMUOVE I FILE YAML GENERATI
# -----------------------------------------------------------------------------
# I file yaml vengono rigenerati ad ogni esecuzione di setup-cluster.sh,
# quindi non ha senso tenerli dopo aver distrutto il cluster.

echo ">>> Rimozione file yaml generati..."
rm -f newConfig.yaml test-deployment.yaml test-deployment1.yaml
echo "    File rimossi."


echo ""
echo "=== Cluster eliminato correttamente. ==="
echo "    Per ricrearlo esegui: ./setup-cluster.sh"
