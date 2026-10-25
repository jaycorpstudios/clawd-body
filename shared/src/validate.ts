import { Ajv2020 } from 'ajv/dist/2020.js';
import schema from '../events.schema.json' with { type: 'json' };

export type Envelope = {
  v: 1;
  id: string;
  ts: number;
  host?: string;
  type: string;
  data: Record<string, unknown>;
};

export type Validation = { ok: true; event: Envelope } | { ok: false; errors: string[] };

const validator = new Ajv2020({ allErrors: true, strict: true, strictRequired: false, allowUnionTypes: true }).compile<Envelope>(schema);

export const EVENT_TYPES: readonly string[] = schema.properties.type.enum;

export function validateEvent(value: unknown): Validation {
  if (validator(value)) return { ok: true, event: value };
  const errors = (validator.errors ?? []).map((e) => `${e.instancePath || '/'} ${e.message ?? 'invalid'}`);
  return { ok: false, errors: [...new Set(errors)] };
}
