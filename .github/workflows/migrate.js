// .github/workflows/migrate.js
import fs from 'node:fs/promises';
import path from 'node:path';
import sqlite3 from 'sqlite3';

const DB_PATH = '.d1/metrics.sqlite';
const MIGRATIONS_DIR = 'migrations';

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

async function ensureMigrationTable(db) {
  await exec(db, `
    CREATE TABLE IF NOT EXISTS sys_migrations (
      id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
      name TEXT NOT NULL UNIQUE,
      created_at INTEGER DEFAULT (strftime('%s', 'now'))
    );
  `);
}

async function getAppliedMigrations(db) {
  const rows = await all(db, 'SELECT name FROM sys_migrations');
  return new Set(rows.map(r => r.name));
}

async function applyMigration(db, filePath, name) {
  const sql = await fs.readFile(filePath, 'utf8');
  const statements = sql.split(';').map(s => s.trim()).filter(Boolean);
  try {
    await exec(db, 'BEGIN');
    for (const stmt of statements) {
      await exec(db, stmt);
    }
    await run(db, 'INSERT INTO sys_migrations (name) VALUES (?)', [name]);
    await exec(db, 'COMMIT');
    console.log(`✅ Applied: ${name}`);
  } catch (err) {
    await exec(db, 'ROLLBACK');
    console.error(`❌ Error in ${name}: ${err.message}`);
    process.exit(1);
  }
}

async function runMigrations() {
  await ensureDbFile();
  const db = connectDb();

  await ensureMigrationTable(db);
  const applied = await getAppliedMigrations(db);

  const files = (await fs.readdir(MIGRATIONS_DIR))
    .filter(f => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    if (applied.has(file)) {
      console.log(`⏭ Skipping: ${file}`);
      continue;
    }
    const filePath = path.join(MIGRATIONS_DIR, file);
    await applyMigration(db, filePath, file);
  }

  console.log('🎉 All migrations complete');
  db.close();
}

runMigrations().catch((err) => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
