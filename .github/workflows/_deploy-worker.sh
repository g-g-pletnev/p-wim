#!/bin/bash
set -e

# Проверка наличия ZONE_NAME в окружении
if [ -z "$ZONE_NAME" ]; then
  echo "❌ ZONE_NAME is not set. Please define it via GitHub environment or workflow 'env:'"
  exit 1
fi

# === Путь и конфиг воркера ===
WORKER_DIR="workers/${WORKER_NAME}"
CONFIG_PATH="${WORKER_DIR}/worker.json"

echo "🔧 Loading config for $WORKER_NAME..."
NAME=$(jq -r '.name' "$CONFIG_PATH")
DNS_ROUTE=$(jq -r '.dnsRoute // empty' "$CONFIG_PATH")

# === Переменные во временный файл и экспорт в окружение ===
echo "ZONE_NAME=${ZONE_NAME}" > .dev.vars
echo "CLOUDFLARE_ZONE_ID=${CLOUDFLARE_ZONE_ID}" >> .dev.vars
echo "CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}" >> .dev.vars
echo "WORKER_NAME=${NAME}" >> .dev.vars
echo "MAIN_PATH=${WORKER_DIR}/index.js" >> .dev.vars
echo "WORKER_ROUTE=${DNS_ROUTE}" >> .dev.vars

export ZONE_NAME CLOUDFLARE_ZONE_ID CLOUDFLARE_ACCOUNT_ID
export WORKER_NAME="${NAME}"
export MAIN_PATH="${WORKER_DIR}/index.js"
export WORKER_ROUTE="${DNS_ROUTE}"

# === DNS-проверка и создание, если необходимо ===
if [ -n "$DNS_ROUTE" ]; then
  FQDN="${DNS_ROUTE}.${ZONE_NAME}"
  echo "Checking DNS for ${FQDN}..."

  RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${FQDN}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

  if [ "$RECORD_ID" = "null" ]; then
    echo "Creating DNS record for ${FQDN} → ${DNS_ROUTE}.workers.dev"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data '{
        "type": "CNAME",
        "name": "'"${DNS_ROUTE}"'",
        "content": "'"${DNS_ROUTE}.workers.dev"'",
        "ttl": 300,
        "proxied": true
      }'
  else
    echo "✅ DNS record already exists for ${FQDN}"
  fi
fi

# === Генерация wrangler.toml ===
cp wrangler.template.toml wrangler.toml

sed -i "s|\${WORKER_NAME}|$WORKER_NAME|g" wrangler.toml
sed -i "s|\${MAIN_PATH}|$MAIN_PATH|g" wrangler.toml
sed -i "s|\${ZONE_NAME}|$ZONE_NAME|g" wrangler.toml
sed -i "s|\${CLOUDFLARE_ZONE_ID}|$CLOUDFLARE_ZONE_ID|g" wrangler.toml
sed -i "s|\${WORKER_ROUTE}|$WORKER_ROUTE|g" wrangler.toml

# === Добавление routes, если DNS_ROUTE задан ===
if [ -n "$DNS_ROUTE" ]; then
  {
    echo ""
    echo "routes = ["
    echo "  { pattern = \"${DNS_ROUTE}.${ZONE_NAME}\", zone_id = \"${CLOUDFLARE_ZONE_ID}\" }"
    echo "]"
  } >> wrangler.toml
fi

# === Отладочный вывод TOML ===
echo "::group::Rendered wrangler.toml"
cat wrangler.toml
echo "::endgroup::"

# === Upload секретов ===
echo "🔐 Uploading secrets..."
while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' | xargs)
  if [ -n "$key" ]; then
    echo "$value" | npx wrangler secret put "$key"
  fi
done < .dev.vars

# === Deploy ===
echo "🚀 Deploying ${WORKER_NAME}"
npx wrangler deploy

# === Cleanup ===
rm -f .dev.vars wrangler.toml
