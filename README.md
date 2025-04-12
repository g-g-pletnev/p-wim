# p-wim
private web and infrastructure monitor


## 📦 Project Structure & Workers

This project is designed to support a multi-worker Cloudflare Workers application with both local and remote deployment capabilities. Each worker is isolated in its own directory under `/workers` and fully described by a dedicated `worker.json` file.

### 📁 Directory Layout

```
.
├── app/                   # Local Express runner for web workers
│   └── index.js
├── config/                # Reserved for shared config (e.g., schemas, routes)
├── workers/               # All individual worker projects live here
│   ├── webui/
│   │   ├── index.js       # Worker entry point
│   │   └── worker.json    # Metadata and routing info
│   ├── api-metrics/
│   └── agent-web-checker/
├── .github/workflows/     # CI/CD workflows
│   ├── deploy-all.yml
│   ├── deploy-changed.yml
│   ├── deploy-select.yml
│   └── _deploy-worker.sh  # Shared deployment logic
├── wrangler.template.toml # Template for dynamic generation of wrangler.toml
├── package.json
└── README.md
```

---

### 🧩 `worker.json` Specification

Each worker must include a `worker.json` file in its directory, which defines its identity and routing behavior.

#### Example:
```json
{
  "name": "webui",
  "type": "web",                    // "web" or "scheduled"
  "localRoute": "/webui",           // Used for local Express mounting
  "dnsRoute": "webui"                // Used as subdomain (webui.example.com)
}
```

#### Fields:

| Field        | Required | Description |
|--------------|----------|-------------|
| `name`       | ✅ Yes    | Unique name for the worker, also used as Cloudflare service name |
| `type`       | ✅ Yes    | Either `web` for HTTP workers or `scheduled` for cron-like execution |
| `localRoute` | ❌ Optional | Express path prefix for local development (e.g. `/metrics`) |
| `dnsRoute`   | ❌ Optional | Subdomain to use in production (e.g. `metrics` → `metrics.example.com`) |

Workers without a `dnsRoute` will only be accessible via their `workers.dev` fallback domain.

---

### ✅ Workflow Integration

Deployment workflows automatically detect and deploy workers based on:
- file changes (`deploy-changed.yml`)
- manual input (`deploy-select.yml`)
- full deployment (`deploy-all.yml`)

Worker deployment is driven by the metadata in `worker.json`.

---

For detailed deployment behavior, see the `.github/workflows/_deploy-worker.sh` script.

