import { test } from 'node:test';
import assert from 'node:assert/strict';
import { roofPitch, battenGauge } from './roofTools.ts';

test('pitch uses horizontal run and rejects invalid dimensions', () => {
  assert.ok(Math.abs(roofPitch(1200, 2400) - 26.565) < 0.001);
  assert.equal(roofPitch(0, 2400), null);
  assert.equal(roofPitch(1, Infinity), null);
});
test('gauger uses longest rafter and flags a short side outside the permitted gauge', () => {
  const result = battenGauge([4980, 5000, 5020], 100, 320, 345);
  assert.equal(result.courses, 15);
  assert.ok(Math.abs(result.shortest - 4880 / 15) < 0.001);
  assert.equal(result.outOfRange, false);
  assert.equal(battenGauge([4000, 5020], 100, 320, 345).outOfRange, true);
});
test('gauger refuses impossible measurements', () => {
  assert.equal(battenGauge([100], 100, 320, 345), null);
  assert.equal(battenGauge([5000], 100, 345, 320), null);
  assert.equal(battenGauge([], 100, 320, 345), null);
});
