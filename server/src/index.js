// The Ski Apex server: accounts, friends, the leaderboards among friends and, for those who turn
// it on, where each friend is while skiing. On Cloudflare Workers with one Durable Object. It
// keeps a name, a password hash and, for each season, the totals of the days an account chose to
// share. No tracks and no places are ever stored; a position shared live is held in memory only,
// the last one, and forgotten ten minutes after its last update.

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const USERNAME = /^[A-Za-z0-9_.-]{3,20}$/;
const MIN_PASSWORD = 8;
const MAX_PASSWORD = 200;
const PBKDF2_ROUNDS = 100000;
const MAX_TOKENS = 20;
const LOGIN_FAILURES = 10;
const SIGNUPS_PER_HOUR = 10;
const INVITE = /^[A-HJ-NP-Z2-9]{8}$/;
const INVITE_TTL = 7 * 24 * 3600 * 1000;
const MAX_FRIENDS = 200;
const MAX_DAYS = 400;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const POSITION_TTL = 10 * 60 * 1000;
const PHASES = ['run', 'lift', 'idle'];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    try {
      if (path === '/') return json({ name: 'Ski Apex', api: 1 });
      const invite = path.match(/^\/f\/([^/]+)\/?$/);
      if (invite) return await invitePage(invite[1].toUpperCase(), request, env);
      if (path.startsWith('/v1/')) return await accounts(env).fetch(request);
      return json({ error: 'not found' }, 404);
    } catch (e) {
      console.error(e);
      return json({ error: 'server error' }, 500);
    }
  },
};

const accounts = env => env.ACCOUNTS.get(env.ACCOUNTS.idFromName('accounts'));

/// Every account, its friends and the seasons it shares.
export class Accounts {
  constructor(state, env) {
    this.state = state;
    this.env = env || {};
    this.failures = new Map();
    this.signups = new Map();
    // Where the people sharing live are now: never written to storage.
    this.positions = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    const ip = request.headers.get('CF-Connecting-IP') || '';
    const invited = path.match(/^\/v1\/invites\/([^/]+)$/);
    if (invited && method === 'GET') {
      const from = await this.invitation(invited[1]);
      return from ? json({ name: from.user.name, expires: from.expires }) : json({ error: 'no such invitation' }, 404);
    }
    if (path === '/v1/accounts' && method === 'POST') return this.signUp(await body(request), ip);
    if (path === '/v1/sessions' && method === 'POST') return this.signIn(await body(request), ip);
    const found = await this.byToken(request);
    if (!found) return json({ error: 'signed out' }, 401);
    const { user, hash } = found;
    if (path === '/v1/sessions' && method === 'DELETE') {
      user.tokens = user.tokens.filter(t => t !== hash);
      await this.save(user);
      await this.state.storage.delete('token:' + hash);
      return json({ ok: true });
    }
    if (path === '/v1/me' && method === 'GET') return json(this.view(user));
    if (path === '/v1/me' && method === 'DELETE') {
      const b = await body(request);
      if (!(await this.check(user, b?.password))) return json({ error: 'wrong password' }, 403);
      for (const f of user.friends || []) {
        const other = await this.byID(f.id);
        if (other) await this.unfriend(user, other);
      }
      if (user.invite) await this.state.storage.delete('invite:' + user.invite);
      this.positions.delete(user.id);
      const seasons = (user.seasons || []).map(year => `season:${user.id}:${year}`);
      await this.state.storage.delete([...user.tokens.map(t => 'token:' + t), ...seasons, 'user:' + user.name.toLowerCase(), 'id:' + user.id]);
      return json({ ok: true });
    }
    if (path === '/v1/me/invite' && method === 'POST') return this.invite(user, (await body(request))?.renew === true);
    if (path === '/v1/friends' && method === 'GET') return json({ friends: await this.friendsOf(user) });
    if (path === '/v1/friends' && method === 'POST') return this.accept(user, (await body(request))?.code);
    const friend = path.match(/^\/v1\/friends\/([^/]+)$/);
    if (friend && method === 'DELETE') {
      const other = user.friends?.some(f => f.id === friend[1]) ? await this.byID(friend[1]) : null;
      if (!other) return json({ error: 'not a friend' }, 404);
      await this.unfriend(user, other);
      return json({ ok: true });
    }
    if (path === '/v1/me/position' && method === 'PUT') return this.place(user, await body(request));
    if (path === '/v1/me/position' && method === 'DELETE') {
      this.positions.delete(user.id);
      return json({ ok: true });
    }
    if (path === '/v1/friends/positions' && method === 'GET') return json({ friends: await this.around(user) });
    const season = path.match(/^\/v1\/me\/seasons\/(\d{4})$/);
    if (season && method === 'PUT') return this.share(user, Number(season[1]), await body(request));
    if (path === '/v1/board' && method === 'GET') return this.board(user, Number(url.searchParams.get('season')));
    return json({ error: 'not found' }, 404);
  }

