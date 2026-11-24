// Accounts, friends and leaderboards through the worker, with an in-memory stand-in for the
// Durable Object: `npm test` in server/.
import test from 'node:test';
import assert from 'node:assert/strict';

const { default: worker, Accounts } = await import('../src/index.js');

function fakeState() {
  const data = new Map();
  return {
    storage: {
      async get(k) {
        return structuredClone(data.get(k));
      },
      async put(k, v) {
        if (typeof k === 'object') for (const [a, b] of Object.entries(k)) data.set(a, structuredClone(b));
        else data.set(k, structuredClone(v));
      },
      async delete(k) {
        for (const key of Array.isArray(k) ? k : [k]) data.delete(key);
      },
      data,
    },
  };
}

function server() {
  const state = fakeState();
  const object = new Accounts(state);
  const env = {
    ACCOUNTS: {
      idFromName: name => name,
      get: () => ({ fetch: (input, init) => object.fetch(input instanceof Request ? input : new Request(input, init)) }),
    },
  };
  const call = async (method, path, { token, body, headers = {} } = {}) => {
    const h = { 'CF-Connecting-IP': '9.9.9.9', ...headers };
    if (token) h.Authorization = 'Bearer ' + token;
    if (body !== undefined) h['Content-Type'] = 'application/json';
    const res = await worker.fetch(new Request('https://skiapex.test' + path, {
      method,
      headers: h,
      body: body === undefined ? undefined : JSON.stringify(body),
    }), env);
    const type = res.headers.get('Content-Type') || '';
    return { status: res.status, body: type.includes('json') ? await res.json() : await res.text() };
  };
  const signUp = async username => {
    const made = await call('POST', '/v1/accounts', { body: { username, password: 'neve-2026' } });
    assert.equal(made.status, 201);
    return { token: made.body.token, id: made.body.account.id };
  };
  const befriend = async (a, b) => {
    const { body } = await call('POST', '/v1/me/invite', { token: a.token, body: {} });
    const accepted = await call('POST', '/v1/friends', { token: b.token, body: { code: body.code } });
    assert.equal(accepted.status, 201);
  };
  // Bytes instead of JSON, there and back: for the profile pictures.
  const send = (method, path, { token, bytes, type = 'image/jpeg' } = {}) => worker.fetch(new Request('https://skiapex.test' + path, {
    method,
    headers: { 'CF-Connecting-IP': '9.9.9.9', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(bytes ? { 'Content-Type': type } : {}) },
    body: bytes,
  }), env);
  return { call, signUp, befriend, send, data: state.storage.data, object };
}

const day = (date, vertical, more = {}) => ({ date, vertical, runs: 10, distance: 20000, time: 7200, maxSpeed: 18, ...more });

test('an account signs up, signs in and out, and is not kept in clear', async () => {
  const { call, signUp, data } = server();
  const alessio = await signUp('Alessio');
  assert.equal((await call('GET', '/v1/me', { token: alessio.token })).body.name, 'Alessio');
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'alessio', password: 'neve-2026' } })).status, 409);
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'ab', password: 'neve-2026' } })).status, 400);
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'Corta', password: 'neve' } })).status, 400);
  assert.equal((await call('POST', '/v1/sessions', { body: { username: 'ALESSIO', password: 'sbagliata' } })).status, 403);
  const again = await call('POST', '/v1/sessions', { body: { username: 'ALESSIO', password: 'neve-2026' } });
  assert.equal(again.status, 200);
  assert.equal((await call('DELETE', '/v1/sessions', { token: again.body.token })).status, 200);
  assert.equal((await call('GET', '/v1/me', { token: again.body.token })).status, 401);
  assert.equal((await call('GET', '/v1/me', { token: alessio.token })).status, 200);
  assert.equal((await call('GET', '/v1/me')).status, 401);
  const stored = JSON.stringify([...data.entries()]);
  assert.ok(!stored.includes('neve-2026'), 'the password is hashed');
  assert.ok(!stored.includes(alessio.token), 'the token is hashed');
});

