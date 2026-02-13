#!/bin/sh
# =============================================================================
# SCRIPT D'INITIALISATION DES MODÈLES OLLAMA
# =============================================================================
# Ce script est exécuté par le service "ollama-init" au démarrage.
# Il télécharge automatiquement tous les modèles nécessaires.
#
# Fonctionnement :
#   1. Attend qu'Ollama soit accessible (healthcheck)
#   2. Pour chaque modèle de la liste :
#      - Vérifie s'il est déjà téléchargé
#      - Le télécharge si absent
#   3. Affiche un résumé final
#
# Les modèles sont stockés dans le volume Docker "ollama_data"
# et persistent entre les redémarrages.
# =============================================================================

# Couleurs pour les messages (rend la sortie plus lisible)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color (reset)

# URL de base de l'API Ollama (définie dans docker-compose.yml)
OLLAMA_URL="${OLLAMA_BASE_URL:-http://ollama:11434}"

# =============================================================================
# LISTE DES MODÈLES À TÉLÉCHARGER
# =============================================================================
# Ajoutez ou supprimez des modèles en modifiant cette liste.
# Format : "nom_du_modele:tag"
#
# MODÈLES LLM (Language Models) :
#   - llama3.1:latest    → Meta Llama 3.1 8B  (~4.7 Go) - Polyvalent, excellent rapport qualité/taille
#   - llama3:8b          → Meta Llama 3 8B    (~4.7 Go) - Version précédente, très stable
#   - glm-4.7-flash      → GLM-4 Flash        (~3.0 Go) - Rapide, bon pour les tâches simples
#   - qwen3-vl:8b        → Qwen3 Vision-Lang  (~5.0 Go) - Multimodal (texte + images)
#
# MODÈLES D'EMBEDDING :
#   - nomic-embed-text   → Nomic Embed Text    (~274 Mo) - Excellent rapport qualité/taille, 8192 tokens
#   - bge-m3:latest      → BGE-M3 Full         (~1.2 Go) - Multilingue, dense + sparse
#   - bge-m3:567m        → BGE-M3 Compact      (~567 Mo) - Version plus légère de BGE-M3
#   - embeddinggemma:300m→ Embedding Gemma      (~300 Mo) - Léger et performant (Google)
#
# NOTE : La taille indiquée est approximative et peut varier selon la quantification.
# =============================================================================

MODELS="
llama3.1:latest
llama3:8b
glm-4.7-flash:latest
qwen3-vl:8b
nomic-embed-text:latest
bge-m3:latest
bge-m3:567m
embeddinggemma:300m
"

# =============================================================================
# FONCTION : Attendre qu'Ollama soit prêt
# =============================================================================
# Effectue des tentatives de connexion toutes les 5 secondes
# pendant un maximum de 120 secondes (24 tentatives).
# =============================================================================
wait_for_ollama() {
    echo "${BLUE}========================================${NC}"
    echo "${BLUE}  Attente du démarrage d'Ollama...${NC}"
    echo "${BLUE}========================================${NC}"

    MAX_RETRIES=24      # Nombre maximum de tentatives
    RETRY_INTERVAL=5    # Secondes entre chaque tentative
    RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Tente un appel HTTP vers Ollama
        if curl -s -f "${OLLAMA_URL}/" > /dev/null 2>&1; then
            echo "${GREEN}✓ Ollama est prêt !${NC}"
            return 0
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "${YELLOW}  Tentative ${RETRY_COUNT}/${MAX_RETRIES} - Ollama pas encore prêt...${NC}"
        sleep $RETRY_INTERVAL
    done

    # Si on arrive ici, Ollama n'a pas répondu à temps
    echo "${RED}✗ ERREUR : Ollama n'est pas accessible après $((MAX_RETRIES * RETRY_INTERVAL)) secondes${NC}"
    echo "${RED}  Vérifiez les logs : docker logs ollama${NC}"
    return 1
}

