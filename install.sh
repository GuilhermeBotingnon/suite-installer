#!/usr/bin/env bash

#==============================================================================
# THE - Complete Stack Installer v3.0 FINAL
# Docker 29+ + Swarm + Traefik v2.10 + SSL + Portainer + PostgreSQL + MySQL + N8N
# Compatível: Debian 12/13
# Testado e validado - SSL automático funcionando
#==============================================================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variáveis Globais
TRAEFIK_VERSION="v2.10"
PORTAINER_VERSION="latest"
N8N_VERSION="latest"
POSTGRES_VERSION="15"
MYSQL_VERSION="8.0"
PHPMYADMIN_VERSION="latest"

# Banner
clear
echo -e "${BLUE}"
cat << "EOF"
 _____ _   _ _____ 
|_   _| | | | ____|
  | | | |_| |  _|  
  | | |  _  | |___ 
  |_| |_| |_|_____|
                   
THE Stack Installer v3.0 FINAL
Instalação completa com SSL automático
EOF
echo -e "${NC}"

#==============================================================================
# Funções Auxiliares
#==============================================================================

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}▶ $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

generate_password() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

generate_hash() {
    openssl rand -hex 8
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then 
        log_error "Execute como root: sudo bash $0"
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        
        if [[ "$OS" != "debian" ]]; then
            log_error "Sistema não suportado. Use Debian 12 ou 13"
        fi
        
        if [[ "$VER" != "12" && "$VER" != "13" ]]; then
            log_error "Versão não suportada. Use Debian 12 ou 13"
        fi
        
        log_info "Sistema detectado: Debian $VER"
    else
        log_error "Não foi possível detectar o sistema operacional"
    fi
}

wait_for_service() {
    local service_name=$1
    local max_wait=$2
    local waited=0
    
    echo -n "Aguardando $service_name "
    while [ $waited -lt $max_wait ]; do
        if docker service ls | grep -q "$service_name.*1/1"; then
            echo ""
            log_info "$service_name está rodando"
            return 0
        fi
        echo -n "."
        sleep 2
        waited=$((waited + 2))
    done
    echo ""
    log_warn "$service_name pode não ter iniciado completamente"
    return 1
}

#==============================================================================
# Coleta de Informações
#==============================================================================

collect_domains() {
    log_step "CONFIGURAÇÃO DE DOMÍNIOS"
    
    echo -n "Domínio principal (ex: empresa.com.br): "
    read -r BASE_DOMAIN
    
    if [ -z "$BASE_DOMAIN" ]; then
        log_error "Domínio principal é obrigatório"
    fi
    
    echo ""
    echo -e "${CYAN}Subdomínios (pressione Enter para usar o padrão):${NC}"
    echo ""
    
    echo -n "Portainer [portainer]: "
    read -r SUB_PORTAINER
    SUB_PORTAINER=${SUB_PORTAINER:-portainer}
    DOMAIN_PORTAINER="${SUB_PORTAINER}.${BASE_DOMAIN}"
    
    echo -n "phpMyAdmin [phpmyadmin]: "
    read -r SUB_PHPMYADMIN
    SUB_PHPMYADMIN=${SUB_PHPMYADMIN:-phpmyadmin}
    DOMAIN_PHPMYADMIN="${SUB_PHPMYADMIN}.${BASE_DOMAIN}"
    
    echo -n "N8N [n8n]: "
    read -r SUB_N8N
    SUB_N8N=${SUB_N8N:-n8n}
    DOMAIN_N8N="${SUB_N8N}.${BASE_DOMAIN}"
    
    echo -n "Webhook N8N [webhook]: "
    read -r SUB_WEBHOOK
    SUB_WEBHOOK=${SUB_WEBHOOK:-webhook}
    DOMAIN_WEBHOOK="${SUB_WEBHOOK}.${BASE_DOMAIN}"
    
    echo -n "Email para SSL [admin@${BASE_DOMAIN}]: "
    read -r EMAIL_SSL
    EMAIL_SSL=${EMAIL_SSL:-admin@${BASE_DOMAIN}}
    
    echo ""
    log_info "Domínios configurados:"
    echo -e "  ${BLUE}Portainer:${NC}   https://${DOMAIN_PORTAINER}"
    echo -e "  ${BLUE}phpMyAdmin:${NC}  https://${DOMAIN_PHPMYADMIN}"
    echo -e "  ${BLUE}N8N:${NC}         https://${DOMAIN_N8N}"
    echo -e "  ${BLUE}Webhook:${NC}     https://${DOMAIN_WEBHOOK}"
    echo ""
}

