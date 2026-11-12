// Claude/Codex usage across accounts and machines. Run through bin/usage, which supplies
// the runtime. Two modes:
//   _usage.js dump <host>                  read this Orca's accounts.list (or the paired one
//                                          named by ORCA_ENVIRONMENT) and print a snapshot
//   _usage.js report <mode> <state> <snap>…  merge snapshots, print the report
//                                          mode: text | json | watch | ack
'use strict';
const fs = require('fs');

const KINDS = ['claude', 'codex'];
const NEAR = 90;           // a window at or above this % makes an account "near its limit"
const THRESHOLDS = [80, 90];  // the operator is told once per window period when an account in use crosses each
const PAUSE = 95;          // AGENTS.md → Pause at 95%: leads on a machine stop when its Claude account is here
const STALE_MS = 6 * 3600e3;
const TIERS = ['normal', 'lean', 'conserve', 'critical', 'exhausted'];
const GUIDE = {
  normal: 'Claude has room: default models as usual.',
  lean: 'Usage is running ahead of the reset, usually still fine across accounts: default models as usual; watch the trend.',
  conserve: 'Usage is well ahead of the reset: consider proposing a cheaper model or agent family to the operator (with per-account usage); no change without their OK.',
  critical: 'Claude is nearly out across accounts: propose a cheaper model or agent family to the operator now (with per-account usage); ask before starting new Claude work.',
  exhausted: 'Every Claude account is at a limit: tell the operator under Broken; only other agent families can run now, with their OK.',
};

const now = () => Number(process.env.CHIEFOFSTAFF_NOW_MS) || Date.now();

// ---------- dump ----------
function windowsOf(rl) {
  if (!rl) return [];
  return ['session', 'weekly', 'monthly'].map(k => rl[k]).filter(w => w && w.windowMinutes)
    .map(w => ({ minutes: w.windowMinutes, used: w.usedPercent, resetsAt: w.resetsAt }));
}
function reading(rl, updatedAt) {
  const ex = rl && rl.extraUsage;
  return {
    status: rl ? rl.status : 'missing', error: (rl && rl.error) || null,
    updatedAt: (rl && rl.updatedAt) || updatedAt || null, windows: windowsOf(rl),
    extra: ex && ex.enabled && ex.spent != null ? { spent: ex.spent, limit: ex.spendLimit, currency: ex.currencyCode } : null,
  };
}
async function dump(host) {
  const { RuntimeClient } = require(process.env.ORCA_CLIENT_JS);
  const r = (await new RuntimeClient().call('accounts.list', {})).result;
  const rl = r.rateLimits || {};
  const out = { host, ok: true };
  for (const k of KINDS) {
    const inactive = rl[`inactive${k[0].toUpperCase()}${k.slice(1)}Accounts`] || [];
    out[k] = {
      active: r[k].activeAccountId,
      accounts: (r[k].accounts || []).map(a => {
        const isActive = a.id === r[k].activeAccountId;
        const ia = inactive.find(x => x.accountId === a.id);
        const twin = (r[k].accounts || []).filter(b => b.email === a.email).length > 1;
        const plan = a.workspaceLabel || a.planType || a.plan || a.label;
        // The same account can appear on several machines, so readings merge by email. Two
        // entries with one email on a machine (two Codex plans, say) are one OpenAI account.
        return { id: a.id, key: a.email, email: twin && plan ? `${a.email} (${plan})` : a.email, active: isActive,
          ...reading(isActive ? rl[k] : ia && ia.rateLimits, ia && ia.updatedAt) };
      }),
    };
  }
  console.log(JSON.stringify(out));
}

