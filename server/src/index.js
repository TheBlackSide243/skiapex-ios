// The Ski Apex server: accounts, friends, the leaderboards among friends and, for those who turn
// it on, where each friend is while skiing. On Cloudflare Workers with one Durable Object. It
// keeps a name, a password hash (or, for who signs in with Apple or Google, the identifier those
// give: no email), a small profile picture if one was set and, for each season, the totals of the
// days an account chose to share. No tracks and no places are ever stored; a position shared live
// is held in memory only, the last one, and forgotten ten minutes after its last update.
//
// For who chooses to tell, it also keeps where a day was skied, to the kilometer, with how the snow
// was and the numbers of the day: the snow of a ski area as the people there found it, the average
// day there, and which friends have been.
//
// For who turns on the challenge on the pistes, it keeps the pistes skied by name, where they are
// to the kilometer and the best time down each: seen by friends only. A meeting point set for the
// friends (a place chosen on the map, not where one is) is kept until it is over, a day at most,
// with who said they are coming and who said they are not.

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
const MAX_PHOTO = 100 * 1024;
// How the snow was, as told at the end of a day.
const SNOW = ['powder', 'groomed', 'hard', 'icy', 'crust', 'wet', 'wind'];
// What is told of a ski area counts within this many meters of where it is asked about.
const PLACE_RADIUS = 10000;
// How the snow was is news for a few days; the days of a ski area are kept for a season and a bit.
const SNOW_DAYS = 5;
const VISIT_DAYS = 400;
const MAX_VISITS = 600;
// The pistes of an account, for the challenge among friends; a piste of the same name within
// this many meters is the same piste.
const MAX_PISTES = 300;
const PISTE_RADIUS = 15000;
// A meeting point lasts half a day unless told otherwise, and never more than a day.
const MEETING_TTL = 12 * 3600 * 1000;
const MAX_MEETING = 24 * 3600 * 1000;
// Who signs the tokens of "Sign in with Apple" and of Google, and what they call themselves.
const PROVIDERS = {
  apple: { keys: 'https://appleid.apple.com/auth/keys', issuers: ['https://appleid.apple.com'] },
  google: { keys: 'https://www.googleapis.com/oauth2/v3/certs', issuers: ['https://accounts.google.com', 'accounts.google.com'] },
};
// The apps an Apple token may be for: the TestFlight one and the sideloaded one.
const APPLE_AUDIENCES = ['win.shadowbyte.skiapex', 'com.local.skiapex'];

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
    // The public keys of Apple and Google, kept for an hour.
    this.jwks = new Map();
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
    const social = path.match(/^\/v1\/sessions\/(apple|google)$/);
    if (social && method === 'POST') return this.signInWith(social[1], await body(request), ip);
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
      // The password, or for an account made with Apple or Google a plain yes: the token says who it is.
      if (user.hash ? !(await this.check(user, b?.password)) : b?.confirm !== true) return json({ error: 'wrong password' }, 403);
      for (const f of user.friends || []) {
        const other = await this.byID(f.id);
        if (other) await this.unfriend(user, other);
      }
      if (user.invite) await this.state.storage.delete('invite:' + user.invite);
      this.positions.delete(user.id);
      const seasons = (user.seasons || []).map(year => `season:${user.id}:${year}`);
      await this.forgetVisits(user);
      const own = ['photo:' + user.id, 'pistes:' + user.id, 'meet:' + user.id, ...(user.ext ? [user.ext] : [])];
      await this.state.storage.delete([...user.tokens.map(t => 'token:' + t), ...seasons, ...own, 'user:' + user.name.toLowerCase(), 'id:' + user.id]);
      return json({ ok: true });
    }
    if (path === '/v1/me/photo' && method === 'PUT') return this.setPhoto(user, request);
    if (path === '/v1/me/photo' && method === 'DELETE') {
      await this.state.storage.delete('photo:' + user.id);
      user.photo = 0;
      await this.save(user);
      return json(this.view(user));
    }
    const photo = path.match(/^\/v1\/photos\/([^/]+)$/);
    if (photo && method === 'GET') return this.photo(user, photo[1]);
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
    if (path === '/v1/friends/positions' && method === 'GET') {
      return json({ friends: await this.around(user), meetings: await this.meetings(user) });
    }
    if (path === '/v1/me/meeting' && method === 'PUT') return this.meet(user, await body(request));
    if (path === '/v1/me/meeting' && method === 'DELETE') {
      await this.state.storage.delete('meet:' + user.id);
      return json({ ok: true, meetings: await this.meetings(user) });
    }
    if (path === '/v1/meetings' && method === 'GET') return json({ meetings: await this.meetings(user) });
    const answered = path.match(/^\/v1\/meetings\/([^/]+)\/answer$/);
    if (answered && method === 'PUT') return this.answer(user, answered[1], await body(request));
    if (path === '/v1/me/pistes' && method === 'PUT') return this.sharePistes(user, await body(request));
    if (path === '/v1/me/pistes' && method === 'DELETE') {
      await this.state.storage.delete('pistes:' + user.id);
      return json({ ok: true });
    }
    if (path === '/v1/pistes' && method === 'GET') {
      return this.pisteBoard(user, url.searchParams.get('name'), Number(url.searchParams.get('lat')), Number(url.searchParams.get('lon')));
    }
    if (path === '/v1/places/visits' && method === 'PUT') return this.visit(user, await body(request));
    if (path === '/v1/places/visits' && method === 'DELETE') return this.unvisit(user, await body(request));
    if (path === '/v1/places' && method === 'GET') {
        return this.aboutPlace(user, Number(url.searchParams.get('lat')), Number(url.searchParams.get('lon')));
    }
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

  /// In with Apple or with Google: the token they gave the phone is checked against their public
  /// keys, and the account is the one of that person there, made the first time. No email is asked
  /// for or kept: only the identifier, and a name to show to friends.
  async signInWith(provider, b, ip) {
    const audiences = list(provider === 'apple' ? this.env.APPLE_AUDIENCES : this.env.GOOGLE_CLIENT_IDS)
      ?? (provider === 'apple' ? APPLE_AUDIENCES : []);
    if (!audiences.length) return json({ error: 'not set up' }, 503);
    const tries = 'ip:' + ip;
    if (!this.allowed(tries)) return json({ error: 'too many attempts' }, 429);
    const claims = await this.verify(provider, b?.token, audiences);
    if (!claims) {
      this.fail(tries);
      return json({ error: 'bad token' }, 403);
    }
    const key = `ext:${provider}:${claims.sub}`;
    const id = await this.state.storage.get(key);
    let user = id ? await this.byID(id) : null;
    let status = 200;
    if (!user) {
      if (!this.count(this.signups, ip, SIGNUPS_PER_HOUR, 3600 * 1000)) return json({ error: 'too many accounts' }, 429);
      const name = await this.freeName(typeof b?.name === 'string' && b.name.trim() ? b.name : claims.given_name || claims.name || '');
      user = { id: crypto.randomUUID(), name, created: Date.now(), tokens: [], friends: [], seasons: [], ext: key, kind: provider };
      await this.state.storage.put({ ['user:' + name.toLowerCase()]: user, ['id:' + user.id]: name.toLowerCase(), [key]: user.id });
      status = 201;
    }
    return json({ token: await this.issue(user), account: this.view(user) }, status);
  }

  /// The claims of a token signed by Apple or Google for one of our apps, or null.
  async verify(provider, token, audiences) {
    if (typeof token !== 'string' || token.length > 6000) return null;
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    let header, claims, signature;
    try {
      header = JSON.parse(new TextDecoder().decode(unbase64url(parts[0])));
      claims = JSON.parse(new TextDecoder().decode(unbase64url(parts[1])));
      signature = unbase64url(parts[2]);
    } catch {
      return null;
    }
    if (header?.alg !== 'RS256' || typeof header.kid !== 'string') return null;
    const jwk = await this.signingKey(provider, header.kid);
    if (!jwk) return null;
    try {
      const key = await crypto.subtle.importKey('jwk', { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
      const signed = new TextEncoder().encode(parts[0] + '.' + parts[1]);
      if (!(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, signature, signed))) return null;
    } catch {
      return null;
    }
    if (!PROVIDERS[provider].issuers.includes(claims?.iss)) return null;
    const meant = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (!meant.some(a => audiences.includes(a))) return null;
    if (!(typeof claims.exp === 'number' && claims.exp > Date.now() / 1000)) return null;
    if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 200) return null;
    return claims;
  }

  /// The public key a token says it was signed with. The keys are asked for again when an hour
  /// has passed or a new one shows up, but not more than once a minute.
  async signingKey(provider, kid) {
    let known = this.jwks.get(provider);
    const age = known ? Date.now() - known.at : Infinity;
    if (age > 3600 * 1000 || (!known.keys.some(k => k.kid === kid) && age > 60 * 1000)) {
      try {
        const res = await fetch(PROVIDERS[provider].keys);
        if (res.ok) {
          known = { keys: (await res.json()).keys || [], at: Date.now() };
          this.jwks.set(provider, known);
        }
      } catch {
        // The keys already here, if any, will do.
      }
    }
    return known?.keys.find(k => k.kid === kid) || null;
  }

  /// A name nobody has, as close as can be to the one wanted: letters without accents, dots for
  /// spaces, and a number at the end when it is taken.
  async freeName(wanted) {
    let base = String(wanted).normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().replace(/\s+/g, '.')
      .replace(/[^A-Za-z0-9_.-]/g, '').slice(0, 16);
    if (base.length < 3) base = 'sciatore';
    for (let i = 1; i < 60; i++) {
      const name = i === 1 ? base : base + (i < 40 ? i : randomCode(4).toLowerCase());
      if (!(await this.state.storage.get('user:' + name.toLowerCase()))) return name;
    }
    return base.slice(0, 8) + randomCode(8).toLowerCase();
  }

  // Profile pictures

  /// A small JPEG, seen by you and by your friends.
  async setPhoto(user, request) {
    if (Number(request.headers.get('Content-Length') || 0) > MAX_PHOTO) return json({ error: 'photo too big' }, 413);
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.length > MAX_PHOTO) return json({ error: 'photo too big' }, 413);
    if (bytes.length < 100 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) return json({ error: 'bad photo' }, 400);
    user.photo = Date.now();
    await this.state.storage.put({ ['photo:' + user.id]: bytes, ['user:' + user.name.toLowerCase()]: user });
    return json(this.view(user));
  }

  async photo(user, id) {
    if (id !== user.id && !(user.friends || []).some(f => f.id === id)) return json({ error: 'not found' }, 404);
    const bytes = await this.state.storage.get('photo:' + id);
    if (!bytes) return json({ error: 'not found' }, 404);
    // The address changes with the picture (the app adds its version), so it can be kept for good.
    return new Response(bytes, { headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'private, max-age=31536000, immutable' } });
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

  /// An account as its owner sees it. `photo` is when the picture was set (0: none); `kind` is
  /// how one signs in: password, apple or google.
  view(user) {
    return { ...this.card(user), kind: user.kind || 'password' };
  }

  /// An account as the others see it.
  card(user) {
    return { id: user.id, name: user.name, photo: user.photo || 0 };
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
    return { ...this.card(other), since };
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
        photo: person.photo || 0,
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

  // The challenge on the pistes

  /// The pistes of an account as the phone has them now: they replace what was there. For each,
  /// its name, where it is to the kilometer, the best time down the whole of it, the top speed
  /// and how many times it was skied.
  async sharePistes(user, b) {
    if (!Array.isArray(b?.pistes) || b.pistes.length > MAX_PISTES) return json({ error: 'bad pistes' }, 400);
    const kept = [];
    for (const p of b.pistes) {
      if (typeof p?.name !== 'string' || !p.name.trim() || p.name.length > 120) return json({ error: 'bad piste' }, 400);
      if (typeof p.lat !== 'number' || typeof p.lon !== 'number' || !(Math.abs(p.lat) <= 90) || !(Math.abs(p.lon) <= 180)) {
        return json({ error: 'bad position' }, 400);
      }
      if (typeof p.date !== 'string' || !DATE.test(p.date)) return json({ error: 'bad day' }, 400);
      kept.push({
        n: p.name.trim(),
        la: Math.round(p.lat * 100) / 100,
        lo: Math.round(p.lon * 100) / 100,
        b: number(p.best, 5, 7200),
        v: number(p.speed, 0, 70),
        r: Math.round(number(p.runs, 1, 5000)),
        d: p.date,
      });
    }
    await this.state.storage.put('pistes:' + user.id, kept);
    return json({ ok: true, pistes: kept.length });
  }

  /// One piste among you and your friends: who skied it, the best time of each, the fastest first.
  async pisteBoard(user, name, lat, lon) {
    if (typeof name !== 'string' || !name.trim() || name.length > 120) return json({ error: 'bad piste' }, 400);
    if (!(Math.abs(lat) <= 90) || !(Math.abs(lon) <= 180)) return json({ error: 'bad position' }, 400);
    const people = [user];
    for (const f of user.friends || []) {
      const other = await this.byID(f.id);
      if (other) people.push(other);
    }
    const rows = [];
    for (const person of people) {
      const theirs = ((await this.state.storage.get('pistes:' + person.id)) || [])
        .filter(p => p.n === name.trim() && meters(lat, lon, p.la, p.lo) <= PISTE_RADIUS)
        .sort((a, b) => a.b - b.b)[0];
      if (theirs) rows.push({ ...this.card(person), me: person.id === user.id, best: theirs.b, speed: theirs.v, runs: theirs.r, date: theirs.d });
    }
    return json({ rows: rows.sort((a, b) => a.best - b.best) });
  }

  // Meeting points

  /// A place to meet, for your friends: where, what it is called and, if you say so, at what time.
  /// One for each account: a new one replaces the one before.
  async meet(user, b) {
    if (typeof b?.lat !== 'number' || typeof b?.lon !== 'number' || !(Math.abs(b.lat) <= 90) || !(Math.abs(b.lon) <= 180)) {
      return json({ error: 'bad position' }, 400);
    }
    const now = Date.now();
    const label = typeof b.label === 'string' ? b.label.trim().slice(0, 80) : '';
    const when = typeof b.when === 'number' && b.when > now - 3600 * 1000 && b.when < now + MAX_MEETING ? Math.round(b.when) : null;
    // Over an hour after its time; half a day after it was set when it has none.
    const until = when ? when + 3600 * 1000 : now + MEETING_TTL;
    await this.state.storage.put('meet:' + user.id, { lat: b.lat, lon: b.lon, label, when, until, at: now, answers: {} });
    return json({ ok: true, meetings: await this.meetings(user) }, 201);
  }

  /// Your answer to the place to meet of a friend: you are coming, or you are not. It can be
  /// changed; a new place set by the friend is a new question.
  async answer(user, owner, b) {
    if (typeof b?.coming !== 'boolean') return json({ error: 'bad answer' }, 400);
    const m = user.friends?.some(f => f.id === owner) ? await this.state.storage.get('meet:' + owner) : null;
    if (!m || m.until <= Date.now()) return json({ error: 'no such meeting' }, 404);
    m.answers = { ...(m.answers || {}), [user.id]: { a: b.coming ? 'yes' : 'no', at: Date.now() } };
    await this.state.storage.put('meet:' + owner, m);
    return json({ ok: true, meetings: await this.meetings(user) });
  }

  /// The meeting points of you and of your friends that are not over yet, the newest first.
  async meetings(user) {
    const now = Date.now();
    const out = [];
    const people = [user];
    for (const f of user.friends || []) {
      const other = await this.byID(f.id);
      if (other) people.push(other);
    }
    for (const person of people) {
      const m = await this.state.storage.get('meet:' + person.id);
      if (!m) continue;
      if (m.until <= now) {
        await this.state.storage.delete('meet:' + person.id);
        continue;
      }
      const answers = m.answers || {};
      const mine = person.id === user.id;
      const view = { ...this.card(person), mine, lat: m.lat, lon: m.lon, label: m.label, when: m.when, until: m.until, at: m.at };
      if (mine) {
        // Whose place it is sees every friend with what each said: coming first, then not
        // coming, then who has not answered yet.
        const order = { yes: 0, no: 1 };
        view.answers = people.slice(1)
          .map(friend => ({ ...this.card(friend), answer: answers[friend.id]?.a || null }))
          .sort((a, b) => (order[a.answer] ?? 2) - (order[b.answer] ?? 2) || a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
      } else {
        // The others see what they said themselves.
        view.answer = answers[user.id]?.a || null;
      }
      out.push(view);
    }
    return out.sort((a, b) => b.at - a.at);
  }

  // Ski areas: how the snow was, the average day, the friends who have been

  /// A day told: where (to the kilometer), when, and what the phone chose to tell of it: how the
  /// snow was, its numbers for the averages, and whether friends may see you were there. One for
  /// each day and place: told again, it replaces the one before.
  async visit(user, b) {
    if (typeof b?.date !== 'string' || !DATE.test(b.date)) return json({ error: 'bad day' }, 400);
    if (typeof b.lat !== 'number' || typeof b.lon !== 'number' || !(Math.abs(b.lat) <= 90) || !(Math.abs(b.lon) <= 180)) {
      return json({ error: 'bad position' }, 400);
    }
    if (b.snow != null && !SNOW.includes(b.snow)) return json({ error: 'bad snow' }, 400);
    const lat = Math.round(b.lat * 100) / 100;
    const lon = Math.round(b.lon * 100) / 100;
    const key = cellKey(lat, lon);
    const entry = { u: user.id, d: b.date, la: lat, lo: lon, s: b.snow || null, f: b.friends === true, at: Date.now() };
    if (b.stats && typeof b.stats === 'object') {
      entry.n = {
        v: number(b.stats.vertical, 0, 60000),
        di: number(b.stats.distance, 0, 500000),
        rt: number(b.stats.runTime, 0, 24 * 3600),
        lt: number(b.stats.liftTime, 0, 24 * 3600),
        sp: number(b.stats.avgSpeed, 0, 70),
        r: Math.round(number(b.stats.runs, 0, 300)),
      };
    }
    const old = Date.now() - VISIT_DAYS * 24 * 3600 * 1000;
    const visits = ((await this.state.storage.get(key)) || []).filter(v => !(v.u === user.id && v.d === b.date) && v.at > old);
    visits.push(entry);
    user.places = [...new Set([...(user.places || []), key])];
    await this.state.storage.put({ [key]: visits.slice(-MAX_VISITS), ['user:' + user.name.toLowerCase()]: user });
    return json({ ok: true }, 201);
  }

  /// A day taken back: deleted on the phone, or told by mistake.
  async unvisit(user, b) {
    if (typeof b?.date !== 'string' || !DATE.test(b.date)) return json({ error: 'bad day' }, 400);
    for (const key of user.places || []) {
      const visits = (await this.state.storage.get(key)) || [];
      const left = visits.filter(v => !(v.u === user.id && v.d === b.date));
      if (left.length !== visits.length) await this.state.storage.put(key, left);
    }
    return json({ ok: true });
  }

  async forgetVisits(user) {
    for (const key of user.places || []) {
      const visits = (await this.state.storage.get(key)) || [];
      const left = visits.filter(v => v.u !== user.id);
      if (left.length) await this.state.storage.put(key, left);
      else await this.state.storage.delete(key);
    }
  }

  /// What is known of a ski area: how the snow was in the last days, the average day of who
  /// skied there this winter, and which of your friends have been. No names but your friends'.
  async aboutPlace(user, lat, lon) {
    if (!(Math.abs(lat) <= 90) || !(Math.abs(lon) <= 180)) return json({ error: 'bad position' }, 400);
    const around = [];
    for (const dy of [-1, 0, 1]) {
      for (const dx of [-1, 0, 1]) {
        for (const v of (await this.state.storage.get(cellKey(lat + dy * 0.1, lon + dx * 0.1))) || []) {
          if (meters(lat, lon, v.la, v.lo) <= PLACE_RADIUS) around.push(v);
        }
      }
    }
    const now = Date.now();
    const day = 24 * 3600 * 1000;
    // How the snow was: the kinds told in the last days, the most told first, and the last one.
    const told = around.filter(v => v.s && now - Date.parse(v.d) < (SNOW_DAYS + 1) * day).sort((a, b) => (a.d < b.d ? 1 : a.d > b.d ? -1 : b.at - a.at));
    const counts = {};
    for (const v of told) counts[v.s] = (counts[v.s] || 0) + 1;
    const snow = Object.entries(counts).map(([kind, count]) => ({ kind, count })).sort((a, b) => b.count - a.count);
    // The average day, of the days told with their numbers in the last year.
    const counted = around.filter(v => v.n);
    const mean = pick => (counted.length ? counted.reduce((sum, v) => sum + pick(v.n), 0) / counted.length : 0);
    const averages = counted.length
      ? { days: counted.length, vertical: mean(n => n.v), distance: mean(n => n.di), runTime: mean(n => n.rt), liftTime: mean(n => n.lt),
          avgSpeed: mean(n => n.sp), runs: mean(n => n.r) }
      : null;
    // The friends who said they were here.
    const friends = [];
    for (const f of user.friends || []) {
      const theirs = around.filter(v => v.u === f.id && v.f);
      if (!theirs.length) continue;
      const other = await this.byID(f.id);
      if (other) friends.push({ ...this.card(other), days: theirs.length, last: theirs.map(v => v.d).sort().pop() });
    }
    return json({
      snow,
      latest: told.length ? { kind: told[0].s, date: told[0].d } : null,
      reports: told.length,
      averages,
      friends: friends.sort((a, b) => (a.last < b.last ? 1 : -1)),
      mine: around.filter(v => v.u === user.id).length,
    });
  }

  // Live positions

  /// Where you are now, for your friends: the last one only, in memory. The answer has the friends
  /// who are sharing, so that a phone in a pocket asks once for both.
  async place(user, b) {
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
    return json({ ok: true, friends: await this.around(user), meetings: await this.meetings(user) });
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
      if (other) out.push({ ...this.card(other), ...p });
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

/// The square of a tenth of a degree a place is in: what is told of it is kept together.
function cellKey(lat, lon) {
  return `place:${Math.floor(lat * 10)}:${Math.floor(lon * 10)}`;
}

/// Meters between two places.
function meters(lat1, lon1, lat2, lon2) {
  const rad = Math.PI / 180;
  const h = Math.sin((lat2 - lat1) * rad / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin((lon2 - lon1) * rad / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

function unbase64url(s) {
  const text = atob(String(s).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(text, c => c.charCodeAt(0));
}

/// A list written with commas in a setting of the worker, or null when there is none.
function list(value) {
  if (typeof value !== 'string') return null;
  const items = value.split(',').map(s => s.trim()).filter(Boolean);
  return items.length ? items : null;
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
