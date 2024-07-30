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
