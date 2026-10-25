import { ulid } from './ulid.ts';
import type { Envelope } from './validate.ts';

export function envelope(type: string, data: Record<string, unknown>, host?: string, tsMs: number = Date.now()): Envelope {
  return { v: 1, id: ulid(tsMs), ts: Math.floor(tsMs / 1000), ...(host ? { host } : {}), type, data };
}