  // Accounts

  async signUp(b, ip) {
    const name = typeof b?.username === 'string' ? b.username.trim() : '';
    if (!USERNAME.test(name)) return json({ error: 'bad username' }, 400);
    if (!goodPassword(b?.password)) return json({ error: 'password too short' }, 400);
    if (!this.count(this.signups, ip, SIGNUPS_PER_HOUR, 3600 * 1000)) return json({ error: 'too many accounts' }, 429);
    const key = 'user:' + name.toLowerCase();
    if (await this.state.storage.get(key)) return json({ error: 'username taken' }, 409);
    const user = { id: crypto.randomUUID(), name, created: Date.now(), tokens: [], friends: [], seasons: [], ...(await hashPassword(b.password)) };
    await this.state.storage.put({ [key]: user, ['id:' + user.id]: name.toLowerCase() });
    return json({ token: await this.issue(user), account: this.view(user) }, 201);
  }

  async signIn(b, ip) {
    const name = typeof b?.username === 'string' ? b.username.trim().toLowerCase() : '';
    const tries = 'ip:' + ip;
    const named = 'name:' + name;
    if (!this.allowed(tries) || !this.allowed(named)) return json({ error: 'too many attempts' }, 429);
    const user = USERNAME.test(name) ? await this.state.storage.get('user:' + name) : null;
    if (!user || !(await this.check(user, b?.password))) {
      this.fail(tries);
      this.fail(named);
      return json({ error: 'wrong username or password' }, 403);
    }
    this.failures.delete(named);
    return json({ token: await this.issue(user), account: this.view(user) });
  }

  /// A new token for a phone; the oldest go when there are too many.
  async issue(user) {
    const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
    const hash = await sha256(token);
    user.tokens.push(hash);
    const dropped = user.tokens.length > MAX_TOKENS ? user.tokens.splice(0, user.tokens.length - MAX_TOKENS) : [];
    if (dropped.length) await this.state.storage.delete(dropped.map(t => 'token:' + t));
    await this.state.storage.put({ ['user:' + user.name.toLowerCase()]: user, ['token:' + hash]: user.name.toLowerCase() });
    return token;
  }

  async byToken(request) {
    const auth = request.headers.get('Authorization') || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
    if (!/^[A-Za-z0-9_-]{20,100}$/.test(token)) return null;
    const hash = await sha256(token);
    const name = await this.state.storage.get('token:' + hash);
    const user = name ? await this.state.storage.get('user:' + name) : null;
    return user && user.tokens.includes(hash) ? { user, hash } : null;
  }

  async byID(id) {
    const name = typeof id === 'string' ? await this.state.storage.get('id:' + id) : null;
    return name ? this.state.storage.get('user:' + name) : null;
  }

  async check(user, password) {
    if (typeof password !== 'string' || password.length > MAX_PASSWORD) return false;
    const { hash } = await hashPassword(password, user.salt);
    return same(hash, user.hash);
  }