generate_credentials() {
    log_step "GERANDO CREDENCIAIS SEGURAS"
    
    POSTGRES_PASSWORD=$(generate_password)
    MYSQL_ROOT_PASSWORD=$(generate_password)
    N8N_DB_NAME="n8n_$(generate_hash)"
    N8N_ENCRYPTION_KEY=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    
    log_info "Todas as credenciais foram geradas"
}

#==============================================================================
# Instalação Base do Sistema
#==============================================================================

setup_swap() {
    log_step "CONFIGURANDO SWAP 4GB"
    
    if [ -f /swapfile ]; then
        log_warn "Swap já existe, pulando..."
        return
    fi
    
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    log_info "Swap de 4GB configurado"
}

install_dependencies() {
    log_step "INSTALANDO DEPENDÊNCIAS"
    
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        ufw \
        htop \
        net-tools \
        apache2-utils \
        dnsutils \
        wget > /dev/null 2>&1
    
    log_info "Dependências instaladas"
}

install_docker() {
    log_step "INSTALANDO DOCKER ENGINE (ÚLTIMA VERSÃO)"
    
    # Remover completamente versões antigas
    apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Limpar repositórios antigos
    rm -f /etc/apt/sources.list.d/docker.list
    rm -rf /etc/apt/keyrings/docker.gpg
    
    # Adicionar repositório oficial
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Atualizar e instalar
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Iniciar e habilitar
    systemctl enable docker
    systemctl start docker
    
    # Verificar versão
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}')
    DOCKER_API=$(docker version --format '{{.Server.APIVersion}}')
    
    log_info "Docker $DOCKER_VERSION instalado (API $DOCKER_API)"
    
    # Validar versão da API
    if [[ "$DOCKER_API" < "1.44" ]]; then
        log_error "Docker API muito antiga ($DOCKER_API). Necessário 1.44+. Tente reiniciar o servidor."
    fi
}

setup_docker_swarm() {
    log_step "INICIALIZANDO DOCKER SWARM"
    
    if docker info 2>/dev/null | grep -q "Swarm: active"; then
        log_warn "Swarm já está ativo"
        return
    fi
    
    SWARM_IP=$(hostname -I | awk '{print $1}')
    docker swarm init --advertise-addr "$SWARM_IP"
    
    log_info "Swarm inicializado em $SWARM_IP"
}

create_networks() {
    log_step "CRIANDO REDES DOCKER"
    
    if docker network ls | grep -q "network_swarm_public"; then
        log_warn "Network já existe"
    else
        docker network create --driver=overlay --attachable network_swarm_public
        log_info "Network network_swarm_public criada"
    fi
}

setup_firewall() {
    log_step "CONFIGURANDO FIREWALL UFW"
    
    # Desabilitar temporariamente para evitar problemas
    ufw --force disable
    
    # Configurar regras
    ufw default deny incoming
    ufw default allow outgoing
    
    # Portas essenciais
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # Portas Docker Swarm
    ufw allow 2377/tcp comment 'Docker Swarm'
    ufw allow 7946/tcp comment 'Docker Network'
    ufw allow 7946/udp comment 'Docker Network'
    ufw allow 4789/udp comment 'Docker Overlay'
    
    # Habilitar
    ufw --force enable
    
    log_info "Firewall configurado"
}

#==============================================================================
# Instalação Traefik (Proxy Reverso + SSL)
#==============================================================================

setup_traefik() {
    log_step "INSTALANDO TRAEFIK v2.10 + LET'S ENCRYPT"
    
    mkdir -p /opt/traefik/letsencrypt
    
    # Criar arquivo acme.json com permissões corretas
    touch /opt/traefik/letsencrypt/acme.json
    chmod 600 /opt/traefik/letsencrypt/acme.json
    
    cat > /opt/traefik/docker-compose.yml <<EOF
version: '3.8'

services:
  traefik:
    image: traefik:${TRAEFIK_VERSION}
    command:
      # API
      - "--api.dashboard=true"
      - "--api.insecure=false"
      
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      
      # Docker Provider
      - "--providers.docker=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.docker.network=network_swarm_public"
      - "--providers.docker.watch=true"
      
      # Let's Encrypt
      - "--certificatesresolvers.letsencryptresolver.acme.email=${EMAIL_SSL}"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      
      # Logs
      - "--log.level=INFO"
      - "--accesslog=false"
      
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
        
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik/letsencrypt:/letsencrypt
      
    networks:
      - network_swarm_public
      
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s

networks:
  network_swarm_public:
    external: true
EOF

    cd /opt/traefik
    docker stack deploy -c docker-compose.yml traefik
    
    log_info "Traefik implantado"
    wait_for_service "traefik_traefik" 30
}

