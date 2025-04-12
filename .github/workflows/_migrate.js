import fs from 'node:fs/promises';
import path from 'node:path';
import { execSync } from 'node:child_process';
import sqlite3 from 'sqlite3';

const DB_PATH = '.d1/metrics.sqlite';
const MIGRATIONS_DIR = 'migrations';
const DB_NAME = 'metrics';

const CLOUDFLARE_TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const IS_CLOUD = !!CLOUDFLARE_TOKEN;
const WRANGLER_TEMPLATE = 'wrangler.template.toml';
const WRANGLER_OUTPUT = 'wrangler.toml';

async function getMigrationFiles() {
  const files = await fs.readdir(MIGRATIONS_DIR);
  return files.filter(f => f.endsWith('.sql')).sort();
}

async function renderWranglerToml() {
  const template = await fs.readFile(WRANGLER_TEMPLATE, 'utf8');
  const replaced = template
    .replace(/\$\{WORKER_NAME\}/g, 'migrator')
    .replace(/\$\{MAIN_PATH\}/g, 'm.js');
  await fs.writeFile(WRANGLER_OUTPUT, replaced);
}

// ----------------------------
// ✅ CLOUD MODE (via wrangler)
// ----------------------------
async function applyCloudMigrations() {
  console.log('☁️ Running in Cloudflare D1 mode');

  try {
    await renderWranglerToml();

    const appliedRaw = execSync(`npx wrangler d1 execute ${DB_NAME} --remote --command "SELECT name FROM sys_migrations;" || true`).toString();
    const applied = new Set(
      appliedRaw
        .split('\n')
        .filter(line => line && !line.includes('name') && !line.includes('success'))
        .map(line => line.trim())
    );

    const files = await getMigrationFiles();

    for (const file of files) {
      if (applied.has(file)) {
        console.log(`⏭ Skipping already applied: ${file}`);
        continue;
      }
      console.log(`🔄 Applying ${file}...`);
      execSync(`npx wrangler d1 execute ${DB_NAME} --remote --file ${path.join(MIGRATIONS_DIR, file)}`, { stdio: 'inherit' });
      execSync(`npx wrangler d1 execute ${DB_NAME} --remote --command "INSERT INTO sys_migrations (name) VALUES ('${file}');"`);
      console.log(`✅ Done: ${file}`);
    }
  } finally {
    try {
      await fs.unlink(WRANGLER_OUTPUT);
      console.log('🗑️ Cleaned up wrangler.toml');
    } catch (err) {
      console.warn('⚠️ Could not delete wrangler.toml:', err.message);
    }
  }
  console.log('🎉 Cloud migrations complete');
}

// ----------------------------
// 🖥 LOCAL MODE (sqlite3)
// ----------------------------
function connectDb() {
  return new sqlite3.Database(DB_PATH);
}

function exec(db, sql) {
  return new Promise((resolve, reject) => {
    db.exec(sql, (err) => (err ? reject(err) : resolve()));
  });
}

function run(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function (err) {
      err ? reject(err) : resolve(this);
    });
  });
}

function all(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
  });
}

async function ensureDbFile() {
  try {
    await fs.access(DB_PATH);
    console.log(`✅ Database exists: ${DB_PATH}`);
  } catch {
    console.log(`📦 Creating empty database: ${DB_PATH}`);
    await fs.mkdir(path.dirname(DB_PATH), { recursive: true });
    await fs.writeFile(DB_PATH, '');
  }
}

async function applyLocalMigrations() {
  console.log('💻 Running in local SQLite mode');
  await ensureDbFile();
  const db = connectDb();

  await exec(db, `
    CREATE TABLE IF NOT EXISTS sys_migrations (
      id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
      name TEXT NOT NULL UNIQUE,
      created_at INTEGER DEFAULT (strftime('%s', 'now'))
    );
  `);

  const rows = await all(db, 'SELECT name FROM sys_migrations');
  const applied = new Set(rows.map(r => r.name));
  const files = await getMigrationFiles();

  for (const file of files) {
    if (applied.has(file)) {
      console.log(`⏭ Skipping: ${file}`);
      continue;
    }
    const sql = await fs.readFile(path.join(MIGRATIONS_DIR, file), 'utf8');
    const statements = sql.split(';').map(s => s.trim()).filter(Boolean);
    try {
      await exec(db, 'BEGIN');
      for (const stmt of statements) await exec(db, stmt);
      await run(db, 'INSERT INTO sys_migrations (name) VALUES (?)', [file]);
      await exec(db, 'COMMIT');
      console.log(`✅ Applied: ${file}`);
    } catch (err) {
      await exec(db, 'ROLLBACK');
      console.error(`❌ Error in ${file}: ${err.message}`);
      process.exit(1);
    }
  }

  db.close();
  console.log('🎉 Local migrations complete');
}

// ----------------------------
// 🔁 Main
// ----------------------------
(async () => {
  try {
    if (IS_CLOUD) {
      await applyCloudMigrations();
    } else {
      await applyLocalMigrations();
    }
  } catch (err) {
    console.error('💥 Migration failed:', err);
    process.exit(1);
  }
})();