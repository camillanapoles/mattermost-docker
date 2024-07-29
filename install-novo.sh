#!/bin/bash

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar se o Docker está instalado
if ! command_exists docker; then
    echo "Docker não está instalado. Por favor, instale o Docker primeiro."
    exit 1
fi

# Verificar se o Docker Compose está instalado
if ! command_exists docker-compose; then
    echo "Docker Compose não está instalado. Por favor, instale o Docker Compose primeiro."
    exit 1
fi

# Solicitar o domínio
read -p "Digite o domínio para o Mattermost (ex: mattermost.seudominio.com): " DOMAIN

# Solicitar o email para o Let's Encrypt
read -p "Digite o email para o Let's Encrypt: " EMAIL

# Criar diretórios necessários
mkdir -p ./volumes/app/mattermost/{config,data,logs,plugins,client/plugins,bleve-indexes}
mkdir -p ./volumes/web/certbot/{conf,www}

# Criar arquivo .env
cat << EOF > .env
DOMAIN=$DOMAIN
DOCKER_MATTERMOST_IMAGE=mattermost/mattermost-team-edition:release-7.10
DOCKER_NGINX_IMAGE=nginx:1.25.1-alpine
DOCKER_POSTGRES_IMAGE=postgres:15.3-alpine
EOF

# Criar docker-compose.yml
cat << EOF > docker-compose.yml
services:
  postgres:
    image: \${DOCKER_POSTGRES_IMAGE}
    container_name: postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=mmuser
      - POSTGRES_PASSWORD=mmuser_password
      - POSTGRES_DB=mattermost
    volumes:
      - ./volumes/db/var/lib/postgresql/data:/var/lib/postgresql/data
    networks:
      - mm-network

  mattermost:
    image: \${DOCKER_MATTERMOST_IMAGE}
    container_name: mattermost
    restart: unless-stopped
    depends_on:
      - postgres
    environment:
      - MM_USERNAME=mmuser
      - MM_PASSWORD=mmuser_password
      - MM_DBNAME=mattermost
      - MM_SQLSETTINGS_DRIVERNAME=postgres
      - MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:mmuser_password@postgres:5432/mattermost?sslmode=disable&connect_timeout=10
    volumes:
      - ./volumes/app/mattermost/config:/mattermost/config:rw
      - ./volumes/app/mattermost/data:/mattermost/data:rw
      - ./volumes/app/mattermost/logs:/mattermost/logs:rw
      - ./volumes/app/mattermost/plugins:/mattermost/plugins:rw
      - ./volumes/app/mattermost/client/plugins:/mattermost/client/plugins:rw
      - ./volumes/app/mattermost/bleve-indexes:/mattermost/bleve-indexes:rw
    networks:
      - mm-network

  nginx:
    image: \${DOCKER_NGINX_IMAGE}
    container_name: nginx
    restart: unless-stopped
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./volumes/web/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./volumes/web/certbot/conf:/etc/letsencrypt:ro
      - ./volumes/web/certbot/www:/var/www/certbot:ro
    command: "/bin/sh -c 'while :; do sleep 6h & wait \$\${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"
    networks:
      - mm-network

  certbot:
    image: certbot/certbot
    container_name: certbot
    restart: unless-stopped
    volumes:
      - ./volumes/web/certbot/conf:/etc/letsencrypt
      - ./volumes/web/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait \$\${!}; done;'"

networks:
  mm-network:
    driver: bridge
EOF

# Criar nginx.conf temporário (sem SSL)
mkdir -p ./volumes/web/nginx
cat << EOF > ./volumes/web/nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name $DOMAIN;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 200 'Waiting for SSL certificate...';
        }
    }
}
EOF

# Iniciar o Nginx
docker-compose up -d nginx

# Aguardar o Nginx iniciar
sleep 10

# Obter o certificado SSL
docker-compose run --rm certbot certonly --webroot -w /var/www/certbot -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email --force-renewal

# Criar nginx.conf final (com SSL)
cat << EOF > ./volumes/web/nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream mattermost {
        server mattermost:8065;
        keepalive 32;
    }

    server {
        listen 80;
        server_name $DOMAIN;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

        location / {
            proxy_pass http://mattermost;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Frame-Options SAMEORIGIN;
            proxy_set_header Host \$http_host;

            client_max_body_size 50M;
            proxy_buffering off;

            location ~ /api/v[0-9]+/(users/)?websocket\$ {
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection "upgrade";
                client_max_body_size 50M;
                proxy_set_header Host \$http_host;
                proxy_http_version 1.1;
                proxy_buffering off;
                proxy_pass http://mattermost;
            }
        }
    }
}
EOF

# Reiniciar o Nginx para aplicar as configurações SSL
docker-compose restart nginx

# Iniciar todos os serviços
docker-compose up -d

echo "Instalação concluída. Acesse https://$DOMAIN para configurar o Mattermost
."

