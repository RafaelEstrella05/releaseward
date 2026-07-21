const test = require('node:test');
const assert = require('node:assert/strict');
const { classify } = require('./classifier');

const categoryCases = [
  ['Badge access denied at the rear entrance', 'access_denied'],
  ['Entry detected outside business hours', 'after_hours'],
  ['Possible piggyback at the lobby turnstile', 'tailgating'],
  ['The north camera offline alert is active', 'device_offline'],
  ['A visitor arrived at the front desk', 'visitor'],
];

for (const [text, expectedCategory] of categoryCases) {
  test(`classifies ${expectedCategory} events`, () => {
    assert.deepEqual(classify(text), {
      category: expectedCategory,
      confidence: 0.25,
    });
  });
}

test('returns uncategorized when no keywords match', () => {
  assert.deepEqual(classify('Routine patrol completed without incident'), {
    category: 'uncategorized',
    confidence: 0,
  });
});

test('counts multiple matching keywords when calculating confidence', () => {
  assert.deepEqual(classify('Badge denied and card rejected'), {
    category: 'access_denied',
    confidence: 0.5,
  });
});
