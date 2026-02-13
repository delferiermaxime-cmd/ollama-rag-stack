#!/bin/bash
# =============================================================================
# SCRIPT D'ARRÊT ET DE NETTOYAGE
# =============================================================================
# Ce script propose plusieurs options pour arrêter et/ou nettoyer la stack.
#
# Utilisation :
#   chmod +x scripts/stop-and-clean.sh
#   ./scripts/stop-and-clean.sh
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║       ARRÊT & NETTOYAGE - Stack RAG                  ║${NC}"
echo "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Choisissez une option :"
echo ""
echo "  ${GREEN}1)${NC} Arrêter les services (conserver les données)"
echo "  ${YELLOW}2)${NC} Arrêter et supprimer les conteneurs"
echo "  ${RED}3)${NC} TOUT supprimer (conteneurs + volumes + données)"
echo "  ${BLUE}4)${NC} Annuler"
echo ""
read -p "  Votre choix [1-4] : " CHOICE

case $CHOICE in
    1)
        echo ""
        echo "${YELLOW}Arrêt des services...${NC}"
        docker compose stop
        echo "${GREEN}✓ Services arrêtés. Les données sont conservées.${NC}"
        echo "  Pour redémarrer : docker compose start"
        ;;
    2)
        echo ""
        echo "${YELLOW}Suppression des conteneurs...${NC}"
        docker compose down
        echo "${GREEN}✓ Conteneurs supprimés. Les volumes (données) sont conservés.${NC}"
        echo "  Pour relancer : docker compose up -d"
        ;;
    3)
        echo ""
        echo "${RED}⚠  ATTENTION : Cela supprimera TOUTES les données :${NC}"
        echo "${RED}   - Modèles Ollama téléchargés (~20-40 Go)${NC}"
        echo "${RED}   - Collections et index Qdrant${NC}"
        echo "${RED}   - Workspaces et documents AnythingLLM${NC}"
        echo ""
        read -p "  Êtes-vous sûr ? (oui/non) : " CONFIRM
        if [ "$CONFIRM" = "oui" ]; then
            echo "${RED}Suppression complète en cours...${NC}"
            docker compose down -v --remove-orphans
            echo "${GREEN}✓ Tout a été supprimé.${NC}"
            echo "  Pour repartir de zéro : docker compose up -d"
        else
            echo "${GREEN}Annulé.${NC}"
        fi
        ;;
    4)
        echo "${GREEN}Annulé.${NC}"
        ;;
    *)
        echo "${RED}Choix invalide.${NC}"
        ;;
esac
echo ""