// ---------- report ----------
const label = m => m === 300 ? '5h' : m === 10080 ? 'week' : m >= 40000 ? 'month' : `${Math.round(m / 60)}h`;
function left(ms) {
  if (ms <= 0) return 'reset';
  const h = ms / 3600e3;
  return h < 48 ? `${h.toFixed(1)}h` : `${Math.floor(h / 24)}d${Math.round(h % 24)}h`;
}
// Pace of one window. ratio = share of budget left / share of time left: >= 1 is on or
// under pace, < 1 is ahead of it. 90% used with 2h left in a week is ~8 (fine); 90% with
// 5 days left is ~0.14 (far ahead).
function pace(w, t) {
  const total = w.minutes * 60e3, rem = w.resetsAt - t;
  // No reset time, or the window reset after this reading: usage now is unknown.
  if (!w.resetsAt) return { used: w.used, rem: null, timeLeft: null, ratio: null, unknown: true };
  if (rem <= 0) return { used: w.used, rem: 0, timeLeft: 0, ratio: null, reset: true };
  const timeLeft = Math.min(1, rem / total);
  const used = w.used;
  return { used, rem, timeLeft, ratio: (100 - used) / Math.max(100 * timeLeft, 1), ahead: used - 100 * (1 - timeLeft) };
}

function merge(snaps) {
  const kinds = {};
  for (const k of KINDS) {
    const by = new Map();
    for (const s of snaps) {
      if (!s.ok || !s[k]) continue;
      for (const a of s[k].accounts) {
        const key = a.key || a.email || a.id;
        const e = by.get(key) || { email: a.email || key, activeOn: [], ids: {}, windows: new Map(), errors: [], extra: null, updatedAt: 0 };
        if (a.active || !e.ids[s.host]) e.ids[s.host] = a.id;
        if (a.active) e.activeOn.push(s.host);
        if (a.extra && (!e.extra || a.updatedAt > e.updatedAt)) e.extra = a.extra;
        if (a.windows.length) {
          for (const w of a.windows) {
            const prev = e.windows.get(w.minutes);
            if (!prev || (a.updatedAt || 0) > prev.updatedAt) e.windows.set(w.minutes, { ...w, updatedAt: a.updatedAt || 0 });
          }
          e.updatedAt = Math.max(e.updatedAt, a.updatedAt || 0);
        } else if (a.error) e.errors.push(`${s.host}: ${a.error}`);
        by.set(key, e);
      }
    }
    kinds[k] = [...by.values()].map(e => ({ ...e, windows: [...e.windows.values()].sort((x, y) => x.minutes - y.minutes) }));
  }
  return kinds;
}

// The least-used other account usable on host that is below NEAR in every window, or null.
const roomFor = (accts, act, host) => accts.filter(a => a !== act && a.known && !a.near && a.ids[host])
  .sort((x, y) => x.maxUsed - y.maxUsed)[0] || null;

