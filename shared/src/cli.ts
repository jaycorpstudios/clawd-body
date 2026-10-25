#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { setTimeout as sleep } from 'node:timers/promises';
import { parseArgs } from 'node:util';
import { envelope } from './envelope.ts';
import { SCENARIOS } from './scenarios.ts';
import { validateEvent } from './validate.ts';

const USAGE = `Usage:
  buddy-emit list
  buddy-emit <scenario> [--host work] [--interval ms]   print contract events as JSON lines
  buddy-emit validate < events.jsonl                    exit 1 if any line is invalid`;

async function emit(name: string, host: string, intervalMs: number): Promise<number> {
  const scenario = SCENARIOS[name];
  if (!scenario) {
    console.error(`Unknown scenario "${name}". Run "buddy-emit list".`);
    return 2;
  }
  for (const [i, step] of scenario.build(Math.floor(Date.now() / 1000)).entries()) {
    if (i > 0 && intervalMs > 0) await sleep(intervalMs);
    const event = envelope(step.type, step.data, step.from === 'mac' ? host : undefined);
    const result = validateEvent(event);
    if (!result.ok) {
      console.error(`Scenario "${name}" produced an invalid ${step.type}: ${result.errors.join('; ')}`);
      return 1;
    }
    console.log(JSON.stringify(event));
  }
  return 0;
}

async function validateStdin(): Promise<number> {
  let line = 0;
  let invalid = 0;
  for await (const text of createInterface({ input: process.stdin })) {
    line++;
    if (!text.trim()) continue;
    let value: unknown;
    try {
      value = JSON.parse(text);
    } catch {
      invalid++;
      console.error(`line ${line}: not JSON`);
      continue;
    }
    const result = validateEvent(value);
    if (!result.ok) {
      invalid++;
      console.error(`line ${line}: ${result.errors.join('; ')}`);
    }
  }
  console.error(`${line - invalid}/${line} valid`);
  return invalid ? 1 : 0;
}

async function main(argv: string[]): Promise<number> {
  const { positionals, values } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: { host: { type: 'string', default: 'work' }, interval: { type: 'string', default: '0' } },
  });
  const [command] = positionals;
  if (!command) {
    console.error(USAGE);
    return 2;
  }
  if (command === 'list') {
    for (const [name, s] of Object.entries(SCENARIOS)) console.log(`${name.padEnd(16)} ${s.description}`);
    return 0;
  }
  if (command === 'validate') return validateStdin();
  return emit(command, values.host, Number(values.interval));
}

process.exitCode = await main(process.argv.slice(2));