#==============================================================================
# Instalação Portainer (Gerenciamento Docker)
#==============================================================================

setup_portainer() {
    log_step "INSTALANDO PORTAINER"
    
    mkdir -p /opt/portainer
    
    cat > /opt/portainer/docker-compose.yml <<EOF
version: '3.8'

services:
  agent:
    image: portainer/agent:${PORTAINER_VERSION}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - portainer-agent
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux

  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer-data:/data
    networks:
      - portainer-agent
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${DOMAIN_PORTAINER}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls=true"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  portainer-agent:
    driver: overlay
  network_swarm_public:
    external: true

volumes:
  portainer-data:
    driver: local
EOF

    cd /opt/portainer
    docker stack deploy -c docker-compose.yml portainer
    
    log_info "Portainer implantado: https://${DOMAIN_PORTAINER}"
    wait_for_service "portainer_portainer" 30
}

#==============================================================================
# Instalação PostgreSQL
#==============================================================================

setup_postgres() {
    log_step "INSTALANDO POSTGRESQL 15"
    
    mkdir -p /opt/postgres
    docker volume create postgres_data
    
    cat > /opt/postgres/docker-compose.yml <<EOF
version: '3.8'

services:
  postgres:
    image: pgvector/pgvector:pg${POSTGRES_VERSION}
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
      TZ: America/Sao_Paulo
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

volumes:
  postgres_data:
    external: true

networks:
  network_swarm_public:
    external: true
EOF

    cd /opt/postgres
    docker stack deploy -c docker-compose.yml postgres
    
    log_info "PostgreSQL implantado"
    
    # Aguardar PostgreSQL iniciar
    echo -n "Aguardando PostgreSQL "
    sleep 10
    for i in {1..20}; do
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Criar database para N8N
    log_info "Criando database ${N8N_DB_NAME}..."
    
    MAX_TRIES=15
    for i in $(seq 1 $MAX_TRIES); do
        CONTAINER_ID=$(docker ps -q -f name=postgres_postgres 2>/dev/null | head -n1)
        if [ -n "$CONTAINER_ID" ]; then
            if docker exec "$CONTAINER_ID" psql -U postgres -c "CREATE DATABASE ${N8N_DB_NAME};" 2>/dev/null; then
                log_info "Database ${N8N_DB_NAME} criado com sucesso"
                break
            fi
        fi
        
        if [ $i -eq $MAX_TRIES ]; then
            log_warn "Database não criado automaticamente. Será criado pelo N8N na primeira execução."
        fi
        sleep 3
    done
}

#==============================================================================
# Instalação MySQL
#==============================================================================

setup_mysql() {
    log_step "INSTALANDO MYSQL 8.0 (PERCONA)"
    
    mkdir -p /opt/mysql
    docker volume create mysql_data
    
    cat > /opt/mysql/docker-compose.yml <<EOF
version: '3.8'

services:
  mysql:
    image: percona/percona-server:${MYSQL_VERSION}
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      TZ: America/Sao_Paulo
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - network_swarm_public
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --default-authentication-plugin=mysql_native_password
      - --max-allowed-packet=512M
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

volumes:
  mysql_data:
    external: true

networks:
  network_swarm_public:
    external: true
EOF

    cd /opt/mysql
    docker stack deploy -c docker-compose.yml mysql
    
    log_info "MySQL implantado"
    wait_for_service "mysql_mysql" 30
}

#==============================================================================
# Instalação phpMyAdmin
#==============================================================================

