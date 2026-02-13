# 🚀 Stack RAG Locale — Ollama + Qdrant + AnythingLLM

> **Stack complète de RAG (Retrieval-Augmented Generation) auto-hébergée avec Docker Compose.**
> Discutez avec vos documents en utilisant des LLM locaux — aucune donnée ne quitte votre machine.

---

## 📋 Table des matières

1. [Vue d'ensemble](#-vue-densemble)
2. [Architecture](#-architecture)
3. [Prérequis](#-prérequis)
4. [Installation — Linux](#-installation--linux)
5. [Installation — Windows](#-installation--windows)
6. [Déploiement](#-déploiement)
7. [Configuration post-déploiement](#-configuration-post-déploiement)
8. [Multi-utilisateurs](#-multi-utilisateurs)
9. [Commandes utiles](#-commandes-utiles)
10. [Personnalisation](#-personnalisation)

> 📘 Un guide de dépannage exhaustif est disponible dans **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**.

---

## 🔍 Vue d'ensemble

Cette stack déploie 3 services interconnectés :

| Service | Rôle | Port |
|---------|------|------|
| **Ollama** | Serveur d'inférence LLM local | `11434` |
| **Qdrant** | Base de données vectorielle | `6333` (REST) / `6334` (gRPC) |
| **AnythingLLM** | Interface web RAG tout-en-un | `3001` |

**Modèles pré-installés automatiquement :**

| Modèle | Type | Taille approx. | Usage |
|--------|------|-----------------|-------|
| `llama3.1:latest` | LLM | ~4.7 Go | Conversation générale, RAG |
| `llama3:8b` | LLM | ~4.7 Go | Alternative stable |
| `glm-4.7-flash:latest` | LLM | ~3.0 Go | Tâches rapides |
| `qwen3-vl:8b` | LLM multimodal | ~5.0 Go | Texte + images |
| `nomic-embed-text:latest` | Embedding | ~274 Mo | Indexation documents (recommandé) |
| `bge-m3:latest` | Embedding | ~1.2 Go | Multilingue dense+sparse |
| `bge-m3:567m` | Embedding | ~567 Mo | Version compacte |
| `embeddinggemma:300m` | Embedding | ~300 Mo | Léger et performant |

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Machine Hôte                     │
│                                                     │
│  ┌──────────────┐  ┌──────────┐  ┌──────────────┐   │
│  │   Ollama     │  │  Qdrant  │  │ AnythingLLM  │   │
│  │              │  │          │  │              │   │
│  │ LLM Inference│  │ Vector DB│  │ Web UI + RAG │   │
│  │ :11434       │  │ :6333    │  │ :3001        │   │
│  └──────┬───────┘  └────┬─────┘  └──────┬───────┘   │  
│         │               │               │           │
│         └───────────────┼───────────────┘           │
│                         │                           │
│                   [rag-network]                     │
│                   Réseau Docker                     │
└─────────────────────────────────────────────────────┘
```

**Flux de données RAG :**
1. L'utilisateur uploade un document dans AnythingLLM
2. AnythingLLM découpe le document en chunks
3. Chaque chunk est transformé en vecteur via Ollama (modèle d'embedding)
4. Les vecteurs sont stockés dans Qdrant
5. Quand l'utilisateur pose une question :
   - La question est vectorisée
   - Qdrant retrouve les chunks les plus similaires
   - Les chunks pertinents + la question sont envoyés au LLM
   - Le LLM génère une réponse contextualisée

---

## ⚙ Prérequis

### Configuration minimale

| Ressource | Minimum | Recommandé |
|-----------|---------|------------|
| RAM | 8 Go | 16 Go+ |
| Stockage | 30 Go | 60 Go+ |
| CPU | 4 cœurs | 8 cœurs+ |
| GPU (optionnel) | NVIDIA 6 Go VRAM | NVIDIA 8 Go+ VRAM |

### Logiciels requis

| Logiciel | Version min. | Vérification |
|----------|-------------|--------------|
| Docker Engine | 20.10+ | `docker --version` |
| Docker Compose | V2+ | `docker compose version` |
| Git (optionnel) | 2.0+ | `git --version` |
| NVIDIA Driver (si GPU) | 525+ | `nvidia-smi` |
| NVIDIA Container Toolkit (si GPU, Linux) | 1.13+ | `nvidia-ctk --version` |

---

## 🐧 Installation sur Linux

### Étape 1 : Installer Docker

```bash
# === Ubuntu / Debian ===

# Mise à jour des paquets
sudo apt update && sudo apt upgrade -y

# Installation des dépendances
sudo apt install -y ca-certificates curl gnupg

# Ajout de la clé GPG officielle Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Ajout du dépôt Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installation de Docker Engine + Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ajout de votre utilisateur au groupe docker (évite d'utiliser sudo)
sudo usermod -aG docker $USER

# IMPORTANT : Déconnectez-vous et reconnectez-vous pour que le groupe prenne effet
# Ou exécutez : newgrp docker

# Vérification
docker --version
docker compose version
```

### Étape 2 (optionnel) : Installer le support GPU NVIDIA

```bash
# Prérequis : les drivers NVIDIA doivent déjà être installés
# Vérification : nvidia-smi doit afficher votre GPU

# Installation du NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configuration de Docker pour utiliser le runtime NVIDIA
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Vérification : doit afficher les infos GPU
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

### Étape 3 : Déployer la stack

Passez à la section [Déploiement](#-déploiement).

---

## 🪟 Installation sur Windows

### Étape 1 : Installer Docker Desktop

1. **Téléchargez Docker Desktop** depuis [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
2. **Exécutez l'installateur** et suivez les instructions
3. **Activez WSL 2** si demandé (Docker Desktop le propose automatiquement)
4. **Redémarrez** votre ordinateur si nécessaire
5. **Lancez Docker Desktop** depuis le menu Démarrer

**Vérification dans PowerShell :**

```powershell
docker --version
docker compose version
```

### Étape 2 (optionnel) : Activer le support GPU NVIDIA

> **Prérequis :** Carte graphique NVIDIA avec drivers à jour (525+)

1. Ouvrez **Docker Desktop** → **Settings** (⚙️)
2. Allez dans **Resources** → **WSL Integration**
3. Activez l'intégration WSL pour votre distribution
4. Dans **General**, vérifiez que **"Use the WSL 2 based engine"** est coché
5. Appliquez et redémarrez Docker Desktop

**Vérification dans PowerShell :**

```powershell
# Doit afficher les infos de votre GPU
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

> **Note Windows :** Le support GPU dans Docker Desktop pour Windows nécessite
> Windows 11 (ou Windows 10 21H2+) avec WSL 2 et les drivers NVIDIA 525+.

### Étape 3 : Déployer la stack

Passez à la section [Déploiement](#-déploiement).

---

## 🚀 Déploiement

### 1. Récupérer le projet

```bash
# Option A : Cloner avec Git
git clone https://github.com/delferiermaxime-cmd/ollama-rag-stack.git ollama-rag-stack
cd ollama-rag-stack

# Option B : Télécharger et extraire manuellement
# Puis : cd ollama-rag-stack
```

### 2. Configurer l'environnement

```bash
# Copier le fichier d'exemple
cp env.example .env
cat .env (pour vérifier)

# Éditez .env selon vos besoins (optionnel, les valeurs par défaut fonctionnent)
# Linux : nano .env
# Windows PowerShell : notepad .env
```

### 3. Rendre les scripts exécutables (Linux uniquement)

```bash
chmod +x scripts/*.sh
```

### 4. Lancer la stack

```bash
# ╔═══════════════════════════════════════════╗
# ║  MODE CPU (sans GPU)                      ║
# ╚═══════════════════════════════════════════╝
docker compose up -d

# ╔═══════════════════════════════════════════╗
# ║  MODE GPU NVIDIA                          ║
# ╚═══════════════════════════════════════════╝
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
```

### 5. Suivre le téléchargement des modèles

Le premier lancement télécharge tous les modèles (~15-20 Go). Suivez la progression :

```bash
# Suivre les logs du service d'initialisation en temps réel
docker logs -f ollama-init

# Ou suivre tous les services
docker compose logs -f
```

> ⏱ **Le premier démarrage peut prendre 15-60 minutes** selon votre connexion Internet.
> Les démarrages suivants seront quasi instantanés car les modèles sont persistés.

### 6. Vérifier l'installation

```bash
# Linux
./scripts/check-health.sh

# Windows PowerShell
docker compose ps
curl http://localhost:11434/         # Ollama
curl http://localhost:6333/healthz   # Qdrant
curl http://localhost:3001/api/ping  # AnythingLLM
```

### 7. Accéder aux services

| Service | URL |
|---------|-----|
| **AnythingLLM** (interface principale) | [http://localhost:3001](http://localhost:3001) |
| **Ollama API** | [http://localhost:11434](http://localhost:11434) |
| **Qdrant Dashboard** | [http://localhost:6333/dashboard](http://localhost:6333/dashboard) |

---

## 🔧 Configuration post-déploiement

### Configurer AnythingLLM (premier lancement)

1. Ouvrez [http://localhost:3001](http://localhost:3001) dans votre navigateur
2. Suivez l'assistant de configuration :
   - **LLM Provider** : Sélectionnez `Ollama`
   - **Ollama URL** : `http://ollama:11434` (URL interne Docker)
   - **Modèle LLM** : Choisissez `llama3.1:latest` (ou un autre de la liste)
   - **Embedding Provider** : Sélectionnez `Ollama`
   - **Modèle d'embedding** : Choisissez `nomic-embed-text:latest`
   - **Vector Database** : Sélectionnez `Qdrant`
   - **Qdrant URL** : `http://qdrant:6333` (URL interne Docker)
3. Créez un workspace et commencez à uploader des documents !

### Tester Ollama directement

```bash
# Lister les modèles disponibles
curl http://localhost:11434/api/tags

# Tester une génération
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.1:latest",
  "prompt": "Bonjour ! Explique-moi le RAG en une phrase.",
  "stream": false
}'

# Tester un embedding
curl http://localhost:11434/api/embeddings -d '{
  "model": "nomic-embed-text:latest",
  "prompt": "Ceci est un test d embedding"
}'
```

---

## 👥 Multi-Utilisateurs

AnythingLLM supporte nativement le mode multi-utilisateurs avec des rôles.
Tous les utilisateurs partagent la même URL et la même base vectorielle Qdrant.
Les accès sont contrôlés par des rôles assignés par l'administrateur.

### Activation

**Étape 1 :** Lancez la stack normalement (`docker compose up -d`)

**Étape 2 :** Ouvrez AnythingLLM → **Settings** (⚙️) → **Security** → **Enable Multi-User Mode**

**Étape 3 :** Créez le compte administrateur (username + mot de passe)

> ⚠️ **ATTENTION : Cette action est IRRÉVERSIBLE.** Une fois le mode multi-user activé, impossible de revenir en single-user.

**Étape 4 :** Créez des utilisateurs via **Settings** → **Users**

### Rôles disponibles

| Rôle | Workspaces | Documents | Settings système | Gestion users |
|------|-----------|-----------|-----------------|---------------|
| **Admin** | Tous | Tous | ✅ | ✅ |
| **Manager** | Tous | Tous | ❌ | ❌ |
| **Default** | Assignés uniquement | Assignés uniquement | ❌ | ❌ |

### Comment ça marche avec Qdrant

Quand un document est embedé dans un workspace, tous les utilisateurs ayant accès à ce workspace peuvent interroger ces documents via RAG. Les vecteurs sont stockés dans Qdrant dans des collections nommées automatiquement par workspace. Un utilisateur "Default" ne voit que les workspaces auxquels l'admin l'a assigné.

### Configuration avancée : SSO Simple

Pour intégrer AnythingLLM dans un système d'authentification existant :

```bash
# 1. Activez dans .env :
SIMPLE_SSO_ENABLED=enable

# 2. Redémarrez :
docker compose restart anythingllm

# 3. Générez un lien de connexion via l'API :
curl -X POST http://localhost:3001/api/v1/users/{user_id}/issue-auth-token \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json"
```

---

## 📝 Commandes utiles

### Gestion des services

```bash
# Démarrer la stack
docker compose up -d

# Démarrer avec GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d

# Arrêter (conserver les données)
docker compose stop

# Redémarrer
docker compose restart

# Arrêter et supprimer les conteneurs (volumes conservés)
docker compose down

# TOUT supprimer (conteneurs + volumes + données)
docker compose down -v --remove-orphans
```

### Logs et débogage

```bash
docker compose logs              # Tous les logs
docker compose logs -f           # Temps réel
docker compose logs -f ollama    # Un service spécifique
```

### Gestion des modèles Ollama

```bash
docker exec -it ollama ollama pull <modele>   # Ajouter
docker exec -it ollama ollama list            # Lister
docker exec -it ollama ollama rm <modele>     # Supprimer
docker exec -it ollama ollama show <modele>   # Infos
```

### Sauvegarde et restauration

```bash
# Sauvegarder
docker run --rm -v ollama_data:/data -v $(pwd)/backup:/backup \
  alpine tar czf /backup/ollama_backup.tar.gz -C /data .

docker run --rm -v qdrant_data:/data -v $(pwd)/backup:/backup \
  alpine tar czf /backup/qdrant_backup.tar.gz -C /data .

docker run --rm -v anythingllm_data:/data -v $(pwd)/backup:/backup \
  alpine tar czf /backup/anythingllm_backup.tar.gz -C /data .

# Restaurer
docker run --rm -v ollama_data:/data -v $(pwd)/backup:/backup \
  alpine sh -c "cd /data && tar xzf /backup/ollama_backup.tar.gz"
```

---

## 🎨 Personnalisation

### Ajouter/supprimer des modèles

Éditez `scripts/init-models.sh` et modifiez la variable `MODELS`, puis relancez :

```bash
docker compose run --rm ollama-init
```

Parcourez la bibliothèque sur [ollama.com/library](https://ollama.com/library).

### Modifier les paramètres Qdrant

Éditez `config/qdrant/config.yaml` puis : `docker compose restart qdrant`

### Exposer sur le réseau local

Les services écoutent sur toutes les interfaces par défaut. Depuis une autre machine :
`http://<IP_DE_LA_MACHINE>:3001`

---

## 📁 Structure du projet

```
ollama-rag-stack/
├── docker-compose.yml          # Configuration principale (CPU)
├── docker-compose.gpu.yml      # Override pour GPU NVIDIA
├── .env.example                # Template des variables d'environnement
├── .env                        # Votre configuration locale (créé par vous)
├── .gitignore                  # Fichiers exclus de Git
├── README.md                   # Ce fichier
├── TROUBLESHOOTING.md          # Guide de dépannage exhaustif
├── config/
│   └── qdrant/
│       └── config.yaml         # Configuration avancée de Qdrant
└── scripts/
    ├── init-models.sh          # Téléchargement automatique des modèles
    ├── check-health.sh         # Vérification de santé de la stack
    └── stop-and-clean.sh       # Arrêt et nettoyage
```

---

## 📄 Licence

Ce projet est fourni tel quel, libre d'utilisation et de modification.
Les composants utilisés ont leurs propres licences :
- Ollama : [MIT License](https://github.com/ollama/ollama/blob/main/LICENSE)
- Qdrant : [Apache 2.0](https://github.com/qdrant/qdrant/blob/master/LICENSE)
- AnythingLLM : [MIT License](https://github.com/Mintplex-Labs/anything-llm/blob/master/LICENSE)