test('an invitation makes two people friends both ways, once', async () => {
  const { call, signUp } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const invite = await call('POST', '/v1/me/invite', { token: a.token, body: {} });
  assert.equal(invite.status, 201);
  assert.match(invite.body.code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal((await call('POST', '/v1/me/invite', { token: a.token, body: {} })).body.code, invite.body.code, 'the same link for a week');
  assert.equal((await call('GET', '/v1/invites/' + invite.body.code.toLowerCase())).body.name, 'Alessio');
  assert.equal((await call('POST', '/v1/friends', { token: a.token, body: { code: invite.body.code } })).status, 409, 'not with yourself');
  assert.equal((await call('POST', '/v1/friends', { token: b.token, body: { code: 'AAAAAAAA' } })).status, 404);
  assert.equal((await call('POST', '/v1/friends', { token: b.token, body: { code: invite.body.code } })).status, 201);
  assert.equal((await call('POST', '/v1/friends', { token: b.token, body: { code: invite.body.code } })).status, 200, 'already friends');
  assert.deepEqual((await call('GET', '/v1/friends', { token: a.token })).body.friends.map(f => f.name), ['Alex']);
  assert.deepEqual((await call('GET', '/v1/friends', { token: b.token })).body.friends.map(f => f.name), ['Alessio']);
  const renewed = await call('POST', '/v1/me/invite', { token: a.token, body: { renew: true } });
  assert.notEqual(renewed.body.code, invite.body.code);
  assert.equal((await call('GET', '/v1/invites/' + invite.body.code)).status, 404, 'the old link stops working');
  assert.equal((await call('DELETE', '/v1/friends/' + a.id, { token: b.token })).status, 200);
  assert.deepEqual((await call('GET', '/v1/friends', { token: a.token })).body.friends, []);
  assert.equal((await call('DELETE', '/v1/friends/' + a.id, { token: b.token })).status, 404);
});

test('the leaderboard has you and your friends, and nobody else', async () => {
  const { call, signUp, befriend } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Estraneo');
  await befriend(a, b);
  const sent = await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: [
    day('2026-12-06', 4000), day('2026-12-06', 1000, { maxSpeed: 22 }), day('2027-01-10', 5000),
  ] } });
  assert.equal(sent.status, 200);
  assert.equal(sent.body.days, 2, 'two recordings on the same date are one day on the mountain');
  assert.equal(sent.body.vertical, 10000);
  assert.equal(sent.body.maxSpeed, 22);
  await call('PUT', '/v1/me/seasons/2026', { token: b.token, body: { days: [day('2026-12-20', 7000)] } });
  await call('PUT', '/v1/me/seasons/2026', { token: c.token, body: { days: [day('2026-12-20', 99000)] } });

  const board = await call('GET', '/v1/board?season=2026', { token: a.token });
  assert.deepEqual(board.body.rows.map(r => r.name).sort(), ['Alessio', 'Alex']);
  const me = board.body.rows.find(r => r.me);
  assert.equal(me.name, 'Alessio');
  assert.equal(me.runs, 30);
  assert.equal(board.body.rows.find(r => !r.me).vertical, 7000);
  assert.deepEqual((await call('GET', '/v1/board?season=2026', { token: c.token })).body.rows.map(r => r.vertical), [60000],
    'alone on your board, and a day is capped at what a day can be');
  assert.deepEqual((await call('GET', '/v1/board?season=2025', { token: a.token })).body.rows.map(r => r.days), [0, 0]);

  // Sent again with a day less: the totals follow, they do not pile up.
  const fewer = await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: [day('2027-01-10', 5000)] } });
  assert.equal(fewer.body.vertical, 5000);
  assert.equal(fewer.body.days, 1);
});

test('what is sent is checked', async () => {
  const { call, signUp } = server();
  const a = await signUp('Alessio');
  assert.equal((await call('PUT', '/v1/me/seasons/2026', { body: { days: [] } })).status, 401);
  assert.equal((await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: 'tutti' } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: [{ date: 'ieri', vertical: 1 }] } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/seasons/1999', { token: a.token, body: { days: [] } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: new Array(401).fill(day('2026-12-01', 1)) } })).status, 400);
  const odd = await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: [{ date: '2026-12-01', vertical: 'molto', runs: -4, maxSpeed: 900 }] } });
  assert.equal(odd.body.vertical, 0);
  assert.equal(odd.body.runs, 0);
  assert.equal(odd.body.maxSpeed, 70);
  assert.equal((await call('GET', '/v1/board', { token: a.token })).status, 400);
  assert.equal((await call('GET', '/v1/altro', { token: a.token })).status, 404);
  assert.equal((await call('GET', '/altro')).status, 404);
  assert.equal((await call('GET', '/')).body.name, 'Ski Apex');
});

