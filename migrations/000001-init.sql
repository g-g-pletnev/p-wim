-- Track applied migrations
CREATE TABLE IF NOT EXISTS sys_migrations (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    name TEXT NOT NULL UNIQUE,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Historical data
CREATE TABLE data_metrics (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    agent_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    data TEXT NOT NULL,
    source_uuid TEXT NOT NULL,
    dts_inserted INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

-- Temporary session storage
CREATE TABLE tmp_sessions (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    user_id TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    expires_at INTEGER
);

-- Users
CREATE TABLE ref_users (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    role TEXT NOT NULL
);

-- Monitoring agents
CREATE TABLE ref_agents (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    token TEXT UNIQUE NOT NULL DEFAULT (hex(randomblob(16))),
    hostname TEXT NOT NULL,
    type TEXT NOT NULL,
    description TEXT,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    config TEXT
);

-- Page content
CREATE TABLE ref_pages (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    slug TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    content TEXT NOT NULL
);

-- Stored SQL queries
CREATE TABLE ref_queries (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    name TEXT NOT NULL,
    query TEXT NOT NULL
);
