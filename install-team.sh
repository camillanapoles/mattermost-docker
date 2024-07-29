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
if ! command -v docker &> /dev/null; then
    error "Docker não está instalado. Por favor, instale o Docker antes de continuar."
fi

# Verificar se o Docker Compose está instalado
if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose não está instalado. Por favor, instale o Docker Compose antes de continuar."
fi

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funções para mensagens
error() {
    echo -e "${RED}Erro: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}Sucesso: $1${NC}"
}

warning() {
    echo -e "${YELLOW}Aviso: $1${NC}"
}

# Verificar pré-requisitos
command -v docker >/dev/null 2>&1 || error "Docker não está instalado. Por favor, instale o Docker antes de continuar."
command -v docker-compose >/dev/null 2>&1 || error "Docker Compose não está instalado. Por favor, instale o Docker Compose antes de continuar."

# Remover pastas anteriores
warning "Removendo pastas anteriores..."
docker-compose down 
sudo rm -rf volumes
sudo rm -f .env docker-compose.yml

# Criar diretórios necessários
mkdir -p volumes/mattermost/{config,data,logs,plugins,client-plugins} volumes/postgres volumes/nginx/conf.d volumes/certbot/{conf,www}

# Gerar senhas aleatórias
MM_PASSWORD=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32)

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
NGINX_IMAGE=nginx:latest

# Configurações Certbot
CERTBOT_IMAGE=certbot/certbot

# Configurações Watchtower
WATCHTOWER_IMAGE=containrrr/watchtower

# Domínio e Email
DOMAIN=team.cnmfs.me
EMAIL=dev@cnmfs.me
EOF 

success "Arquivo .env criado com sucesso."


# Criar arquivo docker-compose.yml
cat << EOF > docker-compose.yml
version: '3'

services:
  mattermost:
    image: \${MATTERMOST_IMAGE}
    container_name: mattermost
    depends_on:
      - postgres
    environment:
      - MM_USERNAME=\${MM_USERNAME}
      - MM_PASSWORD=\${MM_PASSWORD}
      - MM_DBNAME=\${MM_DBNAME}
      - MM_SQLSETTINGS_DRIVERNAME=postgres
      - MM_SQLSETTINGS_DATASOURCE=postgres://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}?sslmode=disable&connect_timeout=10
    volumes:
      - ./volumes/mattermost/config:/mattermost/config:rw
      - ./volumes/mattermost/data:/mattermost/data:rw
      - ./volumes/mattermost/logs:/mattermost/logs:rw
      - ./volumes/mattermost/plugins:/mattermost/plugins:rw
      - ./volumes/mattermost/client-plugins:/mattermost/client/plugins:rw
    ports:
      - "8065:8065"
    restart: unless-stopped

  postgres:
    image: \${POSTGRES_IMAGE}
    container_name: postgres
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - ./volumes/postgres:/var/lib/postgresql/data
    restart: unless-stopped

  nginx:
    image: \${NGINX_IMAGE}
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    command: "/bin/sh -c 'while :; do sleep 6h & wait \$\${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"
    depends_on:
      - mattermost
    restart: unless-stopped

  certbot:
    image: \${CERTBOT_IMAGE}
    container_name: certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait \$\${!}; done;'"

  watchtower:
    image: \${WATCHTOWER_IMAGE}
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 30
    restart: unless-stopped
EOF

success "Arquivo docker-compose.yml criado com sucesso."

# Criar arquivo de configuração do Nginx
cat << EOF > nginx/nginx.conf
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
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    include /etc/nginx/conf.d/*.conf;
}
EOF

success "Arquivo nginx/nginx.conf criado com sucesso."

# Criar arquivo de configuração do site Nginx com certificado SSL temporário
cat << EOF > nginx/conf.d/mattermost.conf
server {
    listen 80;
    server_name \${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name \${DOMAIN};

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

success "Arquivo nginx/conf.d/mattermost.conf criado com sucesso."

# Gerar certificado SSL temporário
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx/conf.d/key.pem -out nginx/conf.d/cert.pem -subj "/CN=localhost"

success "Certificado SSL temporário gerado com sucesso."

# Solicitar informações do usuário
read -p "Digite o domínio para o Mattermost (ex: mattermost.seudominio.com): " domain
read -p "Digite o endereço de e-mail para o Let's Encrypt: " email

# Atualizar o arquivo .env com as informações fornecidas
#sed -i "s/DOMAIN=.*/DOMAIN=$domain/" .env
#sed -i "s/EMAIL=.*/EMAIL=$email/" .env

success "Arquivo .env atualizado com o domínio e e-mail fornecidos."

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
echo "Por favor, configure seu DNS para apontar $domain para o IP deste servidor."
echo "Depois disso, você poderá acessar o Mattermost em https://$domain"
echo "Para obter um certificado SSL válido, execute:"
echo "docker-compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot -d $domain"
echo "Em seguida, atualize o arquivo nginx/conf.d/mattermost.conf com os novos caminhos do certificado e reinicie o Nginx."
echo "==============================================="