function analyse(snaps, t) {
  const kinds = merge(snaps);
  for (const k of KINDS) for (const a of kinds[k]) {
    a.paces = a.windows.map(w => ({ ...w, label: label(w.minutes), ...pace(w, t), stale: t - w.updatedAt > STALE_MS }));
    const live = a.paces.filter(p => !p.reset);
    a.known = live.length > 0;
    a.maxUsed = a.known ? Math.max(...live.map(p => p.used)) : null;
    a.blocked = a.known && a.maxUsed >= 100;
    a.near = a.known && a.maxUsed >= NEAR;
  }
  // Claude tier from weekly windows across all accounts with a reading.
  const weekly = kinds.claude.map(a => a.paces.find(p => p.minutes === 10080)).filter(p => p && p.ratio !== null);
  const budget = weekly.reduce((s, p) => s + (100 - p.used), 0);
  const time = weekly.reduce((s, p) => s + 100 * p.timeLeft, 0);
  const ratio = weekly.length ? (time > 0 ? budget / time : Infinity) : null;
  // No usable weekly reading at all: the tier is unknown, and --watch leaves its state alone.
  let tier = ratio === null ? 'unknown' : ratio >= 1 ? 'normal' : ratio >= 0.6 ? 'lean' : ratio >= 0.3 ? 'conserve' : 'critical';
  const known = kinds.claude.filter(a => a.known);
  if (known.length && known.every(a => a.blocked)) {
    // Every account with a reading is at a limit; one without a reading might still have room.
    tier = known.length === kinds.claude.length ? 'exhausted' : 'critical';
  }
  // Switch recommendations: per machine and kind, when the active account is near a limit.
  const switches = [];
  for (const s of snaps) {
    if (!s.ok) continue;
    for (const k of KINDS) {
      const act = kinds[k].find(a => a.activeOn.includes(s.host));
      if (!act || !act.near) continue;
      const room = roomFor(kinds[k], act, s.host);
      switches.push({ host: s.host, kind: k, from: act.email, fromUsed: act.maxUsed, to: room ? room.email : null, toId: room ? room.ids[s.host] : null, extra: !!act.extra });
    }
  }
  // Threshold crossings: accounts in use only, live windows only. Only the highest threshold
  // a window has crossed counts, so a jump from 70% to 95% is one 90% crossing.
  const thresholds = [];
  for (const k of KINDS) for (const a of kinds[k]) {
    if (!a.activeOn.length) continue;
    for (const p of a.paces) {
      if (p.reset || p.unknown) continue;
      const th = Math.max(0, ...THRESHOLDS.filter(x => p.used >= x));
      if (!th) continue;
      thresholds.push({ kind: k, email: a.email, activeOn: a.activeOn, label: p.label, minutes: p.minutes, resetsAt: p.resetsAt,
        used: p.used, rem: p.rem, threshold: th });
    }
  }
  // Pause (AGENTS.md → Pause at 95%): per machine, its Claude account is at PAUSE% or more of
  // a live window and no other Claude account usable there has more than 10% left, i.e. is
  // below NEAR in every window (the same room test as switch advice). The window shown is
  // the one that resets last, when the pause can end.
  // okHosts are machines whose Claude account in use has a reading: only they can start or
  // end a pause.
  const pauses = [];
  const okHosts = snaps.filter(s => s.ok && kinds.claude.some(a => a.activeOn.includes(s.host) && a.windows.length)).map(s => s.host);
  for (const host of okHosts) {
    const act = kinds.claude.find(a => a.activeOn.includes(host));
    const hot = act.paces.filter(p => !p.reset && !p.unknown && p.used >= PAUSE).sort((x, y) => y.resetsAt - x.resetsAt);
    if (!hot.length || roomFor(kinds.claude, act, host)) continue;
    const p = hot[0];
    pauses.push({ host, email: act.email, label: p.label, minutes: p.minutes, used: p.used, rem: p.rem, resetsAt: p.resetsAt });
  }
  const anyRead = KINDS.some(k => kinds[k].some(a => a.windows.length));
  return { at: t, tier, ratio, thresholds, pauses, okHosts, anyRead, guide: GUIDE[tier] || 'No current weekly reading for any Claude account; treat as normal and check again.', kinds, switches,
    unreachable: snaps.filter(s => !s.ok).map(s => `${s.host}: ${s.error}`) };
}

function thresholdLine(c, switches) {
  // At 90% say what happens next, from the switch advice for that account.
  const sw = c.threshold >= NEAR ? switches.filter(s => s.kind === c.kind && s.from === c.email)
    .map(s => s.to ? ` chiefofstaff will switch ${s.kind} on ${s.host} to ${s.to}.` : ` No other ${s.kind} account has room on ${s.host}.`).join('') : '';
  return `Threshold: ${c.kind} ${c.email} (active on ${c.activeOn.join(', ')}) is at ${Math.round(c.used)}% of its ${c.label} window, resets in ${left(c.rem)}.${sw}`;
}

