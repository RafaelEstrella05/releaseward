const express = require('express');
const pinoHttp = require('pino-http');
const _ = require('lodash');
const path = require('path');

const app = express();
const httpLogger = pinoHttp();

app.use(httpLogger);
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// --- INTENTIONAL SECURITY FLAW, documented in SECURITY_FLAWS.md ---
// Fake, DeepSeek/OpenAI-style API-key-shaped string so the pipeline's
// secret-scanning stage has something real to catch. Not a real credential —
// never replace this with an actual working key.
const DEMO_API_KEY = 'sk-fakeDoNotUse0000000000000000000000demo';
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

const CATEGORY_KEYWORDS = {
  access_denied: ['badge denied', 'access denied', 'invalid credential', 'card rejected'],
  after_hours: ['after hours', 'after-hours', 'outside business hours', 'weekend entry'],
  tailgating: ['tailgating', 'piggyback', 'multiple entries single badge', 'unauthorized follow'],
  device_offline: ['camera offline', 'feed lost', 'device offline', 'sensor unresponsive'],
  visitor: ['visitor check-in', 'guest badge', 'visitor arrived', 'front desk visitor'],
};

function classify(text) {
  const lower = text.toLowerCase();
  const scores = Object.fromEntries(
    Object.entries(CATEGORY_KEYWORDS).map(([category, keywords]) => [
      category,
      keywords.filter((k) => lower.includes(k)).length,
    ])
  );
  const [topCategory, topScore] = Object.entries(scores).sort((a, b) => b[1] - a[1])[0];
  const maxPossible = Math.max(...Object.values(CATEGORY_KEYWORDS).map((k) => k.length));

  // lodash merge used for real here (not just decorative) to build the result object
  return _.merge(
    { category: 'uncategorized', confidence: 0 },
    topScore > 0 ? { category: topCategory, confidence: Number((topScore / maxPossible).toFixed(2)) } : {}
  );
}

app.post('/classify', (req, res) => {
  const { text } = req.body || {};
  if (!text || typeof text !== 'string') {
    return res.status(400).json({ error: 'text field (string) is required' });
  }
  const result = classify(text);
  req.log.info({ inputLength: text.length, result }, 'classified a security event');
  res.status(200).json(result);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: `releaseward demo service listening on port ${PORT}` }));
});
