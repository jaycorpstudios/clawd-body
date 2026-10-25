import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { envelope, EVENT_TYPES, SCENARIOS, ulid, validateEvent } from '../src/index.ts';

const FIXTURES = new URL('../fixtures/', import.meta.url);
const readJson = (dir: string, file: string) => JSON.parse(readFileSync(new URL(`${dir}/${file}`, FIXTURES), 'utf8'));
const list = (dir: string) => readdirSync(new URL(dir, FIXTURES)).filter((f) => f.endsWith('.json'));

describe('valid fixtures', () => {
  for (const file of list('valid')) {
    it(file, () => {
      const result = validateEvent(readJson('valid', file));
      assert.ok(result.ok, result.ok ? '' : result.errors.join('; '));
    });
  }

  it('cover every event type', () => {
    const covered = new Set(list('valid').map((f) => readJson('valid', f).type));
    assert.deepEqual(EVENT_TYPES.filter((t) => !covered.has(t)), []);
  });
});

describe('invalid fixtures', () => {
  for (const file of list('invalid')) {
    const { reason, event } = readJson('invalid', file);
    it(`${file}: ${reason}`, () => assert.equal(validateEvent(event).ok, false));
  }
});

describe('scenarios', () => {
  for (const [name, scenario] of Object.entries(SCENARIOS)) {
    it(`${name} emits only valid events`, () => {
      for (const step of scenario.build(1792900000)) {
        const result = validateEvent(envelope(step.type, step.data, step.from === 'mac' ? 'work' : undefined));
        assert.ok(result.ok, `${step.type}: ${result.ok ? '' : result.errors.join('; ')}`);
      }
    });
  }
});

describe('ulid', () => {
  it('encodes the timestamp so ids sort by time', () => {
    assert.ok(ulid(1000) < ulid(2000));
    assert.equal(ulid(0).slice(0, 10), '0000000000');
  });
});