  save(user) {
    return this.state.storage.put('user:' + user.name.toLowerCase(), user);
  }

  view(user) {
    return { id: user.id, name: user.name };
  }

  // Friends

  /// Your invitation link's code: the same one for a week, so a link sent around keeps working; a
  /// new one when it has less than a day left, or when you ask (the old one stops working).
  async invite(user, renew) {
    const storage = this.state.storage;
    const current = user.invite ? await storage.get('invite:' + user.invite) : null;
    if (current && !renew && current.expires - Date.now() > 24 * 3600 * 1000) {
      return json({ code: user.invite, expires: current.expires });
    }
    for (let i = 0; i < 6; i++) {
      const code = randomCode(8);
      if (await storage.get('invite:' + code)) continue;
      const expires = Date.now() + INVITE_TTL;
      if (user.invite) await storage.delete('invite:' + user.invite);
      user.invite = code;
      await storage.put({ ['invite:' + code]: { id: user.id, expires }, ['user:' + user.name.toLowerCase()]: user });
      return json({ code, expires }, 201);
    }
    return json({ error: 'busy' }, 503);
  }

  /// Who an invitation is from, while it is good.
  async invitation(raw) {
    const code = typeof raw === 'string' ? raw.toUpperCase() : '';
    if (!INVITE.test(code)) return null;
    const inv = await this.state.storage.get('invite:' + code);
    if (!inv || inv.expires < Date.now()) return null;
    const user = await this.byID(inv.id);
    return user && user.invite === code ? { user, expires: inv.expires } : null;
  }

  /// An invitation accepted: friends both ways, from now.
  async accept(user, code) {
    const from = await this.invitation(code);
    if (!from) return json({ error: 'no such invitation' }, 404);
    const other = from.user;
    if (other.id === user.id) return json({ error: 'that is you' }, 409);
    user.friends ||= [];
    other.friends ||= [];
    if (user.friends.some(f => f.id === other.id)) return json(this.friendView(other, user));
    if (user.friends.length >= MAX_FRIENDS || other.friends.length >= MAX_FRIENDS) return json({ error: 'too many friends' }, 409);
    const since = Date.now();
    user.friends.push({ id: other.id, since });
    other.friends.push({ id: user.id, since });
    await this.state.storage.put({ ['user:' + user.name.toLowerCase()]: user, ['user:' + other.name.toLowerCase()]: other });
    return json(this.friendView(other, user), 201);
  }

  async unfriend(user, other) {
    user.friends = (user.friends || []).filter(f => f.id !== other.id);
    other.friends = (other.friends || []).filter(f => f.id !== user.id);
    await this.state.storage.put({ ['user:' + user.name.toLowerCase()]: user, ['user:' + other.name.toLowerCase()]: other });
  }

  /// Your friends by name; friends whose account went are dropped on the way.
  async friendsOf(user) {
    const out = [];
    for (const f of user.friends || []) {
      const other = await this.byID(f.id);
      if (other) out.push(this.friendView(other, user));
    }
    if (out.length !== (user.friends || []).length) {
      user.friends = user.friends.filter(f => out.some(o => o.id === f.id));
      await this.save(user);
    }
    return out.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  }

  friendView(other, user) {
    const since = (user.friends || []).find(f => f.id === other.id)?.since ?? null;
    return { ...this.view(other), since };
  }

  // Seasons and leaderboards