const pauseText = p => `claude on ${p.host}: ${p.email} is at ${Math.round(p.used)}% of its ${p.label} window, resets in ${left(p.rem)}, and no other Claude account has more than 10% left. Tell every active lead on ${p.host} to stop at a safe point until the reset (AGENTS.md → Pause at 95%).`;
// Why a pause recorded for e.host no longer holds.
function resumeLine(e, r) {
  const act = r.kinds.claude.find(a => a.activeOn.includes(e.host));
  const room = act && roomFor(r.kinds.claude, act, e.host);
  const why = act.email !== e.email ? `${e.host} now uses ${act.email}`
    : room ? `${room.email} has more than 10% left; switch ${e.host} to it`
    : `${act.email} is below ${PAUSE}% in every window`;
  return `Resume: claude on ${e.host}: the 95% pause is over (${why}). Tell the leads you paused on ${e.host} to carry on.`;
}

function text(r, localHost) {
  const L = [];
  const pct = x => `${Math.round(x)}%`;
  for (const k of KINDS) {
    L.push(`${k}:`);
    for (const a of r.kinds[k]) {
      const on = a.activeOn.length ? ` (active on ${a.activeOn.join(', ')})` : '';
      const ws = a.paces.map(p => {
        if (p.reset) return `${p.label} reset since the last reading`;
        if (p.unknown) return `${p.label} ${pct(p.used)}, reset time unknown`;
        const pacing = p.used >= 100 ? 'at the limit' : p.ratio >= 1 || p.ahead < 1 ? 'on pace' : `ahead of pace by ${Math.round(p.ahead)} pts`;
        return `${p.label} ${pct(p.used)}, resets in ${left(p.rem)}, ${pacing}${p.stale ? ' (stale)' : ''}`;
      });
      const ex = a.extra ? `; extra usage on: ${a.extra.spent}/${a.extra.limit} ${a.extra.currency}` : '';
      L.push(`  ${a.email}${on}: ${ws.length ? ws.join('; ') : 'no reading' + (a.errors.length ? ` (${a.errors[0]})` : '')}${ex}`);
    }
  }
  const ratio = r.ratio === null ? 'no weekly readings' : r.ratio === Infinity ? 'all weekly windows reset' : `budget/time ${r.ratio.toFixed(2)}`;
  L.push(`Claude tier: ${r.tier} (${ratio}). ${r.guide}`);
  for (const s of r.switches) {
    const envs = Object.fromEntries((process.env.CHIEFOFSTAFF_ENVS || '').split('\n').filter(Boolean).map(l => l.split('=')));
    const env = s.host === localHost ? '' : `ORCA_ENVIRONMENT=${envs[s.host] || '<env>'} `;
    L.push(s.to
      ? `Switch ${s.kind} on ${s.host}: ${s.from} is at ${pct(s.fromUsed)}${s.extra ? ' with paid extra usage on' : ''}; switch to ${s.to}: ${env}bin/orca-account ${s.kind} ${s.toId}`
      : `${s.kind} on ${s.host}: ${s.from} is at ${pct(s.fromUsed)} and no other ${s.kind} account has room.`);
  }
  for (const p of r.pauses) L.push(`Pause in force: ${pauseText(p)}`);
  for (const u of r.unreachable) L.push(`Not read: ${u}`);
  return L.join('\n');
}

