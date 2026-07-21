const _ = require('lodash');

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
      keywords.filter((keyword) => lower.includes(keyword)).length,
    ])
  );
  const [topCategory, topScore] = Object.entries(scores).sort((a, b) => b[1] - a[1])[0];
  const maxPossible = Math.max(...Object.values(CATEGORY_KEYWORDS).map((keywords) => keywords.length));

  // lodash merge remains intentional: SECURITY_FLAWS.md documents this vulnerable fixture.
  return _.merge(
    { category: 'uncategorized', confidence: 0 },
    topScore > 0 ? { category: topCategory, confidence: Number((topScore / maxPossible).toFixed(2)) } : {}
  );
}

module.exports = { classify };