  /// The days of a season as the phone has them now: they replace what was there, so sending them
  /// again changes nothing and a day deleted on the phone goes from the totals too. Only the
  /// totals are kept.
  async share(user, year, b) {
    if (!(year >= 2000 && year <= 2100)) return json({ error: 'bad season' }, 400);
    if (!Array.isArray(b?.days) || b.days.length > MAX_DAYS) return json({ error: 'bad days' }, 400);
    const dates = new Set();
    const totals = { days: 0, vertical: 0, runs: 0, distance: 0, time: 0, maxSpeed: 0, updated: Date.now() };
    for (const d of b.days) {
      if (typeof d?.date !== 'string' || !DATE.test(d.date)) return json({ error: 'bad day' }, 400);
      dates.add(d.date);
      totals.vertical += number(d.vertical, 0, 60000);
      totals.runs += Math.round(number(d.runs, 0, 300));
      totals.distance += number(d.distance, 0, 500000);
      totals.time += number(d.time, 0, 24 * 3600);
      totals.maxSpeed = Math.max(totals.maxSpeed, number(d.maxSpeed, 0, 70));
    }
    totals.days = dates.size;
    user.seasons = [...new Set([...(user.seasons || []), year])];
    await this.state.storage.put({ [`season:${user.id}:${year}`]: totals, ['user:' + user.name.toLowerCase()]: user });
    return json({ season: year, ...totals });
  }

  /// A season of you and your friends, one row each: the phone sorts it by what it shows.
  async board(user, year) {
    if (!(year >= 2000 && year <= 2100)) return json({ error: 'bad season' }, 400);
    const rows = [];
    const people = [user];
    for (const f of user.friends || []) {
      const other = await this.byID(f.id);
      if (other) people.push(other);
    }
    for (const person of people) {
      const t = (await this.state.storage.get(`season:${person.id}:${year}`)) || {};
      rows.push({
        id: person.id,
        name: person.name,
        me: person.id === user.id,
        days: t.days || 0,
        vertical: t.vertical || 0,
        runs: t.runs || 0,
        distance: t.distance || 0,
        time: t.time || 0,
        maxSpeed: t.maxSpeed || 0,
      });
    }
    return json({ season: year, rows });
  }

  // Live positions

  /// Where you are now, for your friends: the last one only, in memory.
  place(user, b) {
    if (typeof b?.lat !== 'number' || typeof b?.lon !== 'number' || !(Math.abs(b.lat) <= 90) || !(Math.abs(b.lon) <= 180)) {
      return json({ error: 'bad position' }, 400);
    }
    this.positions.set(user.id, {
      lat: b.lat,
      lon: b.lon,
      alt: number(b.alt, -500, 9000),
      speed: number(b.speed, 0, 70),
      phase: PHASES.includes(b.phase) ? b.phase : 'idle',
      at: Date.now(),
    });
    return json({ ok: true });
  }

  /// Your friends who are sharing right now; the ones not heard from for ten minutes are forgotten.
  async around(user) {
    const now = Date.now();
    for (const [id, p] of this.positions) if (now - p.at > POSITION_TTL) this.positions.delete(id);
    const out = [];
    for (const f of user.friends || []) {
      const p = this.positions.get(f.id);
      if (!p) continue;
      const other = await this.byID(f.id);
      if (other) out.push({ id: other.id, name: other.name, ...p });
    }
    return out;
  }

  // Too many tries

  allowed(key) {
    const now = Date.now();
    const recent = (this.failures.get(key) || []).filter(t => now - t < 15 * 60 * 1000);
    this.failures.set(key, recent);
    return recent.length < LOGIN_FAILURES;
  }

  fail(key) {
    this.failures.set(key, [...(this.failures.get(key) || []), Date.now()]);
  }

  count(map, key, max, window) {
    const now = Date.now();
    const recent = (map.get(key) || []).filter(t => now - t < window);
    if (recent.length >= max) return false;
    recent.push(now);
    map.set(key, recent);
    return true;
  }
}

// The page of an invitation link

