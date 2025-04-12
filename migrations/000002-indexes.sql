-- 🔍 data_metrics: фильтрация по агенту и времени
CREATE INDEX IF NOT EXISTS idx_data_metrics_agent_timestamp
  ON data_metrics (agent_id, timestamp);

-- 👤 ref_users: авторизация по username
CREATE UNIQUE INDEX IF NOT EXISTS idx_ref_users_username
  ON ref_users (username);

-- 🛰 ref_agents: авторизация или идентификация по токену
CREATE UNIQUE INDEX IF NOT EXISTS idx_ref_agents_token
  ON ref_agents (token);

-- 📄 ref_pages: доступ к страницам по slug
CREATE UNIQUE INDEX IF NOT EXISTS idx_ref_pages_slug
  ON ref_pages (slug);

-- 🧠 ref_queries: вызов запроса по имени
CREATE INDEX IF NOT EXISTS idx_ref_queries_name
  ON ref_queries (name);
