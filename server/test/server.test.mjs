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
  return { call, signUp, befriend, data: state.storage.data, object };
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