const PAGE_TEXT = {
  it: {
    title: name => `${name} ti invita su Ski Apex`,
    body: 'Apri l\'invito nell\'app per diventare amici e confrontare le vostre stagioni sugli sci: giorni sulla neve, dislivello, chilometri.',
    open: 'Apri in Ski Apex',
    app: 'Non hai ancora l\'app? Ski Apex è su TestFlight e su GitHub.',
    goneTitle: 'Invito scaduto',
    gone: 'Questo invito non è più valido. Chiedi un link nuovo a chi te l\'ha mandato.',
  },
  en: {
    title: name => `${name} invites you to Ski Apex`,
    body: 'Open the invitation in the app to become friends and compare your seasons on skis: days on the snow, vertical, distance.',
    open: 'Open in Ski Apex',
    app: 'No app yet? Ski Apex is on TestFlight and on GitHub.',
    goneTitle: 'Invitation expired',
    gone: 'This invitation is no longer valid. Ask whoever sent it for a new link.',
  },
};

async function invitePage(code, request, env) {
  const lang = /^it\b/i.test(request.headers.get('Accept-Language') || '') ? 'it' : 'en';
  const t = PAGE_TEXT[lang];
  const res = INVITE.test(code) ? await accounts(env).fetch(new Request(`https://accounts/v1/invites/${code}`)) : null;
  if (!res?.ok) {
    return html(page(lang, t.goneTitle, `<h1>${esc(t.goneTitle)}</h1><p>${esc(t.gone)}</p>`), 404);
  }
  const { name } = await res.json();
  const title = t.title(name);
  return html(page(lang, title, `
<p class="kicker">SKI APEX</p>
<h1>${esc(title)}</h1>
<p>${esc(t.body)}</p>
<p><a class="open" href="skiapex://friend/${code}">${esc(t.open)}</a></p>
<p class="code">${code}</p>
<p class="small">${esc(t.app)} <a href="https://github.com/TheBlackSide243/skiapex-ios">github.com/TheBlackSide243/skiapex-ios</a></p>`));
}

function page(lang, title, body) {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta property="og:title" content="${esc(title)}">
<title>${esc(title)}</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0b1626; color: #f2f6fb;
         font: 16px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
  main { max-width: 30rem; margin: 1rem; padding: 2rem; background: #15253c; border: 1px solid rgba(255,255,255,.12); border-radius: 22px; }
  h1 { font-size: 1.5rem; line-height: 1.25; margin: .2rem 0 1rem; }
  p { color: #98a9bf; font-family: system-ui, sans-serif; }
  .kicker { color: #5ccfff; font: 700 .8rem ui-monospace, monospace; letter-spacing: .12em; margin: 0; }
  .open { display: block; text-align: center; padding: 1rem; border-radius: 999px; background: #5ccfff; color: #07121f;
          font: 600 1rem ui-monospace, monospace; text-decoration: none; }
  .code { text-align: center; font: 600 1.3rem ui-monospace, monospace; letter-spacing: .2em; color: #f2f6fb; }
  .small { font-size: .85rem; }
  a { color: #5ccfff; }
</style>
</head>
<body><main>${body}</main></body>
</html>`;
}

// Helpers

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function html(body, status = 200) {
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'" },
  });
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function randomCode(length) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return [...bytes].map(b => CODE_CHARS[b % CODE_CHARS.length]).join('');
}

/// A number from the phone, kept between two limits; anything else is the lower one.
function number(x, lo, hi) {
  return typeof x === 'number' && Number.isFinite(x) ? Math.min(hi, Math.max(lo, x)) : lo;
}

async function body(request) {
  return request.json().catch(() => null);
}

function goodPassword(p) {
  return typeof p === 'string' && p.length >= MIN_PASSWORD && p.length <= MAX_PASSWORD;
}

/// A password as a PBKDF2-SHA256 hash with a random salt (or the stored one, to check it).
async function hashPassword(password, saltHex) {
  const salt = saltHex ? Uint8Array.from(saltHex.match(/../g).map(h => parseInt(h, 16))) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ROUNDS }, key, 256);
  return { salt: hex(salt), hash: hex(new Uint8Array(bits)) };
}

/// Two hashes compared in a time that does not depend on where they differ.
function same(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function sha256(s) {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))));
}

function hex(bytes) {
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
