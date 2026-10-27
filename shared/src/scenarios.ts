import { ulid } from './ulid.ts';

export type ScenarioStep = { from: 'mac' | 'buddy'; type: string; data: Record<string, unknown> };
export type Scenario = { description: string; build: (nowS: number) => ScenarioStep[] };

const mac = (type: string, data: Record<string, unknown>): ScenarioStep => ({ from: 'mac', type, data });
const buddy = (type: string, data: Record<string, unknown>): ScenarioStep => ({ from: 'buddy', type, data });

const SESSION = '7f3a9c1e-2b4d-4e8f-9a01-5c6d7e8f9a0b';
const PROJECT = 'payments-api';
const EXPIRY_S = 600;

function lowRiskPermission(nowS: number) {
  return {
    request_id: ulid(), session: SESSION, project: PROJECT, tool: 'Bash', detail: 'npm run db:migrate',
    why: 'Apply migration 0042 to the local database before running the tests.',
    cwd: '~/code/payments-api', risk: 'low', remote_allowed: true, expires_at: nowS + EXPIRY_S,
  };
}

function snapshot(nowS: number): ScenarioStep {
  return mac('snapshot', {
    sessions: [
      { session: SESSION, project: PROJECT, task: 'Payments webhook refactor', status: 'working', since: nowS - 840, tokens: 118,
        steps: [{ ts: nowS - 120, kind: 'edit', text: 'Edited src/webhooks/stripe.ts' }] },
      { session: 'a1b2c3d4', project: 'hilo-app', task: 'SQLite v3 migration', status: 'done', since: nowS - 300,
        summary: 'Migration applied; 128 tests passed.' },
    ],
    usage: { session_pct: 42, weekly_pct: 31, reset_in_min: 134, tokens_today: 1840000 },
    hilo: {
      current: { title: 'Integrate BLE events into the daemon', project: 'hilo-buddy', started_at: nowS - 2892 },
      next: [{ title: 'Review CloudWatch alerts', project: 'acme', jira: 'DEMO-1423' }],
      agreements_today: ['Compact JSON events'],
    },
  });
}

export const SCENARIOS: Record<string, Scenario> = {
  connect: {
    description: 'Link comes up: full snapshot for this host',
    build: (nowS) => [snapshot(nowS)],
  },
  'permission-low': {
    description: 'Low-risk permission approved from the buddy, then the task finishes',
    build: (nowS) => {
      const p = lowRiskPermission(nowS);
      return [
        mac('session.start', { session: SESSION, project: PROJECT, task: 'Payments webhook refactor' }),
        mac('agent.step', { session: SESSION, kind: 'read', text: 'Read src/webhooks/stripe.ts' }),
        mac('agent.needs_permission', p),
        buddy('device.ack', { request_id: p.request_id, seen: true }),
        buddy('permission.decision', { request_id: p.request_id, decision: 'approve' }),
        mac('agent.request_resolved', { request_id: p.request_id, session: SESSION, kind: 'permission', outcome: 'approved', via: 'buddy' }),
        mac('agent.task_done', { session: SESSION, summary: 'Changes ready for review: 3 files, tests green.' }),
        mac('session.end', { session: SESSION }),
      ];
    },
  },
  'permission-high': {
    description: 'High-risk permission: the buddy can only deny',
    build: (nowS) => {
      const request_id = ulid();
      return [
        mac('agent.needs_permission', {
          request_id, session: SESSION, project: 'infra-terraform', tool: 'Bash', detail: 'terraform apply',
          why: 'Deploy the new task definition to ECS (production).', cwd: '~/code/infra-terraform',
          risk: 'high', remote_allowed: false, expires_at: nowS + EXPIRY_S,
        }),
        buddy('permission.decision', { request_id, decision: 'deny' }),
        mac('agent.request_resolved', { request_id, session: SESSION, kind: 'permission', outcome: 'denied', via: 'buddy' }),
      ];
    },
  },
  'resolved-on-mac': {
    description: 'User taps Later on the buddy, then answers on the Mac',
    build: (nowS) => {
      const p = lowRiskPermission(nowS);
      return [
        mac('agent.needs_permission', p),
        buddy('device.snooze', { request_id: p.request_id }),
        mac('agent.request_resolved', { request_id: p.request_id, session: SESSION, kind: 'permission', outcome: 'approved', via: 'mac' }),
      ];
    },
  },
  question: {
    description: 'Question answered from the buddy',
    build: (nowS) => {
      const request_id = ulid();
      return [
        mac('agent.question', {
          request_id, session: SESSION, project: 'hilo-app', detail: 'Where should I store Hilo history?',
          options: ['Local SQLite', 'Markdown files', 'Decide later'], expires_at: nowS + EXPIRY_S,
        }),
        buddy('question.answer', { request_id, choice_index: 0, choice: 'Local SQLite' }),
        mac('agent.request_resolved', { request_id, session: SESSION, kind: 'question', outcome: 'answered', via: 'buddy', choice_index: 0 }),
      ];
    },
  },
  expired: {
    description: 'Nobody answers; the request expires and falls back to the Mac prompt',
    build: (nowS) => {
      const p = lowRiskPermission(nowS);
      return [
        mac('agent.needs_permission', p),
        mac('agent.request_resolved', { request_id: p.request_id, session: SESSION, kind: 'permission', outcome: 'expired', via: 'timeout' }),
      ];
    },
  },
  day: {
    description: 'Usage, Hilo, music, an error and device events',
    build: (nowS) => [
      snapshot(nowS),
      mac('usage.update', { session_pct: 81, weekly_pct: 38, reset_in_min: 40, tokens_today: 2100000 }),
      mac('hilo.task_changed', { title: 'Review CloudWatch alerts', project: 'acme', jira: 'DEMO-1423', started_at: nowS }),
      mac('media.now_playing', { title: 'Night Build', artist: 'Tabstop', length_s: 247, position_s: 12 }),
      mac('agent.error', { session: SESSION, detail: '3 tests failed in payments.spec.ts' }),
      buddy('device.battery', { pct: 14, charging: false }),
      buddy('device.sleep', { by: 'long_press' }),
      buddy('device.wake', { by: 'touch' }),
      buddy('device.pet_accessory', { acc: 'wizard' }),
      mac('usage.window_reset', {}),
    ],
  },
  desk: {
    description: 'Settings from Hilo, a pomodoro started on the buddy and music controls',
    build: (nowS) => {
      const work = { phase: 'work', work_min: 25, break_min: 5, cycle: 0 };
      return [
        buddy('device.settings', { sound: false, volume: 60, brightness: 100 }),
        mac('settings.set', { sound: true, volume: 0 }),
        buddy('device.settings', { sound: true, volume: 0, brightness: 100 }),
        buddy('device.pomodoro', { ...work, state: 'running', ends_at: nowS + 1500, updated_at: nowS }),
        mac('pomodoro.state', { ...work, state: 'paused', left_s: 1200, updated_at: nowS + 300 }),
        mac('media.now_playing', { title: 'Night Build', artist: 'Tabstop', length_s: 247, position_s: 12, playing: true }),
        buddy('media.control', { action: 'next' }),
      ];
    },
  },
};
