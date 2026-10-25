import { getRandomValues } from 'node:crypto';

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function ulid(nowMs: number = Date.now()): string {
  let time = '';
  for (let t = nowMs, i = 0; i < 10; i++, t = Math.floor(t / 32)) time = CROCKFORD[t % 32] + time;
  const random = Array.from(getRandomValues(new Uint8Array(16)), (b) => CROCKFORD[b % 32]).join('');
  return time + random;
}