function report(mode, statePath, files) {
  const snaps = files.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));
  const r = analyse(snaps, now());
  const localHost = process.env.CHIEFOFSTAFF_HOST;
  if (mode === 'json') return console.log(JSON.stringify(r, (k, v) => v === Infinity ? null : v, 1));
  if (mode === 'text') return console.log(text(r, localHost));
  // watch / ack: alert once when the tier worsens, a new switch recommendation appears, an
  // account in use crosses 80% or 90% of a window, or a machine's pause starts or ends.
  let st = {};
  try { st = JSON.parse(fs.readFileSync(statePath, 'utf8')); } catch { /* first run */ }
  const sigs = r.switches.map(s => `${s.host}|${s.kind}|${s.from}|${s.to}`);
  const save = o => { const tmp = `${statePath}.${process.pid}`; fs.writeFileSync(tmp, JSON.stringify(o)); fs.renameSync(tmp, statePath); };
  if (mode === 'ack') {
    if (st.pending) save({ alerted: st.pending });
    return;
  }
  if (!r.anyRead) return;  // nothing read at all: keep the alert state as it is
  const al = { tier: 'normal', switches: [], ...st.alerted };
  // Alerted thresholds are {kind, email, minutes, resetsAt, threshold}; old string entries are dropped.
  const alTh = (al.thresholds || []).filter(e => e && typeof e === 'object');
  // Claude reports resetsAt with millisecond jitter, and windows are at least 5h apart, so
  // the same period is the same account and window with reset times within 30 minutes.
  const same = (e, c) => e.kind === c.kind && e.email === c.email && e.minutes === c.minutes && Math.abs(e.resetsAt - c.resetsAt) < 30 * 60e3;
  // A threshold is new unless it, or a higher one for the same window period, was alerted.
  const freshTh = r.thresholds.filter(c => !alTh.some(e => same(e, c) && e.threshold >= c.threshold));
  // An unknown tier (no Claude weekly reading) leaves the alerted tier alone.
  const known = r.tier !== 'unknown';
  const worse = known && TIERS.indexOf(r.tier) > TIERS.indexOf(al.tier);
  const fresh = sigs.filter(s => !al.switches.includes(s));
  // Forget what cleared, so a tier that drops and rises again alerts again. Thresholds go only
  // when their window period is over (reset time passed); a missing reading keeps them.
  const settled = { tier: known && TIERS.indexOf(r.tier) < TIERS.indexOf(al.tier) ? r.tier : al.tier,
    switches: al.switches.filter(s => sigs.includes(s)),
    thresholds: alTh.filter(e => e.resetsAt > r.at) };
  // Pauses, one per machine: new when the machine had none alerted; over when its reading
  // came in and shows none. An unread machine keeps what was alerted.
  const alP = al.pauses || [];
  const freshP = r.pauses.filter(p => !alP.some(e => e.host === p.host));
  const overP = alP.filter(e => r.okHosts.includes(e.host) && !r.pauses.some(p => p.host === e.host));
  settled.pauses = alP;
  const pendP = [...r.pauses.map(p => ({ host: p.host, email: p.email, minutes: p.minutes, resetsAt: p.resetsAt })),
    ...alP.filter(e => !r.okHosts.includes(e.host))];
  const pendTh = settled.thresholds.map(e => ({ ...e }));
  for (const c of r.thresholds) {
    const e = pendTh.find(x => same(x, c));
    if (e) { e.resetsAt = c.resetsAt; e.threshold = Math.max(e.threshold, c.threshold); }
    else pendTh.push({ kind: c.kind, email: c.email, minutes: c.minutes, resetsAt: c.resetsAt, threshold: c.threshold });
  }
  save({ alerted: settled, pending: { tier: worse ? r.tier : settled.tier, switches: [...new Set([...settled.switches, ...sigs])], thresholds: pendTh, pauses: pendP } });
  const lines = [...freshP.map(p => `Pause: ${pauseText(p)}`), ...overP.map(e => resumeLine(e, r)), ...freshTh.map(c => thresholdLine(c, r.switches))];
  if (lines.length) console.log(lines.join('\n'));
  if (worse || fresh.length || lines.length) console.log(text(r, localHost));
}

const [mode, ...rest] = process.argv.slice(2);
if (mode === 'dump') dump(rest[0]).catch(e => { console.log(JSON.stringify({ host: rest[0], ok: false, error: String(e.message || e).slice(0, 200) })); });
else if (mode === 'report') report(rest[0], rest[1], rest.slice(2));
else { console.error('usage: _usage.js dump <host> | report <text|json|watch|ack> <state> <snapshot>…'); process.exit(2); }