test('a deleted account leaves nothing behind', async () => {
  const { call, signUp, befriend, data } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  await befriend(a, b);
  await call('PUT', '/v1/me/seasons/2026', { token: a.token, body: { days: [day('2026-12-06', 4000)] } });
  assert.equal((await call('DELETE', '/v1/me', { token: a.token, body: { password: 'sbagliata' } })).status, 403);
  assert.equal((await call('DELETE', '/v1/me', { token: a.token, body: { password: 'neve-2026' } })).status, 200);
  assert.equal((await call('GET', '/v1/me', { token: a.token })).status, 401);
  assert.deepEqual((await call('GET', '/v1/friends', { token: b.token })).body.friends, []);
  assert.deepEqual((await call('GET', '/v1/board?season=2026', { token: b.token })).body.rows.map(r => r.name), ['Alex']);
  assert.ok(![...data.keys()].some(k => k.includes(a.id) || k === 'user:alessio'), 'no key of the account is left');
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'Alessio', password: 'neve-2026' } })).status, 201, 'the name is free again');
});

test('the invitation page opens the app, and says so when the link is old', async () => {
  const { call, signUp } = server();
  const a = await signUp('Alessio');
  const { body } = await call('POST', '/v1/me/invite', { token: a.token, body: {} });
  const page = await call('GET', '/f/' + body.code, { headers: { 'Accept-Language': 'it-IT' } });
  assert.equal(page.status, 200);
  assert.ok(page.body.includes('Alessio ti invita su Ski Apex'));
  assert.ok(page.body.includes(`skiapex://friend/${body.code}`));
  const english = await call('GET', '/f/' + body.code.toLowerCase());
  assert.ok(english.body.includes('Alessio invites you to Ski Apex'));
  const gone = await call('GET', '/f/AAAAAAAA');
  assert.equal(gone.status, 404);
  assert.ok(gone.body.includes('Invitation expired'));
});

