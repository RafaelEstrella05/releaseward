const express = require('express');
const pinoHttp = require('pino-http');
const path = require('path');
const client = require('prom-client');
const { classify } = require('./classifier');

const app = express();
const httpLogger = pinoHttp();

const metricsRegistry = new client.Registry();
client.collectDefaultMetrics({ register: metricsRegistry });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds, labeled by method/route/status code',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [metricsRegistry],
});

const classifyTotal = new client.Counter({
  name: 'releaseward_classify_events_total',
  help: 'Security-event classifications served, labeled by resulting category',
  labelNames: ['category'],
  registers: [metricsRegistry],
});

app.use(httpLogger);
app.use((req, res, next) => {
  const endTimer = httpRequestDuration.startTimer({ method: req.method });
  res.on('finish', () => {
    // req.route is only set once Express matches a route; fall back to path
    // for 404s so unmatched routes don't create unbounded label cardinality.
    const route = req.route ? req.route.path : 'unmatched';
    endTimer({ route, status_code: res.statusCode });
  });
  next();
});
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', metricsRegistry.contentType);
  res.end(await metricsRegistry.metrics());
});

// --- INTENTIONAL SECURITY FLAW, documented in SECURITY_FLAWS.md ---
// Synthetic releaseward-only API-key-shaped string so the pipeline's
// custom secret-scanning rule has something real to catch. Not a real credential —
// never replace this with an actual working key.
// eslint-disable-next-line no-unused-vars -- Intentional fixture for Trivy secret detection.
const DEMO_API_KEY = 'releaseward_demo_00000000000000000000000000000000';
// --- END INTENTIONAL FLAW ---

let ready = false;
setTimeout(() => {
  ready = true;
}, 2000); // simulate a warm-up period, like a real service loading caches/connections

app.get('/livez', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

app.get('/readyz', (req, res) => {
  if (!ready) {
    req.log.warn('readiness check failed: still warming up');
    return res.status(503).json({ status: 'not ready' });
  }
  res.status(200).json({ status: 'ready' });
});

app.post('/classify', (req, res) => {
  const { text } = req.body || {};
  if (!text || typeof text !== 'string') {
    return res.status(400).json({ error: 'text field (string) is required' });
  }
  const result = classify(text);
  classifyTotal.inc({ category: result.category });
  req.log.info({ inputLength: text.length, result }, 'classified a security event');
  res.status(200).json(result);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: `releaseward demo service listening on port ${PORT}` }));
});