setup_phpmyadmin() {
    log_step "INSTALANDO PHPMYADMIN"
    
    mkdir -p /opt/phpmyadmin
    
    cat > /opt/phpmyadmin/docker-compose.yml <<EOF
version: '3.8'

services:
  phpmyadmin:
    image: phpmyadmin:${PHPMYADMIN_VERSION}
    environment:
      PMA_HOST: mysql
      PMA_PORT: 3306
      UPLOAD_LIMIT: 512M
      MEMORY_LIMIT: 512M
      MAX_EXECUTION_TIME: 600
      TZ: America/Sao_Paulo
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.phpmyadmin.rule=Host(\`${DOMAIN_PHPMYADMIN}\`)"
        - "traefik.http.routers.phpmyadmin.entrypoints=websecure"
        - "traefik.http.routers.phpmyadmin.tls=true"
        - "traefik.http.routers.phpmyadmin.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.phpmyadmin.loadbalancer.server.port=80"

networks:
  network_swarm_public:
    external: true
EOF

    cd /opt/phpmyadmin
    docker stack deploy -c docker-compose.yml phpmyadmin
    
    log_info "phpMyAdmin implantado: https://${DOMAIN_PHPMYADMIN}"
    wait_for_service "phpmyadmin_phpmyadmin" 30
}

#==============================================================================
# Instalação N8N (Automação)
#==============================================================================

setup_n8n() {
    log_step "INSTALANDO N8N COM FILA E WORKERS"
    
    mkdir -p /opt/n8n
    docker volume create n8n_data
    
    cat > /opt/n8n/docker-compose.yml <<EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 512mb --maxmemory-policy allkeys-lru
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  n8n_admin:
    image: n8nio/n8n:${N8N_VERSION}
    command: start
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=${N8N_DB_NAME}
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${DOMAIN_N8N}
      - N8N_EDITOR_BASE_URL=https://${DOMAIN_N8N}/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_WEBHOOK}/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=1
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336
      - N8N_DIAGNOSTICS_ENABLED=false
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_admin.rule=Host(\`${DOMAIN_N8N}\`)"
        - "traefik.http.routers.n8n_admin.entrypoints=websecure"
        - "traefik.http.routers.n8n_admin.priority=2"
        - "traefik.http.routers.n8n_admin.tls=true"
        - "traefik.http.routers.n8n_admin.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_admin.service=n8n_admin"
        - "traefik.http.services.n8n_admin.loadbalancer.server.port=5678"

  n8n_webhook:
    image: n8nio/n8n:${N8N_VERSION}
    command: webhook
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=${N8N_DB_NAME}
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${DOMAIN_N8N}
      - N8N_EDITOR_BASE_URL=https://${DOMAIN_N8N}/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_WEBHOOK}/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=1
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 2
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_webhook.rule=Host(\`${DOMAIN_WEBHOOK}\`)"
        - "traefik.http.routers.n8n_webhook.entrypoints=websecure"
        - "traefik.http.routers.n8n_webhook.priority=1"
        - "traefik.http.routers.n8n_webhook.tls=true"
        - "traefik.http.routers.n8n_webhook.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_webhook.service=n8n_webhook"
        - "traefik.http.services.n8n_webhook.loadbalancer.server.port=5678"

  n8n_worker:
    image: n8nio/n8n:${N8N_VERSION}
    command: worker --concurrency=10
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=${N8N_DB_NAME}
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=1
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 3
      placement:
        constraints:
          - node.role == manager

volumes:
  n8n_data:
    external: true

networks:
  network_swarm_public:
    external: true
EOF

    cd /opt/n8n
    docker stack deploy -c docker-compose.yml n8n
    
    log_info "N8N implantado: https://${DOMAIN_N8N}"
    log_info "N8N Webhook: https://${DOMAIN_WEBHOOK}"
}

#==============================================================================
# Geração do Resumo Final
#==============================================================================

generate_summary() {
    log_step "GERANDO RESUMO DA INSTALAÇÃO"
    
    SERVER_IP=$(hostname -I | awk '{print $1}')
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}')
    
    cat > /root/THE-installation-summary.txt <<EOF
================================================================================
                    THE - RESUMO DA INSTALAÇÃO
================================================================================

Data e Hora: $(date '+%d/%m/%Y %H:%M:%S')
Servidor IP: ${SERVER_IP}
Sistema: Debian $(lsb_release -rs)
Docker: ${DOCKER_VERSION}
Traefik: ${TRAEFIK_VERSION}

================================================================================
                              ACESSOS
================================================================================

Portainer:    https://${DOMAIN_PORTAINER}
phpMyAdmin:   https://${DOMAIN_PHPMYADMIN}
N8N Admin:    https://${DOMAIN_N8N}
N8N Webhook:  https://${DOMAIN_WEBHOOK}

IMPORTANTE: Os certificados SSL podem levar 2-5 minutos para serem gerados
na primeira vez. Se encontrar erro de certificado, aguarde alguns minutos.

================================================================================
                           CREDENCIAIS
================================================================================

━━━ POSTGRESQL ━━━
Host:         postgres (interno) ou ${SERVER_IP}:5432 (externo)
Database:     ${N8N_DB_NAME} (N8N)
Usuário:      postgres
Senha:        ${POSTGRES_PASSWORD}

━━━ MYSQL ━━━
Host:         mysql (interno) ou ${SERVER_IP}:3306 (externo)
Usuário:      root
Senha:        ${MYSQL_ROOT_PASSWORD}

━━━ N8N ━━━
Database:     ${N8N_DB_NAME}
DB User:      postgres
DB Password:  ${POSTGRES_PASSWORD}
Encryption:   ${N8N_ENCRYPTION_KEY}

━━━ REDIS ━━━
Host:         redis
Password:     ${REDIS_PASSWORD}

================================================================================
                        CONFIGURAÇÃO DNS
================================================================================

Aponte os seguintes registros A para o IP: ${SERVER_IP}

${DOMAIN_PORTAINER}      → ${SERVER_IP}
${DOMAIN_PHPMYADMIN}     → ${SERVER_IP}
${DOMAIN_N8N}            → ${SERVER_IP}
${DOMAIN_WEBHOOK}        → ${SERVER_IP}

Para verificar DNS:
  dig ${DOMAIN_N8N} +short

================================================================================
                        COMANDOS ÚTEIS
================================================================================

━━━ GERENCIAMENTO DE STACKS ━━━
Ver stacks:              docker stack ls
Ver serviços:            docker service ls
Ver containers:          docker ps

━━━ LOGS ━━━
Logs Traefik:            docker service logs traefik_traefik -f
Logs Portainer:          docker service logs portainer_portainer -f
Logs N8N Admin:          docker service logs n8n_n8n_admin -f
Logs N8N Worker:         docker service logs n8n_n8n_worker -f
Logs PostgreSQL:         docker service logs postgres_postgres -f
Logs MySQL:              docker service logs mysql_mysql -f

━━━ GESTÃO DE SERVIÇOS ━━━
Reiniciar serviço:       docker service update --force <nome_servico>
Escalar workers N8N:     docker service scale n8n_n8n_worker=5
Remover stack:           docker stack rm <nome_stack>

━━━ VERIFICAR CERTIFICADOS SSL ━━━
Ver certificados:        cat /opt/traefik/letsencrypt/acme.json
Forçar renovação:        docker service update --force traefik_traefik

━━━ BACKUP E MANUTENÇÃO ━━━
Backup PostgreSQL:       docker exec \$(docker ps -qf name=postgres) \\
                         pg_dump -U postgres ${N8N_DB_NAME} > backup.sql
Backup MySQL:            docker exec \$(docker ps -qf name=mysql) \\
                         mysqldump -u root -p${MYSQL_ROOT_PASSWORD} --all-databases > backup.sql

================================================================================
                     DIRETÓRIOS DE CONFIGURAÇÃO
================================================================================

Traefik:      /opt/traefik/
Portainer:    /opt/portainer/
PostgreSQL:   /opt/postgres/
MySQL:        /opt/mysql/
phpMyAdmin:   /opt/phpmyadmin/
N8N:          /opt/n8n/

Certificados SSL: /opt/traefik/letsencrypt/acme.json

================================================================================
                     ARQUITETURA N8N
================================================================================

O N8N está configurado com alta disponibilidade:

- 1x N8N Admin     - Interface de gerenciamento
- 2x N8N Webhook   - Processamento de webhooks (load balanced)
- 3x N8N Worker    - Processamento de filas em background
- 1x Redis         - Gerenciamento de filas

Para escalar workers conforme demanda:
  docker service scale n8n_n8n_worker=5

================================================================================
                     TROUBLESHOOTING
================================================================================

━━━ CERTIFICADOS SSL NÃO GERADOS ━━━
1. Verifique se DNS está apontando: dig ${DOMAIN_N8N} +short
2. Verifique se porta 80 está acessível externamente
3. Veja logs do Traefik: docker service logs traefik_traefik -f
4. Aguarde 5-10 minutos e tente novamente

━━━ SERVIÇO NÃO INICIANDO ━━━
1. Ver logs: docker service logs <nome_servico> -f
2. Ver tarefas: docker service ps <nome_servico> --no-trunc
3. Reiniciar: docker service update --force <nome_servico>

━━━ N8N NÃO CONECTA NO POSTGRES ━━━
1. Verificar se database existe:
   docker exec \$(docker ps -qf name=postgres) psql -U postgres -l
2. Se não existir, criar:
   docker exec \$(docker ps -qf name=postgres) \\
   psql -U postgres -c "CREATE DATABASE ${N8N_DB_NAME};"

━━━ PERFORMANCE ━━━
- Verificar uso de recursos: htop
- Ver logs de performance: docker stats
- Ajustar workers N8N conforme carga

================================================================================
                     PRÓXIMOS PASSOS
================================================================================

1. ✓ Configurar DNS apontando para ${SERVER_IP}
2. ✓ Aguardar 5-10 minutos para certificados SSL
3. → Acessar Portainer e criar senha de admin
4. → Acessar N8N e criar primeiro usuário
5. → Acessar phpMyAdmin (user: root, senha acima)

================================================================================
                     SEGURANÇA
================================================================================

⚠️  IMPORTANTE - Ações de segurança recomendadas:

1. Altere as senhas padrão imediatamente
2. Configure backup automático dos databases
3. Monitore os logs regularmente
4. Mantenha o Docker atualizado: apt-get upgrade docker-ce
5. Configure alertas de monitoramento

================================================================================
                     SUPORTE
================================================================================

Email SSL: ${EMAIL_SSL}
Este arquivo: /root/THE-installation-summary.txt

Para suporte adicional, consulte a documentação:
- Traefik: https://doc.traefik.io/traefik/
- N8N: https://docs.n8n.io/
- Docker Swarm: https://docs.docker.com/engine/swarm/

================================================================================
                     FIM DO RESUMO
================================================================================
EOF

    # Exibir resumo
    cat /root/THE-installation-summary.txt
    
    log_info "Resumo completo salvo em: /root/THE-installation-summary.txt"
}

#==============================================================================
# Verificações Finais
#==============================================================================

final_checks() {
    log_step "VERIFICAÇÕES FINAIS"
    
    echo ""
    echo -e "${CYAN}Status dos Serviços:${NC}"
    echo ""
    docker service ls
    
    echo ""
    echo -e "${CYAN}Verificando DNS:${NC}"
    echo ""
    
    for domain in "$DOMAIN_PORTAINER" "$DOMAIN_PHPMYADMIN" "$DOMAIN_N8N" "$DOMAIN_WEBHOOK"; do
        IP=$(dig +short "$domain" | head -n1)
        if [ -n "$IP" ]; then
            log_info "$domain → $IP ✓"
        else
            log_warn "$domain → Não configurado ainda"
        fi
    done
    
    echo ""
    log_info "Monitorar geração de certificados:"
    echo -e "  ${BLUE}docker service logs traefik_traefik -f${NC}"
}

#==============================================================================
# Execução Principal
#==============================================================================

main() {
    echo ""
    check_root
    check_os
    
    # Coleta de informações
    collect_domains
    generate_credentials
    
    # Confirmação
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Confirma a instalação com as configurações acima?${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -n "Digite 's' para continuar ou 'n' para cancelar: "
    read -r CONFIRM
    
    if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
        log_error "Instalação cancelada pelo usuário"
    fi
    
    # Instalação do sistema base
    setup_swap
    install_dependencies
    install_docker
    setup_docker_swarm
    create_networks
    setup_firewall
    
    # Instalação dos serviços (ordem importa!)
    setup_traefik       # 1º - Proxy reverso + SSL
    sleep 20            # Aguardar Traefik estabilizar
    
    setup_postgres      # 2º - Database para N8N
    sleep 15            # Aguardar Postgres estabilizar
    
    setup_mysql         # 3º - Database geral
    sleep 15            # Aguardar MySQL estabilizar
    
    setup_portainer     # 4º - Gerenciamento (depende de Traefik)
    sleep 10
    
    setup_phpmyadmin    # 5º - Gerenciamento MySQL (depende de MySQL)
    sleep 10
    
    setup_n8n           # 6º - N8N por último (depende de tudo)
    sleep 15
    
    # Finalização
    generate_summary
    final_checks
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}        INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}➜ Configure os DNS apontando para o servidor${NC}"
    echo -e "${CYAN}➜ Aguarde 5-10 minutos para os certificados SSL${NC}"
    echo -e "${CYAN}➜ Resumo completo: cat /root/THE-installation-summary.txt${NC}"
    echo ""
    echo -e "${YELLOW}Monitorar certificados em tempo real:${NC}"
    echo -e "  ${BLUE}docker service logs traefik_traefik -f | grep -i acme${NC}"
    echo ""
}

# Executar instalação
main
