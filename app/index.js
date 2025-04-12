import express from 'express';
import path from 'path';
import fs from 'fs';
import cron from 'node-cron';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();

const WORKERS_DIR = path.resolve(__dirname, '../workers');

const getWorkerConfigs = () => {
  const entries = fs.readdirSync(WORKERS_DIR, { withFileTypes: true });
  return entries
    .filter((dirent) => dirent.isDirectory())
    .map((dirent) => {
      const name = dirent.name;
      const configPath = path.join(WORKERS_DIR, name, 'worker.json');
      const entryPath = path.join(WORKERS_DIR, name, 'index.js');

      if (!fs.existsSync(configPath)) {
        console.warn(`⚠️ Missing config: ${configPath}`);
        return null;
      }
      if (!fs.existsSync(entryPath)) {
        console.warn(`⚠️ Missing entry file: ${entryPath}`);
        return null;
      }

      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      config.name = config.name || name;
      config.entry = entryPath;
      return config;
    })
    .filter(Boolean);
};

const WORKERS = getWorkerConfigs();

const mountWorkers = async () => {
  for (const worker of WORKERS) {
    const mod = await import(worker.entry);

    if (worker.type === 'web') {
      const route = worker.localRoute || `/${worker.name}`;
      console.log(`📡 Mounting [${worker.name}] at ${route}`);
      app.all(route + '*', async (req, res) => {
        try {
          const url = new URL(req.originalUrl, `http://${req.headers.host}`);
          const cfReq = new Request(url, {
            method: req.method,
            headers: req.headers,
            body: ['GET', 'HEAD'].includes(req.method) ? undefined : req,
          });

          const cfRes = await mod.default.fetch(cfReq, process.env, {
            waitUntil: () => {},
          });

          const body = await cfRes.text();
          res.status(cfRes.status).set(Object.fromEntries(cfRes.headers)).send(body);
        } catch (err) {
          console.error(`❌ Error in [${worker.name}] web:`, err);
          res.status(500).send(`Internal error in worker "${worker.name}"`);
        }
      });
    }

    if (worker.type === 'scheduled') {
      if (!mod.default?.scheduled) {
        console.warn(`⚠️ Worker "${worker.name}" missing default.scheduled`);
        continue;
      }

      const cronExpr = worker.cron || '0 * * * *'; // по умолчанию: раз в час
      console.log(`⏰ Scheduling [${worker.name}] with: ${cronExpr}`);
      cron.schedule(cronExpr, async () => {
        try {
          const now = new Date();
          await mod.default.scheduled({ scheduledTime: now }, process.env, {
            waitUntil: () => {},
          });
          console.log(`✅ [${worker.name}] ran at ${now.toISOString()}`);
        } catch (err) {
          console.error(`❌ Scheduled error in "${worker.name}":`, err);
        }
      });
    }
  }
};

await mountWorkers();

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Local runner started: http://localhost:${PORT}`);
});
