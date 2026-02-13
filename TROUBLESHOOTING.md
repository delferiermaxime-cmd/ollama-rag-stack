# 🔧 Guide de Dépannage Exhaustif

> Ce document couvre tous les problèmes connus pouvant survenir lors de l'installation,
> du déploiement et de l'utilisation de la stack RAG (Ollama + Qdrant + AnythingLLM).

---

## 📋 Table des matières

1. [Diagnostic rapide](#-diagnostic-rapide)
2. [Problèmes Docker](#-problèmes-docker)
3. [Problèmes GPU / NVIDIA](#-problèmes-gpu--nvidia)
4. [Problèmes Ollama](#-problèmes-ollama)
5. [Problèmes Qdrant](#-problèmes-qdrant)
6. [Problèmes AnythingLLM](#-problèmes-anythingllm)
7. [Problèmes réseau](#-problèmes-réseau)
8. [Problèmes de performance](#-problèmes-de-performance)
9. [Problèmes multi-utilisateurs](#-problèmes-multi-utilisateurs)
10. [Mises à jour et migrations](#-mises-à-jour-et-migrations)
11. [Procédures de récupération](#-procédures-de-récupération)

---

## 🩺 Diagnostic rapide

Avant tout dépannage, lancez le script de vérification :

```bash
# Linux
./scripts/check-health.sh

# Windows PowerShell — vérifications manuelles
docker compose ps                              # État des conteneurs
curl http://localhost:11434/                    # Ollama répond ?
curl http://localhost:6333/healthz              # Qdrant répond ?
curl http://localhost:3001/api/ping             # AnythingLLM répond ?
```

**Commandes de diagnostic universelles :**

```bash
# État de tous les conteneurs (nom, état, santé, ports)
docker compose ps -a

# Logs des 50 dernières lignes d'un service
docker compose logs --tail=50 ollama
docker compose logs --tail=50 qdrant
docker compose logs --tail=50 anythingllm
docker compose logs --tail=50 ollama-init

# Ressources utilisées par les conteneurs (CPU, RAM, réseau)
docker stats --no-stream

# Espace disque utilisé par Docker
docker system df

# Vérifier la version de Docker Compose
docker compose version
```

---

## 🐳 Problèmes Docker

### 1. "Cannot connect to the Docker daemon"

**Symptôme :** `docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock`

**Cause :** Le service Docker n'est pas démarré.

**Solution Linux :**

```bash
# Démarrer Docker
sudo systemctl start docker

# Activer le démarrage automatique
sudo systemctl enable docker

# Vérifier le statut
sudo systemctl status docker
```

**Solution Windows :**
- Lancez **Docker Desktop** depuis le menu Démarrer
- Attendez que l'icône Docker dans la barre des tâches passe au vert
- Si Docker Desktop ne démarre pas, redémarrez l'ordinateur

---

### 2. "Permission denied" lors de l'exécution de docker

**Symptôme :** `Got permission denied while trying to connect to the Docker daemon socket`

**Cause :** Votre utilisateur n'est pas dans le groupe `docker`.

**Solution :**

```bash
# Ajouter votre utilisateur au groupe docker
sudo usermod -aG docker $USER

# OBLIGATOIRE : se déconnecter puis se reconnecter
# OU appliquer immédiatement dans le terminal courant :
newgrp docker

# Vérifier
docker run hello-world
```

---

### 3. "docker compose" vs "docker-compose" — commande introuvable

**Symptôme :** `docker compose: command not found` ou `docker-compose: command not found`

**Cause :** Docker Compose V1 (avec le tiret) est obsolète. La stack utilise V2 (sans tiret).

**Solution :**

```bash
# Vérifier quelle version est installée
docker compose version     # V2 (correct)
docker-compose --version   # V1 (obsolète)

# Si seul V1 est disponible, mettre à jour Docker Engine :
# Ubuntu/Debian
sudo apt update
sudo apt install -y docker-compose-plugin

# Ou installer manuellement le plugin
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
```

---

### 4. "port is already allocated"

**Symptôme :** `Error starting userland proxy: listen tcp4 0.0.0.0:11434: bind: address already in use`

**Cause :** Un autre processus utilise déjà ce port.

**Solution :**

```bash
# Identifier le processus qui occupe le port
# Linux
sudo lsof -i :11434
sudo lsof -i :6333
sudo lsof -i :3001

# Windows PowerShell
netstat -ano | findstr :11434
netstat -ano | findstr :6333
netstat -ano | findstr :3001

# Option 1 : Arrêter le processus conflictuel
# (souvent un Ollama ou Qdrant installé directement sur l'hôte)
sudo systemctl stop ollama    # Si Ollama est installé en natif sur Linux
# Ou terminer le processus via son PID

# Option 2 : Changer les ports dans .env
OLLAMA_PORT=11435
QDRANT_REST_PORT=6335
ANYTHINGLLM_PORT=3002
```

---

### 5. Conteneur qui redémarre en boucle (restart loop)

**Symptôme :** `docker compose ps` montre un conteneur en statut `Restarting`

**Solution :**

```bash
# 1. Identifier la cause dans les logs
docker compose logs --tail=100 <nom_du_service>

# 2. Causes fréquentes :
#    - Manque de RAM → augmenter la RAM ou réduire les modèles
#    - Fichier de config corrompu → réinitialiser le volume
#    - Port occupé → voir section "port already allocated"

# 3. Réinitialiser un service spécifique
docker compose stop <service>
docker volume rm <volume_du_service>   # ATTENTION : supprime les données
docker compose up -d <service>
```

---

### 6. "no space left on device"

**Symptôme :** `write /var/lib/docker/...: no space left on device`

**Cause :** Disque plein (les modèles LLM occupent ~20-40 Go).

**Solution :**

```bash
# 1. Voir ce qui occupe l'espace Docker
docker system df
docker system df -v  # Détail par image/conteneur/volume

# 2. Nettoyer les ressources Docker inutilisées
# (ATTENTION : supprime les images, conteneurs et caches non utilisés)
docker system prune -a

# 3. Supprimer les modèles Ollama inutilisés
docker exec -it ollama ollama list
docker exec -it ollama ollama rm <modele_inutile>

# 4. Vérifier l'espace disque système
df -h        # Linux
Get-Volume   # Windows PowerShell
```

---

### 7. Problèmes de permissions sur les volumes (Linux)

**Symptôme :** `Permission denied` dans les logs d'un conteneur, ou `UID/GID mismatch`

**Cause :** L'utilisateur dans le conteneur n'a pas accès aux fichiers du volume.

**Solution :**

```bash
# Voir le UID/GID utilisé par le conteneur
docker exec ollama id
docker exec anythingllm id

# Si nécessaire, corriger les permissions du volume
# (remplacez 1000:1000 par le UID:GID affiché ci-dessus)
docker run --rm -v anythingllm_data:/data alpine chown -R 1000:1000 /data
```

---

## 🎮 Problèmes GPU / NVIDIA

### 8. GPU non détecté par Docker (Linux)

**Symptôme :** `docker run --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi` échoue

**Diagnostic pas à pas :**

```bash
# ═══════════════════════════════════════════
# ÉTAPE 1 : Le driver NVIDIA est-il installé ?
# ═══════════════════════════════════════════
nvidia-smi
# Si "command not found" → installer le driver NVIDIA :
sudo apt update
sudo apt install -y nvidia-driver-535   # ou version plus récente
sudo reboot

# ═══════════════════════════════════════════
# ÉTAPE 2 : nvidia-smi fonctionne mais Docker ne voit pas le GPU
# → Le NVIDIA Container Toolkit n'est pas installé
# ═══════════════════════════════════════════

# Installer le toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configurer le runtime Docker
sudo nvidia-ctk runtime configure --runtime=docker

# OBLIGATOIRE : redémarrer Docker
sudo systemctl restart docker

# ═══════════════════════════════════════════
# ÉTAPE 3 : Tester
# ═══════════════════════════════════════════
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

---

### 9. GPU non détecté après une mise à jour du noyau Linux

**Symptôme :** `nvidia-smi` retourne `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver`

**Cause :** Une mise à jour du noyau (`apt upgrade` ou `apt dist-upgrade`) a cassé la compatibilité avec le driver NVIDIA. Le module noyau NVIDIA doit être recompilé pour le nouveau noyau.

**Solution :**

```bash
# ═══════════════════════════════════════════
# OPTION A : Réinstaller le driver (recommandé)
# ═══════════════════════════════════════════
# Identifier le driver installé
dpkg -l | grep nvidia-driver

# Réinstaller (remplacez 535 par votre version)
sudo apt install --reinstall nvidia-driver-535
sudo reboot

# ═══════════════════════════════════════════
# OPTION B : Utiliser DKMS pour recompiler automatiquement
# ═══════════════════════════════════════════
# DKMS recompile le module NVIDIA à chaque mise à jour du noyau
sudo apt install -y dkms
sudo dkms autoinstall
sudo reboot

# ═══════════════════════════════════════════
# OPTION C : Revenir à l'ancien noyau (temporaire)
# ═══════════════════════════════════════════
# Lister les noyaux disponibles
grep -i "menuentry" /boot/grub/grub.cfg | head -20

# Redémarrer et sélectionner l'ancien noyau dans le menu GRUB
# (Appuyez sur Shift au démarrage pour afficher le menu)

# ═══════════════════════════════════════════
# PRÉVENTION : Bloquer les mises à jour automatiques du noyau
# (uniquement si vous préférez contrôler les mises à jour manuellement)
# ═══════════════════════════════════════════
sudo apt-mark hold linux-image-generic linux-headers-generic
# Pour débloquer plus tard :
# sudo apt-mark unhold linux-image-generic linux-headers-generic
```

---

### 10. GPU non détecté par Docker (Windows)

**Symptôme :** `docker run --gpus all ...` échoue sous Windows

**Diagnostic :**

```powershell
# 1. Vérifier que le driver NVIDIA est installé
nvidia-smi

# 2. Vérifier la version de Windows
winver
# Requis : Windows 11, ou Windows 10 version 21H2+

# 3. Vérifier que WSL 2 est bien activé
wsl --status

# 4. Vérifier que Docker Desktop utilise WSL 2
# Docker Desktop → Settings → General → "Use the WSL 2 based engine" ✅
```

**Solutions :**

```powershell
# Si nvidia-smi ne fonctionne pas :
# → Télécharger le dernier driver NVIDIA depuis https://www.nvidia.com/drivers
# → Installer et redémarrer

# Si WSL 2 n'est pas activé :
wsl --install
# Redémarrer l'ordinateur

# Si Docker Desktop ne voit toujours pas le GPU :
# 1. Fermer Docker Desktop complètement
# 2. Mettre à jour Docker Desktop vers la dernière version
# 3. Redémarrer l'ordinateur
# 4. Relancer Docker Desktop
# 5. Tester : docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

---

### 11. "could not select device driver 'nvidia'"

**Symptôme :** `could not select device driver "nvidia" with capabilities: [[gpu]]`

**Cause :** Le runtime NVIDIA n'est pas configuré dans Docker.

**Solution Linux :**

```bash
# Vérifier si le runtime nvidia existe dans la config Docker
cat /etc/docker/daemon.json

# Si le fichier est vide ou ne contient pas "nvidia", configurer :
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Le fichier devrait maintenant contenir quelque chose comme :
# {
#   "runtimes": {
#     "nvidia": {
#       "path": "nvidia-container-runtime",
#       "runtimeArgs": []
#     }
#   }
# }
```

---

### 12. Ollama utilise le CPU alors que le GPU est disponible

**Symptôme :** La génération est très lente malgré un GPU. Les logs Ollama n'affichent aucune ligne mentionnant "CUDA" ou "GPU".

**Diagnostic :**

```bash
# Vérifier si Ollama détecte le GPU
docker exec -it ollama ollama ps
# La colonne "processor" doit afficher "GPU" (pas "CPU")

# Vérifier les logs de démarrage d'Ollama
docker logs ollama 2>&1 | grep -i -E "gpu|cuda|nvidia|vram"
```

**Solutions :**

```bash
# 1. S'assurer d'utiliser le fichier GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d

# 2. Vérifier que OLLAMA_GPU_LAYERS n'est pas à 0
# Dans .env :
OLLAMA_GPU_LAYERS=-1    # -1 = toutes les couches sur GPU

# 3. Recréer le conteneur Ollama (ne supprime pas les modèles)
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --force-recreate ollama

# 4. Vérifier la VRAM disponible
nvidia-smi
# Si la VRAM est presque pleine, un autre processus l'occupe
```

---

### 13. "CUDA out of memory" / VRAM insuffisante

**Symptôme :** `CUDA out of memory` dans les logs d'Ollama

**Cause :** Le modèle est trop gros pour la VRAM de votre GPU.

**Solutions :**

```bash
# Vérifier la VRAM disponible
nvidia-smi

# Option 1 : Utiliser un modèle plus petit
# llama3.1:latest (8B) → ~5 Go VRAM
# glm-4.7-flash:latest → ~3 Go VRAM
# phi3:latest (3.8B) → ~2.5 Go VRAM

# Option 2 : Mode hybride CPU+GPU (décharger une partie sur la RAM)
# Dans .env, limiter les couches GPU (ex: 20 couches sur GPU, le reste sur CPU)
OLLAMA_GPU_LAYERS=20

# Option 3 : Décharger les modèles inactifs plus vite
OLLAMA_KEEP_ALIVE=60     # Décharge après 1 minute
OLLAMA_NUM_PARALLEL=1    # Un seul modèle à la fois

# Redémarrer pour appliquer
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --force-recreate ollama
```

---

## 🦙 Problèmes Ollama

### 14. Les modèles ne se téléchargent pas (ollama-init échoue)

**Diagnostic :**

```bash
# Voir les logs du service d'init
docker logs ollama-init

# Causes possibles :
# - Ollama pas encore prêt → le script attend automatiquement
# - Pas de connexion Internet → vérifier la connectivité
# - Nom de modèle incorrect → vérifier dans scripts/init-models.sh
# - Timeout → les gros modèles (>5 Go) peuvent dépasser le timeout
```

**Solutions :**

```bash
# Relancer le téléchargement
docker compose run --rm ollama-init

# Télécharger manuellement un modèle
docker exec -it ollama ollama pull llama3.1:latest

# Si le problème est réseau, tester la connectivité du conteneur
docker exec -it ollama curl -I https://ollama.com
```

---

### 15. "model not found" dans AnythingLLM

**Symptôme :** AnythingLLM affiche "model not found" ou ne liste aucun modèle

**Cause :** Les modèles ne sont pas encore téléchargés, ou l'URL Ollama est incorrecte.

**Solution :**

```bash
# 1. Vérifier que les modèles sont installés
docker exec -it ollama ollama list

# 2. Si la liste est vide, les modèles ne sont pas téléchargés
docker compose run --rm ollama-init

# 3. Vérifier la connexion entre AnythingLLM et Ollama
docker exec anythingllm curl -s http://ollama:11434/api/tags

# 4. Dans AnythingLLM, l'URL Ollama doit être :
#    http://ollama:11434   (PAS http://localhost:11434)
```

---

### 16. Ollama est très lent en mode CPU

**Symptôme :** La génération de texte prend plusieurs minutes.

**C'est normal en mode CPU.** Les LLM sont conçus pour les GPU.

**Améliorations possibles :**

```bash
# 1. Utiliser un modèle plus petit
# glm-4.7-flash:latest est le plus rapide de la stack

# 2. Augmenter le nombre de threads CPU
# Ajoutez dans docker-compose.yml, sous environment: d'ollama :
- OLLAMA_NUM_CPU=8    # Nombre de cœurs CPU à utiliser

# 3. Réduire la taille du contexte dans .env
MODEL_TOKEN_LIMIT=4096    # Au lieu de 8192

# 4. Idéalement : passer en mode GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
```

---

## 📦 Problèmes Qdrant

### 17. Qdrant ne démarre pas / crash au démarrage

**Diagnostic :**

```bash
docker compose logs --tail=50 qdrant
```

**Causes et solutions :**

```bash
# Cause 1 : Fichier config.yaml invalide
# Vérifier la syntaxe YAML :
docker run --rm -v $(pwd)/config/qdrant/config.yaml:/config.yaml \
  python:3-slim python -c "import yaml; yaml.safe_load(open('/config.yaml'))"

# Cause 2 : Données corrompues
# Réinitialiser le volume Qdrant (SUPPRIME TOUTES LES COLLECTIONS)
docker compose stop qdrant
docker volume rm qdrant_data
docker compose up -d qdrant

# Cause 3 : Manque de mémoire
# Qdrant utilise le memory-mapping. Vérifier les limites :
# Linux :
sysctl vm.max_map_count
# Si < 262144 :
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

---

### 18. "Too many open files" dans les logs Qdrant

**Symptôme :** `Too many open files (os error 24)` dans les logs

**Cause :** Limite système du nombre de fichiers ouverts trop basse.

**Solution Linux :**

```bash
# Vérifier la limite actuelle
ulimit -n

# Augmenter temporairement
ulimit -n 65536

# Augmenter de façon permanente
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Pour Docker spécifiquement, ajouter dans /etc/docker/daemon.json :
# {
#   "default-ulimits": {
#     "nofile": { "Name": "nofile", "Soft": 65536, "Hard": 65536 }
#   }
# }
sudo systemctl restart docker
```

---

## 🌐 Problèmes AnythingLLM

### 19. AnythingLLM ne se connecte pas à Ollama

**Symptôme :** Erreur de connexion à Ollama dans l'interface

**Cause n°1 :** Utilisation de `localhost` au lieu du nom de service Docker

```
❌ http://localhost:11434      ← Ne fonctionne PAS (localhost = le conteneur lui-même)
✅ http://ollama:11434         ← Correct (nom du service Docker)
```

**Cause n°2 :** Ollama n'est pas encore prêt

```bash
# Vérifier l'état d'Ollama
docker compose ps ollama
# "healthy" = prêt, "starting" = en cours de démarrage
```

**Cause n°3 :** Réseau Docker non fonctionnel

```bash
# Tester la résolution DNS depuis AnythingLLM
docker exec anythingllm ping -c 3 ollama

# Si ça échoue, recréer le réseau
docker compose down
docker compose up -d
```

---

### 20. AnythingLLM ne se connecte pas à Qdrant

**Même logique que pour Ollama :**

```
❌ http://localhost:6333       ← Ne fonctionne PAS
✅ http://qdrant:6333          ← Correct
```

**Si une clé API Qdrant est définie :**
Vérifiez que `QDRANT_API_KEY` dans `.env` est identique pour Qdrant et AnythingLLM (c'est automatique via le `.env` partagé).

---

### 21. L'upload de documents échoue

**Diagnostic :**

```bash
docker compose logs --tail=50 anythingllm | grep -i error
```

**Causes fréquentes :**

```bash
# 1. Manque de RAM → le traitement de gros PDF est gourmand
docker stats --no-stream anythingllm

# 2. Format non supporté
# AnythingLLM supporte : PDF, TXT, DOCX, MD, CSV, XLSX, et plus
# Les images et vidéos ne sont PAS indexables en RAG

# 3. Le modèle d'embedding n'est pas disponible
docker exec -it ollama ollama list | grep embed

# 4. Permissions sur le volume de stockage
docker exec anythingllm ls -la /app/server/storage/
```

---

### 22. AnythingLLM est bloqué sur "Loading..." / page blanche

**Solutions :**

```bash
# 1. Vider le cache du navigateur ou essayer en navigation privée

# 2. Vérifier que le conteneur est sain
docker compose ps anythingllm

# 3. Redémarrer AnythingLLM
docker compose restart anythingllm

# 4. En dernier recours : réinitialiser la base de données
docker compose stop anythingllm
docker volume rm anythingllm_data
docker compose up -d anythingllm
# ⚠️ Cela supprime tous les workspaces, utilisateurs et documents uploadés
```

---

## 🌍 Problèmes réseau

### 23. Accès depuis une autre machine impossible

**Symptôme :** `http://<IP>:3001` ne répond pas depuis un autre PC du réseau

**Solutions :**

```bash
# 1. Vérifier que le pare-feu autorise les ports
# Linux (UFW)
sudo ufw status
sudo ufw allow 3001/tcp
sudo ufw allow 11434/tcp
sudo ufw allow 6333/tcp

# Linux (firewalld)
sudo firewall-cmd --permanent --add-port=3001/tcp
sudo firewall-cmd --permanent --add-port=11434/tcp
sudo firewall-cmd --permanent --add-port=6333/tcp
sudo firewall-cmd --reload

# Windows : vérifier le pare-feu Windows Defender
# Panneau de configuration → Pare-feu → Autoriser une application

# 2. Vérifier l'IP de la machine
ip addr show       # Linux
ipconfig           # Windows

# 3. Tester localement d'abord
curl http://localhost:3001/api/ping
```

---

### 24. Proxy ou VPN bloquant le téléchargement des modèles

**Symptôme :** Les modèles ne se téléchargent pas, timeout réseau

**Solutions :**

```bash
# 1. Configurer le proxy pour Docker
# Créer/éditer /etc/systemd/system/docker.service.d/proxy.conf
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/proxy.conf << 'EOF'
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,ollama,qdrant,anythingllm"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# 2. Ou configurer le proxy dans le conteneur Ollama
# Ajoutez dans docker-compose.yml, sous environment: d'ollama :
# - HTTP_PROXY=http://proxy.example.com:8080
# - HTTPS_PROXY=http://proxy.example.com:8080
# - NO_PROXY=localhost,127.0.0.1
```

---

## 🐢 Problèmes de performance

### 25. Tout est lent / RAM saturée

**Diagnostic :**

```bash
# Voir la consommation de chaque conteneur
docker stats

# Voir la mémoire système
free -h       # Linux
```

**Recommandations mémoire :**

| Scénario | RAM requise |
|----------|------------|
| 1 modèle 8B en CPU | ~8 Go |
| 1 modèle 8B en GPU | ~4 Go RAM + 6 Go VRAM |
| 2 modèles 8B simultanés | ~16 Go |
| Modèle 8B + embedding + Qdrant | ~12 Go |

**Optimisations :**

```bash
# Réduire le nombre de modèles en mémoire (dans .env)
OLLAMA_NUM_PARALLEL=1

# Décharger les modèles plus vite
OLLAMA_KEEP_ALIVE=60    # 1 minute au lieu de 5

# Utiliser des modèles plus légers
# glm-4.7-flash ou phi3 au lieu de llama3.1
```

---

### 26. Le RAG retourne des résultats non pertinents

**C'est un problème de configuration RAG, pas d'infrastructure.**

**Pistes d'amélioration :**

```
1. Taille des chunks trop grande ou trop petite
   → Essayez EMBEDDING_CHUNK_LENGTH=1024 (au lieu de 8192)

2. Modèle d'embedding pas adapté à la langue
   → bge-m3 est meilleur que nomic-embed-text pour le français

3. Nombre de chunks retournés (top-k) trop bas
   → Dans AnythingLLM : Workspace Settings → Chat → augmenter le nombre de résultats

4. Documents mal formatés
   → Préférez les PDF avec du texte sélectionnable (pas des scans/images)

5. Activer le reranking dans AnythingLLM
   → Workspace Settings → Chat → "Accuracy Optimized"
```

---

## 👥 Problèmes multi-utilisateurs

### 27. Impossible de revenir en mode single-user

**C'est par conception.** Le passage en mode multi-user est irréversible dans AnythingLLM. La seule option pour revenir en single-user est de réinitialiser complètement AnythingLLM :

```bash
docker compose stop anythingllm
docker volume rm anythingllm_data
docker compose up -d anythingllm
# ⚠️ Vous perdrez tous les workspaces, documents et utilisateurs
```

---

### 28. Utilisateur bloqué / mot de passe oublié

**Solutions :**

```bash
# Option 1 : L'admin peut réinitialiser le mot de passe
# Via l'interface : Settings → Users → clic sur l'utilisateur → Reset Password

# Option 2 : Si c'est le compte admin qui est perdu
# Il faut accéder à la base SQLite interne
docker exec -it anythingllm sh
# Dans le conteneur :
cd /app/server/storage
# Le fichier anythingllm.db contient les utilisateurs
# Vous pouvez utiliser sqlite3 pour modifier le mot de passe
# (avancé, uniquement si vous connaissez SQLite)
```

---

### 29. Un utilisateur "Default" ne voit aucun workspace

**Cause :** L'admin n'a pas assigné cet utilisateur à des workspaces.

**Solution :**
1. Connectez-vous en tant qu'Admin
2. Allez dans **Settings** → **Users**
3. Sélectionnez l'utilisateur
4. Assignez-le aux workspaces souhaités

---

## 🔄 Mises à jour et migrations

### 30. Mettre à jour les images Docker

```bash
# 1. Tirer les dernières versions
docker compose pull

# 2. Recréer les conteneurs avec les nouvelles images
docker compose up -d

# Vos données sont conservées dans les volumes Docker
# Aucun risque de perte de données
```

---

### 31. Mettre à jour les drivers NVIDIA sans casser le GPU

**Procédure sécurisée :**

```bash
# 1. Arrêter la stack
docker compose down

# 2. Vérifier le driver actuel
nvidia-smi | head -3

# 3. Mettre à jour le driver
sudo apt update
sudo apt install -y nvidia-driver-550   # Remplacer par la version souhaitée

# 4. OBLIGATOIRE : redémarrer
sudo reboot

# 5. Vérifier le nouveau driver
nvidia-smi

# 6. Reconfigurer le toolkit Docker NVIDIA
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 7. Tester le GPU dans Docker
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

# 8. Relancer la stack
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
```

---

### 32. Mise à jour du système Linux (apt upgrade) casse le GPU

**C'est le problème le plus fréquent.** Voir la section [9. GPU non détecté après une mise à jour du noyau Linux](#9-gpu-non-détecté-après-une-mise-à-jour-du-noyau-linux) pour les solutions.

**Prévention :**

```bash
# Installer DKMS pour recompiler automatiquement le module NVIDIA
sudo apt install -y nvidia-dkms-535   # Remplacer 535 par votre version de driver

# Vérifier que DKMS gère bien le module
dkms status
# Devrait afficher : nvidia/535.xxx, <version_noyau>, installed
```

---

## 🆘 Procédures de récupération

### Sauvegarder avant toute opération risquée

```bash
mkdir -p backup

# Sauvegarder les 3 volumes
for vol in ollama_data qdrant_data anythingllm_data; do
  docker run --rm -v ${vol}:/data -v $(pwd)/backup:/backup \
    alpine tar czf /backup/${vol}_$(date +%Y%m%d).tar.gz -C /data .
  echo "✓ ${vol} sauvegardé"
done
```

### Restaurer un volume depuis une sauvegarde

```bash
# Arrêter le service concerné
docker compose stop <service>

# Supprimer le volume actuel
docker volume rm <nom_volume>

# Recréer et restaurer
docker volume create <nom_volume>
docker run --rm -v <nom_volume>:/data -v $(pwd)/backup:/backup \
  alpine sh -c "cd /data && tar xzf /backup/<nom_volume>_YYYYMMDD.tar.gz"

# Relancer
docker compose up -d <service>
```

### Reset complet (dernier recours)

```bash
# ⚠️ SUPPRIME TOUT : conteneurs, volumes, données, modèles
docker compose down -v --remove-orphans
docker system prune -a --volumes

# Repartir de zéro
cp .env.example .env
docker compose up -d
```

---

## 📊 Tableau récapitulatif des erreurs

| # | Erreur | Service | OS | Section |
|---|--------|---------|-----|---------|
| 1 | Cannot connect to Docker daemon | Docker | Linux | [§2](#-problèmes-docker) |
| 2 | Permission denied (docker) | Docker | Linux | [§2](#-problèmes-docker) |
| 3 | docker compose introuvable | Docker | Tous | [§2](#-problèmes-docker) |
| 4 | Port already allocated | Docker | Tous | [§2](#-problèmes-docker) |
| 5 | Restart loop | Docker | Tous | [§2](#-problèmes-docker) |
| 6 | No space left on device | Docker | Tous | [§2](#-problèmes-docker) |
| 7 | Permissions volumes | Docker | Linux | [§2](#-problèmes-docker) |
| 8 | GPU non détecté (Linux) | NVIDIA | Linux | [§3](#-problèmes-gpu--nvidia) |
| 9 | GPU cassé après apt upgrade | NVIDIA | Linux | [§3](#-problèmes-gpu--nvidia) |
| 10 | GPU non détecté (Windows) | NVIDIA | Windows | [§3](#-problèmes-gpu--nvidia) |
| 11 | Could not select driver nvidia | NVIDIA | Linux | [§3](#-problèmes-gpu--nvidia) |
| 12 | Ollama n'utilise pas le GPU | Ollama | Tous | [§3](#-problèmes-gpu--nvidia) |
| 13 | CUDA out of memory | Ollama | Tous | [§3](#-problèmes-gpu--nvidia) |
| 14 | Modèles ne se téléchargent pas | Ollama | Tous | [§4](#-problèmes-ollama) |
| 15 | Model not found | Ollama | Tous | [§4](#-problèmes-ollama) |
| 16 | Ollama lent en CPU | Ollama | Tous | [§4](#-problèmes-ollama) |
| 17 | Qdrant crash au démarrage | Qdrant | Tous | [§5](#-problèmes-qdrant) |
| 18 | Too many open files | Qdrant | Linux | [§5](#-problèmes-qdrant) |
| 19 | AnythingLLM → Ollama KO | AnythingLLM | Tous | [§6](#-problèmes-anythingllm) |
| 20 | AnythingLLM → Qdrant KO | AnythingLLM | Tous | [§6](#-problèmes-anythingllm) |
| 21 | Upload de documents échoue | AnythingLLM | Tous | [§6](#-problèmes-anythingllm) |
| 22 | Page blanche / Loading | AnythingLLM | Tous | [§6](#-problèmes-anythingllm) |
| 23 | Accès distant impossible | Réseau | Tous | [§7](#-problèmes-réseau) |
| 24 | Proxy bloquant | Réseau | Tous | [§7](#-problèmes-réseau) |
| 25 | RAM saturée | Performance | Tous | [§8](#-problèmes-de-performance) |
| 26 | RAG non pertinent | Performance | Tous | [§8](#-problèmes-de-performance) |
| 27 | Retour single-user impossible | Multi-user | Tous | [§9](#-problèmes-multi-utilisateurs) |
| 28 | Mot de passe oublié | Multi-user | Tous | [§9](#-problèmes-multi-utilisateurs) |
| 29 | User ne voit rien | Multi-user | Tous | [§9](#-problèmes-multi-utilisateurs) |
| 30 | Mise à jour images Docker | Migration | Tous | [§10](#-mises-à-jour-et-migrations) |
| 31 | Mise à jour driver NVIDIA | Migration | Tous | [§10](#-mises-à-jour-et-migrations) |
| 32 | apt upgrade casse GPU | Migration | Linux | [§10](#-mises-à-jour-et-migrations) |
