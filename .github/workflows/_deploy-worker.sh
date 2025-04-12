#!/bin/bash
set -e

WORKER_DIR="workers/${WORKER_NAME}"
CONFIG_PATH="${WORKER_DIR}/worker.json"

echo "🔧 Loading config for $WORKER_NAME..."
NAME=$(jq -r '.name' "$CONFIG_PATH")
ROUTE=$(jq -r '.route // empty' "$CONFIG_PATH")

echo "ZONE_NAME=${ZONE_NAME}" > .dev.vars
echo "CLOUDFLARE_ZONE_ID=${CLOUDFLARE_ZONE_ID}" >> .dev.vars
echo "CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}" >> .dev.vars
echo "WORKER_NAME=${NAME}" >> .dev.vars

if [ -n "$ROUTE" ]; then
  FQDN="${ROUTE}.${ZONE_NAME}"
  echo "Checking DNS for ${FQDN}..."

  RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${FQDN}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

  if [ "$RECORD_ID" = "null" ]; then
    echo "Creating DNS for ${FQDN}"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data '{
        "type": "CNAME",
        "name": "'"${ROUTE}"'",
        "content": "'"${ROUTE}.workers.dev"'",
        "ttl": 300,
        "proxied": true
      }'
  fi
fi

cp wrangler.template.toml wrangler.toml
sed -i "s|\${WORKER_NAME}|${NAME}|g" wrangler.toml
sed -i "s|\${MAIN_PATH}|${WORKER_DIR}/index.js|g" wrangler.toml
sed -i "s|\${ZONE_NAME}|${ZONE_NAME}|g" wrangler.toml
sed -i "s|\${CLOUDFLARE_ZONE_ID}|${CLOUDFLARE_ZONE_ID}|g" wrangler.toml

echo "🔐 Uploading secrets..."
while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' | xargs)
  if [ -n "$key" ]; then
    echo "$value" | npx wrangler secret put "$key"
  fi
done < .dev.vars

echo "🚀 Deploying ${WORKER_NAME}"
npx wrangler deploy

rm -f .dev.vars wrangler.toml