test('a position shared live reaches friends only, and does not last', async () => {
  const { call, signUp, befriend, data, object } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Estraneo');
  await befriend(a, b);
  const here = { lat: 45.9336, lon: 7.6295, alt: 2500, speed: 12.5, phase: 'run' };
  assert.equal((await call('PUT', '/v1/me/position', { body: here })).status, 401);
  assert.equal((await call('PUT', '/v1/me/position', { token: a.token, body: { lat: 'qui', lon: 7 } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/position', { token: a.token, body: { lat: 95, lon: 7 } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/position', { token: a.token, body: { ...here, phase: 'volo', speed: 900 } })).status, 200);
  let seen = (await call('GET', '/v1/friends/positions', { token: b.token })).body.friends;
  assert.equal(seen.length, 1);
  assert.equal(seen[0].name, 'Alessio');
  assert.equal(seen[0].lat, 45.9336);
  assert.equal(seen[0].phase, 'idle', 'an unknown phase is standing');
  assert.equal(seen[0].speed, 70);
  assert.deepEqual((await call('GET', '/v1/friends/positions', { token: c.token })).body.friends, [], 'not to strangers');
  assert.deepEqual((await call('GET', '/v1/friends/positions', { token: a.token })).body.friends, [], 'not yourself');
  assert.ok(!JSON.stringify([...data.entries()]).includes('45.9336'), 'never written to storage');

  // Sending yours answers with theirs.
  const mine = await call('PUT', '/v1/me/position', { token: b.token, body: { ...here, lat: 45.94 } });
  assert.deepEqual(mine.body.friends.map(f => f.name), ['Alessio']);
  assert.deepEqual((await call('PUT', '/v1/me/position', { token: c.token, body: here })).body.friends, []);
  await call('DELETE', '/v1/me/position', { token: b.token });
  await call('DELETE', '/v1/me/position', { token: c.token });

  // Ten minutes without news and it is gone.
  object.positions.get(a.id).at -= 11 * 60 * 1000;
  assert.deepEqual((await call('GET', '/v1/friends/positions', { token: b.token })).body.friends, []);
  assert.equal(object.positions.size, 0);

  // Stopped by hand, and gone with the friendship and with the account.
  await call('PUT', '/v1/me/position', { token: a.token, body: here });
  assert.equal((await call('DELETE', '/v1/me/position', { token: a.token })).status, 200);
  assert.deepEqual((await call('GET', '/v1/friends/positions', { token: b.token })).body.friends, []);
  await call('PUT', '/v1/me/position', { token: a.token, body: here });
  await call('DELETE', '/v1/friends/' + a.id, { token: b.token });
  assert.deepEqual((await call('GET', '/v1/friends/positions', { token: b.token })).body.friends, []);
  await call('DELETE', '/v1/me', { token: a.token, body: { password: 'neve-2026' } });
  assert.equal(object.positions.size, 0);
});

test('too many wrong passwords stop the guessing', async () => {
  const { call, signUp } = server();
  await signUp('Alessio');
  for (let i = 0; i < 10; i++) {
    assert.equal((await call('POST', '/v1/sessions', { body: { username: 'Alessio', password: 'prova-' + i } })).status, 403);
  }
  assert.equal((await call('POST', '/v1/sessions', { body: { username: 'Alessio', password: 'neve-2026' } })).status, 429);
});

test('a profile picture is seen by friends only', async () => {
  const { call, signUp, befriend, send, data } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Estraneo');
  await befriend(a, b);
  const jpeg = new Uint8Array(400).fill(7);
  jpeg.set([0xff, 0xd8, 0xff, 0xe0]);
  assert.equal((await send('PUT', '/v1/me/photo', { bytes: jpeg })).status, 401);
  assert.equal((await send('PUT', '/v1/me/photo', { token: a.token, bytes: new Uint8Array(400).fill(1) })).status, 400, 'not a JPEG');
  assert.equal((await send('PUT', '/v1/me/photo', { token: a.token, bytes: new Uint8Array(200 * 1024).fill(0xff) })).status, 413);
  const set = await send('PUT', '/v1/me/photo', { token: a.token, bytes: jpeg });
  assert.equal(set.status, 200);
  const version = (await set.json()).photo;
  assert.ok(version > 0);
  assert.equal((await call('GET', '/v1/me', { token: a.token })).body.photo, version);

  // The friend sees it, in the list, in the leaderboard and by its address; a stranger does not.
  const friends = (await call('GET', '/v1/friends', { token: b.token })).body.friends;
  assert.equal(friends[0].photo, version);
  assert.equal(friends[0].kind, undefined, 'how a friend signs in is their own business');
  const rows = (await call('GET', '/v1/board?season=2026', { token: b.token })).body.rows;
  assert.equal(rows.find(r => r.name === 'Alessio').photo, version);
  assert.equal(rows.find(r => r.name === 'Alex').photo, 0);
  const got = await send('GET', '/v1/photos/' + a.id, { token: b.token });
  assert.equal(got.status, 200);
  assert.equal(got.headers.get('Content-Type'), 'image/jpeg');
  assert.deepEqual(new Uint8Array(await got.arrayBuffer()), jpeg);
  assert.equal((await send('GET', '/v1/photos/' + a.id, { token: a.token })).status, 200, 'and you see your own');
  assert.equal((await send('GET', '/v1/photos/' + a.id, { token: c.token })).status, 404);
  assert.equal((await send('GET', '/v1/photos/' + b.id, { token: a.token })).status, 404, 'no picture set');

  // Taken off, and gone with the account.
  assert.equal((await call('DELETE', '/v1/me/photo', { token: a.token })).body.photo, 0);
  assert.equal((await send('GET', '/v1/photos/' + a.id, { token: b.token })).status, 404);
  await send('PUT', '/v1/me/photo', { token: a.token, bytes: jpeg });
  assert.ok(data.has('photo:' + a.id));
  await call('DELETE', '/v1/me', { token: a.token, body: { password: 'neve-2026' } });
  assert.ok(!data.has('photo:' + a.id));
});

test('signing in with Apple or Google makes one account for each person', async () => {
  const { call, object, data } = server();
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'k1' };
  const b64 = bytes => Buffer.from(bytes).toString('base64url');
  const token = async (claims, { kid = 'k1', key = pair.privateKey } = {}) => {
    const head = b64(JSON.stringify({ alg: 'RS256', kid })) + '.' + b64(JSON.stringify(claims));
    return head + '.' + b64(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(head))));
  };
  const soon = Math.floor(Date.now() / 1000) + 600;
  object.jwks.set('apple', { keys: [jwk], at: Date.now() });
  object.jwks.set('google', { keys: [jwk], at: Date.now() });
  const apple = { iss: 'https://appleid.apple.com', aud: 'win.shadowbyte.skiapex', sub: '001.abc', exp: soon };

  // Apple: made the first time with the name the phone gives, found again the second.
  const first = await call('POST', '/v1/sessions/apple', { body: { token: await token(apple), name: 'Alessio Vitàli' } });
  assert.equal(first.status, 201);
  assert.equal(first.body.account.name, 'Alessio.Vitali');
  assert.equal(first.body.account.kind, 'apple');
  const again = await call('POST', '/v1/sessions/apple', { body: { token: await token(apple) } });
  assert.equal(again.status, 200);
  assert.equal(again.body.account.id, first.body.account.id);
  assert.equal((await call('GET', '/v1/me', { token: again.body.token })).body.name, 'Alessio.Vitali');
  assert.ok(!JSON.stringify([...data.entries()]).includes('@'), 'no email anywhere');

  // Someone else with the same name gets a number; with no name at all, a plain one.
  const other = await call('POST', '/v1/sessions/apple', { body: { token: await token({ ...apple, sub: '001.def' }), name: 'Alessio Vitali' } });
  assert.equal(other.body.account.name, 'Alessio.Vitali2');
  const nameless = await call('POST', '/v1/sessions/apple', { body: { token: await token({ ...apple, sub: '001.ghi' }) } });
  assert.equal(nameless.body.account.name, 'sciatore');

  // What is not a good token gets nothing.
  const stranger = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  for (const bad of [
    await token(apple, { key: stranger.privateKey }),
    await token(apple, { kid: 'k9' }),
    await token({ ...apple, aud: 'com.someone.else' }),
    await token({ ...apple, iss: 'https://evil.example' }),
    await token({ ...apple, exp: soon - 3600 }),
    'not.a.token',
    42,
  ]) {
    assert.equal((await call('POST', '/v1/sessions/apple', { body: { token: bad } })).status, 403);
  }

  // Google: off until the worker is told which app it is for.
  const google = { iss: 'https://accounts.google.com', aud: '123.apps.googleusercontent.com', sub: '9988', exp: soon, given_name: 'Giulia' };
  assert.equal((await call('POST', '/v1/sessions/google', { body: { token: await token(google) } })).status, 503);
  object.env.GOOGLE_CLIENT_IDS = '999.apps.googleusercontent.com, 123.apps.googleusercontent.com';
  const g = await call('POST', '/v1/sessions/google', { body: { token: await token(google) } });
  assert.equal(g.status, 201);
  assert.equal(g.body.account.name, 'Giulia');
  assert.equal(g.body.account.kind, 'google');
  assert.equal((await call('POST', '/v1/sessions/google', { body: { token: await token(apple) } })).status, 403, 'an Apple token is not a Google one');

  // No password to sign in with, and the account goes with a plain yes.
  assert.equal((await call('POST', '/v1/sessions', { body: { username: 'Giulia', password: 'undefined' } })).status, 403);
  assert.equal((await call('DELETE', '/v1/me', { token: g.body.token, body: {} })).status, 403);
  assert.equal((await call('DELETE', '/v1/me', { token: g.body.token, body: { confirm: true } })).status, 200);
  assert.ok(!data.has('ext:google:9988'));
  assert.equal((await call('POST', '/v1/sessions/google', { body: { token: await token(google) } })).status, 201, 'a new account, from nothing');
});