# =============================================================================
# FONCTION : Télécharger un modèle
# =============================================================================
# Paramètre : $1 = nom du modèle (ex: "llama3.1:latest")
#
# L'API Ollama /api/pull déclenche le téléchargement d'un modèle.
# Le paramètre "stream: false" désactive le streaming pour simplifier
# la gestion de la réponse (on attend juste le résultat final).
# =============================================================================
pull_model() {
    MODEL_NAME=$1

    echo ""
    echo "${BLUE}────────────────────────────────────────${NC}"
    echo "${BLUE}  Téléchargement : ${MODEL_NAME}${NC}"
    echo "${BLUE}────────────────────────────────────────${NC}"

    # Vérifie d'abord si le modèle est déjà présent
    # L'API /api/show retourne les infos d'un modèle s'il existe
    if curl -s -f "${OLLAMA_URL}/api/show" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${MODEL_NAME}\"}" > /dev/null 2>&1; then
        echo "${GREEN}  ✓ ${MODEL_NAME} est déjà téléchargé, on passe au suivant.${NC}"
        return 0
    fi

    echo "${YELLOW}  ⬇ Téléchargement en cours... (cela peut prendre plusieurs minutes)${NC}"

    # Lance le téléchargement via l'API Ollama
    # --max-time 3600 = timeout de 1 heure (les gros modèles sont longs à DL)
    RESPONSE=$(curl -s --max-time 3600 \
        "${OLLAMA_URL}/api/pull" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${MODEL_NAME}\", \"stream\": false}")

    # Vérifie le résultat du téléchargement
    # La réponse contient "success" si tout s'est bien passé
    if echo "$RESPONSE" | grep -q "success"; then
        echo "${GREEN}  ✓ ${MODEL_NAME} téléchargé avec succès !${NC}"
        return 0
    else
        echo "${RED}  ✗ Erreur lors du téléchargement de ${MODEL_NAME}${NC}"
        echo "${RED}    Réponse : ${RESPONSE}${NC}"
        return 1
    fi
}

# =============================================================================
# PROGRAMME PRINCIPAL
# =============================================================================

echo ""
echo "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║     INITIALISATION DES MODÈLES OLLAMA               ║${NC}"
echo "${BLUE}║     Stack RAG : Ollama + Qdrant + AnythingLLM       ║${NC}"
echo "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Étape 1 : Attendre qu'Ollama soit opérationnel
wait_for_ollama
if [ $? -ne 0 ]; then
    echo "${RED}Abandon : impossible de se connecter à Ollama.${NC}"
    exit 1
fi

# Étape 2 : Télécharger chaque modèle de la liste
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_COUNT=0

for MODEL in $MODELS; do
    # Ignore les lignes vides
    [ -z "$MODEL" ] && continue

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    pull_model "$MODEL"
    RESULT=$?

    if [ $RESULT -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# Étape 3 : Afficher le résumé
echo ""
echo "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║                  RÉSUMÉ                              ║${NC}"
echo "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo "${BLUE}║${NC}  Total des modèles    : ${TOTAL_COUNT}                           ${BLUE}║${NC}"
echo "${BLUE}║${NC}  ${GREEN}✓ Succès / Déjà prêt : ${SUCCESS_COUNT}${NC}                           ${BLUE}║${NC}"
echo "${BLUE}║${NC}  ${RED}✗ Échecs             : ${FAIL_COUNT}${NC}                           ${BLUE}║${NC}"
echo "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Étape 4 : Lister tous les modèles installés
echo "${BLUE}Modèles actuellement disponibles sur Ollama :${NC}"
curl -s "${OLLAMA_URL}/api/tags" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | while read -r name; do
    echo "  ${GREEN}→ ${name}${NC}"
done

echo ""
echo "${GREEN}Initialisation terminée ! Le conteneur ollama-init va s'arrêter.${NC}"
echo ""

# Code de sortie : 0 si tous les modèles ont réussi, 1 sinon
if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi
exit 0
