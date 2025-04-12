#!/bin/bash
set -e

WORKER_DIR="workers/${WORKER_NAME}"
CONFIG_PATH="${WORKER_DIR}/worker.json"

echo "🔧 Loading config for $WORKER_NAME..."
NAME=$(jq -r '.name' "$CONFIG_PATH")
DNS_ROUTE=$(jq -r '.dnsRoute // empty' "$CONFIG_PATH")

echo "ZONE_NAME=${ZONE_NAME}" > .dev.vars
echo "CLOUDFLARE_ZONE_ID=${CLOUDFLARE_ZONE_ID}" >> .dev.vars
echo "CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}" >> .dev.vars
echo "WORKER_NAME=${NAME}" >> .dev.vars
echo "MAIN_PATH=${WORKER_DIR}/index.js" >> .dev.vars
echo "WORKER_ROUTE=${DNS_ROUTE}" >> .dev.vars

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

# === Render wrangler.toml ===
cp wrangler.template.toml wrangler.toml
sed -i "s|\${WORKER_NAME}|${NAME}|g" wrangler.toml
sed -i "s|\${MAIN_PATH}|${WORKER_DIR}/index.js|g" wrangler.toml
sed -i "s|\${ZONE_NAME}|${ZONE_NAME}|g" wrangler.toml
sed -i "s|\${CLOUDFLARE_ZONE_ID}|${CLOUDFLARE_ZONE_ID}|g" wrangler.toml
sed -i "s|\${WORKER_ROUTE}|${DNS_ROUTE}|g" wrangler.toml

# === Append routes block only if DNS_ROUTE is set ===
if [ -n "$DNS_ROUTE" ]; then
  echo "" >> wrangler.toml
  echo "routes = [" >> wrangler.toml
  echo "  { pattern = \"${DNS_ROUTE}.${ZONE_NAME}\", zone_id = \"${CLOUDFLARE_ZONE_ID}\" }" >> wrangler.toml
  echo "]" >> wrangler.toml
fi

echo "::group::Rendered wrangler.toml"
cat wrangler.toml
echo "::endgroup::"

# === Upload secrets ===
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
