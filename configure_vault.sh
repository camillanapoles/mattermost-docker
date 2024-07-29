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
