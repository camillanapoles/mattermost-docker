
#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cat << "EOF"
   _____ _   _ __  __ ______ ____  
  / ____| \ | |  \/  |  ____|  _ \ 
 | |    |  \| | \  / | |__  | |_) |
 | |    | . ` | |\/| |  __| |  _ < 
 | |____| |\  | |  | | |    | |_) |
  \_____|_| \_|_|  |_|_|    |____/ 
                                   
 Mattermost Installation Script
EOF

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Função para imprimir mensagens de erro
error() {
    echo -e "${RED}Erro: $1${NC}" >&2
    exit 1
}

# Função para imprimir mensagens de sucesso
success() {
    echo -e "${GREEN}Sucesso: $1${NC}"
}

# Função para imprimir mensagens de aviso
warning() {
    echo -e "${YELLOW}Aviso: $1${NC}"
}

# Verificar se o Docker está instalado
if ! command_exists docker; then
    error "Docker não está instalado. Por favor, instale o Docker antes de continuar."
fi

# Verificar se o Docker Compose está instalado
if ! command_exists docker-compose; then
    error "Docker Compose não está instalado. Por favor, instale o Docker Compose antes de continuar."
fi

# Remover pastas anteriores
warning "Removendo pastas anteriores..."
docker-compose down 
sudo rm -rf backup nginx volumes secrets config backup docker-compose.yml backup.sh backups certbot .gitlab-ci.yml .env 


# Verificar se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este script como root ou usando sudo."
  exit 1
fi

# Função para gerar senhas aleatórias
generate_password() {
  openssl rand -base64 32 | tr -d /=+ | cut -c -16
}

# Gerar senhas aleatórias
MM_PASSWORD=$(generate_password)
POSTGRES_PASSWORD=$(generate_password)

# Criar arquivo .env
cat << EOF > .env
# Configurações Mattermost
MATTERMOST_IMAGE=mattermost/mattermost-team-edition:latest
MM_USERNAME=mmuser
MM_PASSWORD=$MM_PASSWORD
MM_DBNAME=mattermost

# Configurações PostgreSQL
POSTGRES_IMAGE=postgres:13
POSTGRES_USER=mmuser
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=mattermost

# Configurações Nginx
DOCKER_NGINX_IMAGE=nginx:1.25.1-alpine

# Configurações Certbot
CERTBOT_IMAGE=certbot/certbot

# Configurações Watchtower
WATCHTOWER_IMAGE=containrrr/watchtower

# Domínio e Email
DOMAIN=team.cnmfs.me
EMAIL=dev@cnmfs.me

# Definir variáveis
DOMAIN="dev.cnmfs.me"
EMAIL="admin@cnmfs.me"
MATTERMOST_VERSION="7.10.0"
FOCALBOARD_VERSION="7.10.0"
POSTGRES_DB="mattermost"
ENABLE_ELASTICSEARCH=true
ENABLE_FOCALBOARD=true
EOF

success "Arquivo .env criado com sucesso."

# Instalar dependências
#apt-get update
#apt-get install -y docker.io docker-compose curl

# Criar diretórios necessários
echo "Criar diretórios necessários..."
mkdir -p config/nginx config/mattermost volumes/db volumes/mattermost/data volumes/mattermost/logs volumes/mattermost/plugins volumes/mattermost/client-plugins volumes/nginx volumes/certbot/conf volumes/certbot/www volumes/elasticsearch volumes/prometheus volumes/grafana volumes/gitlab/{config,logs,data} volumes/jenkins_home volumes/vault secrets backups

# Gerar senhas e salvar em arquivos de secrets
echo "mmuser" > ./secrets/db_user.txt
generate_password > ./secrets/db_password.txt
generate_password > ./secrets/grafana_admin_password.txt
generate_password > ./secrets/gitlab_root_password.txt
generate_password > ./secrets/jenkins_admin_password.txt
generate_password > ./secrets/vault_root_token.txt
generate_password > ./secrets/mattermost_smtp_password.txt

# Criar arquivo docker-compose.yml
cat > docker-compose.yml <<EOL


services:
  db:
    image: postgres:13
    container_name: mattermost-db
    environment:
      - POSTGRES_USER_FILE=/run/secrets/db_user
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - ./volumes/db:/var/lib/postgresql/data
    networks:
      - mattermost-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \$\$(cat /run/secrets/db_user) -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  mattermost:
    image: mattermost/mattermost-team-edition:\${MATTERMOST_VERSION}
    container_name: mattermost
    depends_on:
      - db
    environment:
      - MM_USERNAME_FILE=/run/secrets/db_user
      - MM_PASSWORD_FILE=/run/secrets/db_password
      - MM_DBNAME=\${POSTGRES_DB}
      - MM_SQLSETTINGS_DATASOURCE=postgres://\$\$(cat /run/secrets/db_user):\$\$(cat /run/secrets/db_password)@db:5432/\${POSTGRES_DB}?sslmode=disable&connect_timeout=10
      - MM_SERVICESETTINGS_SITEURL=https://\$DOMAIN
      - MM_EMAILSETTINGS_SMTPSERVER=smtp.example.com
      - MM_EMAILSETTINGS_SMTPPORT=587
      - MM_EMAILSETTINGS_SMTPUSERNAME=mattermost@example.com
      - MM_EMAILSETTINGS_SMTPPASSWORD_FILE=/run/secrets/mattermost_smtp_password
      - MM_EMAILSETTINGS_ENABLESMTPAUTH=true
      - MM_EMAILSETTINGS_CONNECTIONSECURITY=TLS
      - MM_ELASTICSEARCHSETTINGS_ENABLEINDEXING=\${ENABLE_ELASTICSEARCH}
      - MM_FOCALBOARDSETTINGS_ENABLE=\${ENABLE_FOCALBOARD}
      - MM_INTEGRATIONSETTINGS_ENABLEINCOMINGWEBHOOKS=true
      - MM_INTEGRATIONSETTINGS_ENABLEOUTGOINGWEBHOOKS=true
    volumes:
      - ./config/mattermost:/mattermost/config
      - ./volumes/mattermost/data:/mattermost/data
      - ./volumes/mattermost/logs:/mattermost/logs
      - ./volumes/mattermost/plugins:/mattermost/plugins
      - ./volumes/mattermost/client-plugins:/mattermost/client/plugins
    networks:
      - mattermost-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8065/api/v4/system/ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

  nginx:
    image: \${DOCKER_NGINX_IMAGE}
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./volumes/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./volumes/certbot/conf:/etc/letsencrypt
      - ./volumes/certbot/www:/var/www/certbot
    command: "/bin/sh -c 'while :; do sleep 6h & wait \$\${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"
    depends_on:
      - mattermost
    networks:
      - mattermost-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 10s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  certbot:
    image: \${CERTBOT_IMAGE}
    container_name: certbot
    volumes:
      - ./volumes/certbot/conf:/etc/letsencrypt
      - ./volumes/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait \$\${!}; done;'"
    command: certonly --webroot -w /var/www/certbot --force-renewal --email \${EMAIL} -d \$DOMAIN --agree-tos
    depends_on:
      - nginx

  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 30
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.14.0
    container_name: mattermost-elasticsearch
    environment:
      - discovery.type=single-node
    volumes:
      - ./volumes/elasticsearch:/usr/share/elasticsearch/data
    networks:
      - mattermost-network
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G

  prometheus:
    image: prom/prometheus:v2.30.3
    container_name: mattermost-prometheus
    volumes:
      - ./config/prometheus:/etc/prometheus
      - ./volumes/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      - mattermost-network
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  grafana:
    image: grafana/grafana:8.2.2
    container_name: mattermost-grafana
    volumes:
      - ./volumes/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_admin_password
    networks:
      - mattermost-network
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: mattermost-gitlab
    hostname: gitlab.\$DOMAIN
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://gitlab.\$DOMAIN'
        gitlab_rails['initial_root_password'] = File.read('/run/secrets/gitlab_root_password').strip
    ports:
      - "8443:443"
      - "8080:80"
      - "8022:22"
    volumes:
      - ./volumes/gitlab/config:/etc/gitlab
      - ./volumes/gitlab/logs:/var/log/gitlab
      - ./volumes/gitlab/data:/var/opt/gitlab
    networks:
      - mattermost-network
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

  jenkins:
    image: jenkins/jenkins:lts
    container_name: mattermost-jenkins
    environment:
      - JENKINS_OPTS="--argumentsRealm.passwd.admin=\$\$(cat /run/secrets/jenkins_admin_password) --argumentsRealm.roles.admin=admin"
    ports:
      - "8090:8080"
    volumes:
      - ./volumes/jenkins_home:/var/jenkins_home
    networks:
      - mattermost-network
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G

  vault:
    image: vault:1.8.3
    container_name: mattermost-vault
    cap_add:
      - IPC_LOCK
    ports:
      - "8200:8200"
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID_FILE=/run/secrets/vault_root_token
    volumes:
      - ./volumes/vault:/vault/file
    command: server -dev
    networks:
      - mattermost-network
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

networks:
  mattermost-network:
    name: mattermost-network

secrets:
  db_user:
    file: ./secrets/db_user.txt
  db_password:
    file: ./secrets/db_password.txt
  grafana_admin_password:
    file: ./secrets/grafana_admin_password.txt
  gitlab_root_password:
    file: ./secrets/gitlab_root_password.txt
  jenkins_admin_password:
    file: ./secrets/jenkins_admin_password.txt
  vault_root_token:
    file: ./secrets/vault_root_token.txt
  mattermost_smtp_password:
    file: ./secrets/mattermost_smtp_password.txt
EOL

success "Arquivo docker-compose.yml criado com sucesso."

# Criar nginx.conf temporário (sem SSL)
mkdir -p ./config/nginx
cat << EOF > ./config/nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name \$DOMAIN;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 200 'Waiting for SSL certificate...';
        }
    }
}
EOF

success "Arquivo ./config/nginx/nginx.conf criado com sucesso."

# Criar arquivo de configuração do Nginx
cat << EOF > ./config/nginx/nginx.conf
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}
EOF

success "Arquivo ./config/nginx/nginx.conf criado com sucesso."

# Criar arquivo de configuração do site Nginx com certificado SSL temporário
cat << EOF > ./volumes/nginx/conf.d/mattermost.conf
server {
    listen 80;
    server_name \$DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name \$DOMAIN;

    ssl_certificate /etc/nginx/conf.d/cert.pem;
    ssl_certificate_key /etc/nginx/conf.d/key.pem;

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-NginX-Proxy true;

        proxy_pass http://mattermost:8065;
        proxy_redirect off;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

success "Arquivo volumes/nginx/conf.d/mattermost.conf criado com sucesso."

# Gerar certificado SSL temporário
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout volumes/nginx/conf.d/key.pem -out volumes/nginx/conf.d/cert.pem -subj "/CN=localhost"

success "Certificado SSL temporário gerado com sucesso."

# Iniciar os contêineres
docker-compose up -d

# Verificar se os contêineres estão rodando
if docker-compose ps | grep -q "Up"; then
    success "Todos os contêineres estão rodando."
else
    error "Alguns contêineres não iniciaram corretamente. Por favor, verifique os logs com 'docker-compose logs'."
fi

# Instruções finais
echo "==============================================="
echo "Instalação concluída!"
echo "Por favor, configure seu DNS para apontar \$DOMAIN para o IP deste servidor."
echo "Depois disso, você poderá acessar o Mattermost em https://\$DOMAIN"
echo "Para obter um certificado SSL válido, execute:"
echo "docker-compose run --rm volumes/certbot certonly --webroot --webroot-path /var/www/certbot -d \$DOMAIN"
echo "Em seguida, atualize o arquivo nginx/conf.d/mattermost.conf com os novos caminhos do certificado e reinicie o Nginx."
echo "==============================================="

# Backup automático do banco de dados e arquivos
echo "Criando script de backup automático..."

cat << 'EOF' > backup.sh
#!/bin/bash

BACKUP_DIR="./backups"
DB_BACKUP="\${BACKUP_DIR}/db_backup_\$(date +%Y%m%d%H%M%S).sql"
FILES_BACKUP="\${BACKUP_DIR}/files_backup_\$(date +%Y%m%d%H%M%S).tar.gz"

# Criar diretório de backup se não existir
mkdir -p \${BACKUP_DIR}

# Backup do banco de dados PostgreSQL
docker exec mattermost-db pg_dump -U mmuser mattermost > \${DB_BACKUP}

# Backup dos arquivos do Mattermost
tar -czvf \${FILES_BACKUP} volumes/mattermost

echo -e "${GREEN}Backup concluído! Arquivos de backup salvos em \${BACKUP_DIR}.${NC}"
EOF

chmod +x backup.sh

echo "Script de backup automático criado com sucesso."

# Criar arquivo de configuração do GitLab CI/CD
echo "Criando configuração básica para pipelines de CI/CD no GitLab..."

cat << 'EOF' > .gitlab-ci.yml
stages:
  - build
  - test
  - deploy

build:
  stage: build
  script:
    - echo "Building the project..."

test:
  stage: test
  script:
    - echo "Running tests..."

deploy:
  stage: deploy
  script:
    - echo "Deploying the project..."
EOF

success "Arquivo .gitlab-ci.yml criado com sucesso."

# Criar script de configuração do Vault
echo "Criando script de inicialização e configuração automática do Vault..."

cat << 'EOF' > configure_vault.sh
#!/bin/bash

VAULT_ADDR="http://127.0.0.1:8200"
VAULT_TOKEN=$(cat ./secrets/vault_root_token.txt)

# Login no Vault
vault login $VAULT_TOKEN

# Habilitar o secret engine kv
vault secrets enable -path=secret kv

# Criar um segredo de exemplo
vault kv put secret/my-secret value="my secret value"

echo -e "${GREEN}Vault configurado com sucesso.${NC}"
EOF

chmod +x ./*.sh

echo "Script de configuração do Vault criado com sucesso."




