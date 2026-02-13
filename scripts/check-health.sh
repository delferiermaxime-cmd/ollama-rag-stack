#!/bin/bash
# =============================================================================
# SCRIPT DE VÉRIFICATION DE SANTÉ DE LA STACK
# =============================================================================
# Ce script vérifie que tous les services sont opérationnels.
# Utile pour le débogage et la vérification post-déploiement.
#
# Utilisation :
#   chmod +x scripts/check-health.sh
#   ./scripts/check-health.sh
# =============================================================================

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║       VÉRIFICATION DE SANTÉ - Stack RAG              ║${NC}"
echo "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Charge les variables d'environnement si le fichier .env existe
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Ports par défaut
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
QDRANT_REST_PORT="${QDRANT_REST_PORT:-6333}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"

ERRORS=0

# ---------------------------------------------------------------------------
# Vérification 1 : Docker est-il installé et en cours d'exécution ?
# ---------------------------------------------------------------------------
echo "${BLUE}[1/5] Vérification de Docker...${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "  ${GREEN}✓ Docker installé : ${DOCKER_VERSION}${NC}"
else
    echo "  ${RED}✗ Docker n'est pas installé !${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ---------------------------------------------------------------------------
# Vérification 2 : Les conteneurs sont-ils en cours d'exécution ?
# ---------------------------------------------------------------------------
echo ""
echo "${BLUE}[2/5] État des conteneurs...${NC}"
for CONTAINER in ollama qdrant anythingllm; do
    STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER 2>/dev/null)
    HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER 2>/dev/null)

    if [ "$STATUS" = "running" ]; then
        if [ "$HEALTH" = "healthy" ]; then
            echo "  ${GREEN}✓ ${CONTAINER} : running (healthy)${NC}"
        elif [ "$HEALTH" = "starting" ]; then
            echo "  ${YELLOW}⟳ ${CONTAINER} : running (starting...)${NC}"
        else
            echo "  ${YELLOW}⚠ ${CONTAINER} : running (health: ${HEALTH:-unknown})${NC}"
        fi
    else
        echo "  ${RED}✗ ${CONTAINER} : ${STATUS:-not found}${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

# ---------------------------------------------------------------------------
# Vérification 3 : Les APIs sont-elles accessibles ?
# ---------------------------------------------------------------------------
echo ""
echo "${BLUE}[3/5] Accessibilité des APIs...${NC}"

# Ollama
if curl -sf "http://localhost:${OLLAMA_PORT}/" > /dev/null 2>&1; then
    echo "  ${GREEN}✓ Ollama API      : http://localhost:${OLLAMA_PORT}${NC}"
else
    echo "  ${RED}✗ Ollama API      : http://localhost:${OLLAMA_PORT} (inaccessible)${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Qdrant
if curl -sf "http://localhost:${QDRANT_REST_PORT}/healthz" > /dev/null 2>&1; then
    echo "  ${GREEN}✓ Qdrant API      : http://localhost:${QDRANT_REST_PORT}${NC}"
else
    echo "  ${RED}✗ Qdrant API      : http://localhost:${QDRANT_REST_PORT} (inaccessible)${NC}"
    ERRORS=$((ERRORS + 1))
fi

# AnythingLLM
if curl -sf "http://localhost:${ANYTHINGLLM_PORT}/api/ping" > /dev/null 2>&1; then
    echo "  ${GREEN}✓ AnythingLLM     : http://localhost:${ANYTHINGLLM_PORT}${NC}"
else
    echo "  ${RED}✗ AnythingLLM     : http://localhost:${ANYTHINGLLM_PORT} (inaccessible)${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ---------------------------------------------------------------------------
# Vérification 4 : Modèles Ollama installés
# ---------------------------------------------------------------------------
echo ""
echo "${BLUE}[4/5] Modèles Ollama installés...${NC}"
MODELS_RESPONSE=$(curl -s "http://localhost:${OLLAMA_PORT}/api/tags" 2>/dev/null)

if [ -n "$MODELS_RESPONSE" ]; then
    echo "$MODELS_RESPONSE" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | while read -r name; do
        SIZE=$(echo "$MODELS_RESPONSE" | grep -o "\"name\":\"${name}\"[^}]*\"size\":[0-9]*" | grep -o '"size":[0-9]*' | head -1 | sed 's/"size"://')
        if [ -n "$SIZE" ]; then
            SIZE_GB=$(echo "scale=2; $SIZE / 1073741824" | bc 2>/dev/null || echo "?")
            echo "  ${GREEN}→ ${name} (${SIZE_GB} Go)${NC}"
        else
            echo "  ${GREEN}→ ${name}${NC}"
        fi
    done
else
    echo "  ${YELLOW}⚠ Impossible de récupérer la liste des modèles${NC}"
fi

# ---------------------------------------------------------------------------
# Vérification 5 : Collections Qdrant
# ---------------------------------------------------------------------------
echo ""
echo "${BLUE}[5/5] Collections Qdrant...${NC}"
COLLECTIONS=$(curl -s "http://localhost:${QDRANT_REST_PORT}/collections" 2>/dev/null)

if [ -n "$COLLECTIONS" ]; then
    COUNT=$(echo "$COLLECTIONS" | grep -o '"name"' | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        echo "  ${GREEN}${COUNT} collection(s) trouvée(s)${NC}"
        echo "$COLLECTIONS" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | while read -r name; do
            echo "    ${GREEN}→ ${name}${NC}"
        done
    else
        echo "  ${YELLOW}Aucune collection (normal au premier lancement)${NC}"
    fi
else
    echo "  ${YELLOW}⚠ Impossible de se connecter à Qdrant${NC}"
fi

# ---------------------------------------------------------------------------
# Résumé final
# ---------------------------------------------------------------------------
echo ""
echo "${BLUE}══════════════════════════════════════════════════════${NC}"
if [ $ERRORS -eq 0 ]; then
    echo "${GREEN}  ✓ TOUT EST OPÉRATIONNEL !${NC}"
    echo ""
    echo "  Interface AnythingLLM : ${GREEN}http://localhost:${ANYTHINGLLM_PORT}${NC}"
    echo "  API Ollama            : ${GREEN}http://localhost:${OLLAMA_PORT}${NC}"
    echo "  API Qdrant            : ${GREEN}http://localhost:${QDRANT_REST_PORT}${NC}"
    echo "  Dashboard Qdrant      : ${GREEN}http://localhost:${QDRANT_REST_PORT}/dashboard${NC}"
else
    echo "${RED}  ✗ ${ERRORS} ERREUR(S) DÉTECTÉE(S)${NC}"
    echo "  Consultez les logs : docker compose logs"
fi
echo "${BLUE}══════════════════════════════════════════════════════${NC}"
echo ""