test('how the snow was is told to everyone, who was there to friends only', async () => {
  const { call, signUp, befriend, data } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Estraneo');
  await befriend(a, b);
  const today = new Date().toISOString().slice(0, 10);
  const yesterday = new Date(Date.now() - 24 * 3600 * 1000).toISOString().slice(0, 10);
  const long = new Date(Date.now() - 20 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  const here = { lat: 45.93361, lon: 7.62954 };
  const stats = { vertical: 4000, distance: 20000, runTime: 4000, liftTime: 3000, avgSpeed: 9, runs: 10 };

  assert.equal((await call('PUT', '/v1/places/visits', { body: { ...here, date: today } })).status, 401);
  assert.equal((await call('PUT', '/v1/places/visits', { token: a.token, body: { ...here, date: 'oggi' } })).status, 400);
  assert.equal((await call('PUT', '/v1/places/visits', { token: a.token, body: { ...here, date: today, snow: 'marmo' } })).status, 400);
  assert.equal((await call('PUT', '/v1/places/visits', { token: a.token, body: { lat: 95, lon: 7, date: today } })).status, 400);

  // Alessio today: powder, his numbers, and friends may see he was there. Told twice: once.
  for (let i = 0; i < 2; i++) {
    assert.equal((await call('PUT', '/v1/places/visits', { token: a.token, body: { ...here, date: today, snow: 'powder', friends: true, stats } })).status, 201);
  }
  // The stranger, a kilometer away: yesterday icy, today powder, with other numbers, not for friends.
  const near = { lat: 45.94, lon: 7.64 };
  await call('PUT', '/v1/places/visits', { token: c.token, body: { ...near, date: yesterday, snow: 'icy' } });
  await call('PUT', '/v1/places/visits', { token: c.token, body: { ...near, date: today, snow: 'powder', stats: { ...stats, vertical: 2000, runs: 6 } } });
  // Long ago, and far away: neither counts for the snow of here and now.
  await call('PUT', '/v1/places/visits', { token: c.token, body: { ...near, date: long, snow: 'wet' } });
  await call('PUT', '/v1/places/visits', { token: c.token, body: { lat: 46.5, lon: 10.1, date: today, snow: 'crust' } });

  const seen = (await call('GET', `/v1/places?lat=${here.lat}&lon=${here.lon}`, { token: b.token })).body;
  assert.deepEqual(seen.snow, [{ kind: 'powder', count: 2 }, { kind: 'icy', count: 1 }]);
  assert.deepEqual(seen.latest, { kind: 'powder', date: today });
  assert.equal(seen.reports, 3);
  assert.equal(seen.averages.days, 2);
  assert.equal(seen.averages.vertical, 3000);
  assert.equal(seen.averages.runs, 8);
  assert.deepEqual(seen.friends.map(f => [f.name, f.days, f.last]), [['Alessio', 1, today]], 'the friend who said so, not the stranger');
  assert.equal(seen.mine, 0);
  assert.equal((await call('GET', `/v1/places?lat=${here.lat}&lon=${here.lon}`, { token: a.token })).body.mine, 1);
  // To the stranger: the snow and the averages, no names.
  const stranger = (await call('GET', `/v1/places?lat=${here.lat}&lon=${here.lon}`, { token: c.token })).body;
  assert.equal(stranger.reports, 3);
  assert.deepEqual(stranger.friends, []);
  // Elsewhere, only what was told there.
  const far = (await call('GET', '/v1/places?lat=46.5&lon=10.1', { token: b.token })).body;
  assert.deepEqual(far.snow, [{ kind: 'crust', count: 1 }]);
  assert.equal(far.averages, null);
  assert.equal((await call('GET', '/v1/places?lat=x&lon=7', { token: b.token })).status, 400);
  // Kept to the kilometer, not to the meter.
  assert.ok(!JSON.stringify([...data.entries()]).includes('45.93361'));

  // A day taken back, and everything gone with the account.
  assert.equal((await call('DELETE', '/v1/places/visits', { token: c.token, body: { date: yesterday } })).status, 200);
  assert.deepEqual((await call('GET', `/v1/places?lat=${here.lat}&lon=${here.lon}`, { token: b.token })).body.snow, [{ kind: 'powder', count: 2 }]);
  await call('DELETE', '/v1/me', { token: a.token, body: { password: 'neve-2026' } });
  const after = (await call('GET', `/v1/places?lat=${here.lat}&lon=${here.lon}`, { token: b.token })).body;
  assert.deepEqual(after.snow, [{ kind: 'powder', count: 1 }]);
  assert.deepEqual(after.friends, []);
  assert.ok(!JSON.stringify([...data.entries()]).includes(a.id));
});

test('the best time on a piste is seen by friends only, piste by piste', async () => {
  const { call, signUp, befriend, data } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Estraneo');
  await befriend(a, b);
  const here = { lat: 45.93361, lon: 7.62954 };
  const piste = (name, best, more = {}) => ({ name, ...here, best, speed: 19, runs: 3, date: '2026-11-20', ...more });

  assert.equal((await call('PUT', '/v1/me/pistes', { body: { pistes: [] } })).status, 401);
  assert.equal((await call('PUT', '/v1/me/pistes', { token: a.token, body: { pistes: 'tutte' } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/pistes', { token: a.token, body: { pistes: [{ ...piste('Ventina', 300), name: '' }] } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/pistes', { token: a.token, body: { pistes: [piste('Ventina', 300, { lat: 95 })] } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/pistes', { token: a.token, body: { pistes: [piste('Ventina', 300, { date: 'ieri' })] } })).status, 400);

  // Sent twice: the second time replaces the first.
  await call('PUT', '/v1/me/pistes', { token: a.token, body: { pistes: [piste('Ventina', 400)] } });
  assert.equal((await call('PUT', '/v1/me/pistes', { token: a.token, body: { pistes: [piste('Ventina', 312.4), piste('Gran Bosco', 95)] } })).body.pistes, 2);
  // The friend a kilometer away on the same piste, faster; the stranger too; a Ventina of somewhere else.
  await call('PUT', '/v1/me/pistes', { token: b.token, body: { pistes: [piste('Ventina', 290, { lat: 45.94, lon: 7.64, runs: 1 }), piste('Ventina', 100, { lat: 46.5, lon: 10.1 })] } });
  await call('PUT', '/v1/me/pistes', { token: c.token, body: { pistes: [piste('Ventina', 200)] } });

  const board = (await call('GET', `/v1/pistes?name=Ventina&lat=${here.lat}&lon=${here.lon}`, { token: a.token })).body.rows;
  assert.deepEqual(board.map(r => [r.name, r.me, r.best, r.runs]), [['Alex', false, 290, 1], ['Alessio', true, 312.4, 3]], 'the fastest first, no stranger');
  assert.deepEqual((await call('GET', `/v1/pistes?name=Gran%20Bosco&lat=${here.lat}&lon=${here.lon}`, { token: b.token })).body.rows.map(r => r.name), ['Alessio']);
  assert.deepEqual((await call('GET', `/v1/pistes?name=Ventina&lat=${here.lat}&lon=${here.lon}`, { token: c.token })).body.rows.map(r => r.name), ['Estraneo']);
  assert.deepEqual((await call('GET', '/v1/pistes?name=Ventina&lat=46.5&lon=10.1', { token: a.token })).body.rows.map(r => r.best), [100]);
  assert.equal((await call('GET', '/v1/pistes?lat=45.9&lon=7.6', { token: a.token })).status, 400);
  assert.equal((await call('GET', '/v1/pistes?name=Ventina&lat=x&lon=7.6', { token: a.token })).status, 400);
  // Kept to the kilometer, not to the meter.
  assert.ok(!JSON.stringify([...data.entries()]).includes('45.93361'));

  // Taken back, and gone with the account.
  assert.equal((await call('DELETE', '/v1/me/pistes', { token: b.token })).status, 200);
  assert.deepEqual((await call('GET', `/v1/pistes?name=Ventina&lat=${here.lat}&lon=${here.lon}`, { token: a.token })).body.rows.map(r => r.name), ['Alessio']);
  await call('DELETE', '/v1/me', { token: a.token, body: { password: 'neve-2026' } });
  assert.ok(!data.has('pistes:' + a.id));
});

test('a meeting point reaches friends only, and is over after its time', async () => {
  const { call, signUp, befriend, data } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Estraneo');
  await befriend(a, b);
  const hut = { lat: 45.9412, lon: 7.6388, label: 'Rifugio Teodulo' };

  assert.equal((await call('PUT', '/v1/me/meeting', { body: hut })).status, 401);
  assert.equal((await call('PUT', '/v1/me/meeting', { token: a.token, body: { lat: 'qui', lon: 7 } })).status, 400);
  const when = Date.now() + 2 * 3600 * 1000;
  const set = await call('PUT', '/v1/me/meeting', { token: a.token, body: { ...hut, when } });
  assert.equal(set.status, 201);
  assert.deepEqual(set.body.meetings.map(m => [m.name, m.mine, m.label, m.when]), [['Alessio', true, 'Rifugio Teodulo', when]]);

  // The friend sees it, with the positions too; the stranger does not.
  const seen = (await call('GET', '/v1/meetings', { token: b.token })).body.meetings;
  assert.deepEqual(seen.map(m => [m.name, m.mine, m.lat, m.lon]), [['Alessio', false, 45.9412, 7.6388]]);
  assert.equal((await call('GET', '/v1/friends/positions', { token: b.token })).body.meetings.length, 1);
  assert.equal((await call('PUT', '/v1/me/position', { token: b.token, body: { lat: 45.93, lon: 7.63 } })).body.meetings.length, 1);
  assert.deepEqual((await call('GET', '/v1/meetings', { token: c.token })).body.meetings, []);

  // One for each account: a new one replaces it. A time long gone, or too far ahead, is no time.
  await call('PUT', '/v1/me/meeting', { token: a.token, body: { ...hut, label: 'x'.repeat(200), when: Date.now() + 9 * 24 * 3600 * 1000 } });
  const again = (await call('GET', '/v1/meetings', { token: b.token })).body.meetings;
  assert.equal(again.length, 1);
  assert.equal(again[0].label.length, 80);
  assert.equal(again[0].when, null);

  // Over: forgotten the next time someone looks.
  const kept = data.get('meet:' + a.id);
  data.set('meet:' + a.id, { ...kept, until: Date.now() - 1000 });
  assert.deepEqual((await call('GET', '/v1/meetings', { token: b.token })).body.meetings, []);
  assert.ok(!data.has('meet:' + a.id));

  // Taken back by hand, and gone with the account.
  await call('PUT', '/v1/me/meeting', { token: a.token, body: hut });
  assert.deepEqual((await call('DELETE', '/v1/me/meeting', { token: a.token })).body.meetings, []);
  await call('PUT', '/v1/me/meeting', { token: a.token, body: hut });
  await call('DELETE', '/v1/me', { token: a.token, body: { password: 'neve-2026' } });
  assert.ok(!data.has('meet:' + a.id));
  assert.deepEqual((await call('GET', '/v1/meetings', { token: b.token })).body.meetings, []);
});

test('a meeting point is accepted or refused, and only who set it sees who said what', async () => {
  const { call, signUp, befriend, data } = server();
  const a = await signUp('Alessio');
  const b = await signUp('Alex');
  const c = await signUp('Carla');
  const d = await signUp('Estraneo');
  await befriend(a, b);
  await befriend(a, c);
  const hut = { lat: 45.9412, lon: 7.6388, label: 'Rifugio Teodulo' };
  await call('PUT', '/v1/me/meeting', { token: a.token, body: hut });
  const mine = async () => (await call('GET', '/v1/meetings', { token: a.token })).body.meetings[0];
  const theirs = async who => (await call('GET', '/v1/meetings', { token: who.token })).body.meetings[0];

  // Nobody answered yet: whose it is sees every friend waiting, a friend sees no answer of their own.
  assert.deepEqual((await mine()).answers.map(x => [x.name, x.answer]), [['Alex', null], ['Carla', null]]);
  assert.equal((await theirs(b)).answer, null);
  assert.equal((await theirs(b)).answers, undefined, 'a friend does not see what the others said');

  assert.equal((await call('PUT', `/v1/meetings/${a.id}/answer`, { body: { coming: true } })).status, 401);
  assert.equal((await call('PUT', `/v1/meetings/${a.id}/answer`, { token: b.token, body: { coming: 'forse' } })).status, 400);
  assert.equal((await call('PUT', `/v1/meetings/${a.id}/answer`, { token: d.token, body: { coming: true } })).status, 404, 'not a friend');
  assert.equal((await call('PUT', `/v1/meetings/${b.id}/answer`, { token: a.token, body: { coming: true } })).status, 404, 'no place set');
  assert.equal((await call('PUT', `/v1/meetings/${a.id}/answer`, { token: a.token, body: { coming: true } })).status, 404, 'not to your own');

  // Carla is not coming, Alex is: the answer comes back with the meetings, and whose it is sees both.
  const no = await call('PUT', `/v1/meetings/${a.id}/answer`, { token: c.token, body: { coming: false } });
  assert.equal(no.status, 200);
  assert.equal(no.body.meetings[0].answer, 'no');
  await call('PUT', `/v1/meetings/${a.id}/answer`, { token: b.token, body: { coming: true } });
  assert.equal((await theirs(b)).answer, 'yes');
  assert.deepEqual((await mine()).answers.map(x => [x.name, x.answer]), [['Alex', 'yes'], ['Carla', 'no']]);
  // A change of mind.
  await call('PUT', `/v1/meetings/${a.id}/answer`, { token: c.token, body: { coming: true } });
  assert.deepEqual((await mine()).answers.map(x => [x.name, x.answer]), [['Alex', 'yes'], ['Carla', 'yes']]);

  // No longer a friend: no longer in the list. A new place is a new question for everyone.
  await call('DELETE', '/v1/friends/' + c.id, { token: a.token });
  assert.deepEqual((await mine()).answers.map(x => x.name), ['Alex']);
  await call('PUT', '/v1/me/meeting', { token: a.token, body: { ...hut, label: 'Baita del Sole' } });
  assert.deepEqual((await mine()).answers.map(x => [x.name, x.answer]), [['Alex', null]]);
  assert.equal((await theirs(b)).answer, null);

  // Over: nothing left to answer.
  data.set('meet:' + a.id, { ...data.get('meet:' + a.id), until: Date.now() - 1000 });
  assert.equal((await call('PUT', `/v1/meetings/${a.id}/answer`, { token: b.token, body: { coming: true } })).status, 404);
});
