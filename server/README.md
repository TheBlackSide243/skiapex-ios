# Ski Apex server

Accounts, friends and the leaderboards among friends, for the **Amici** tab of the app. A Cloudflare
Worker with one Durable Object (SQLite-backed: it runs on the free plan).

## What it keeps

- For each account: a name, a password hash (PBKDF2-SHA256 with a random salt), the hashes of the
  tokens of the phones signed in, the list of friends, an invitation code.
- For each season an account shares: the **totals** only — days on the snow, vertical, runs,
  distance, time, top speed.

It never receives the tracks or the places of the days. A position shared live (off unless turned on in
the app, sent only while a day is recorded) is held **in memory only**: the last one, never written to
storage, forgotten ten minutes after its last update or as soon as the app takes it back. Deleting the
account from the app deletes all of it.

## API

All under `/v1`, JSON in and out. Signed-in calls carry `Authorization: Bearer <token>`.

| Call | What it does |
|---|---|
| `POST /v1/accounts` `{username, password}` | new account → `{token, account}` |
| `POST /v1/sessions` `{username, password}` | sign in → `{token, account}` |
| `DELETE /v1/sessions` | sign this phone out |
| `GET /v1/me` · `DELETE /v1/me` `{password}` | the account · delete it and what it shared |
| `POST /v1/me/invite` `{renew?}` | the code of the invitation link, good for a week |
| `GET /v1/invites/<code>` | who an invitation is from (no sign-in) |
| `GET /v1/friends` · `POST /v1/friends` `{code}` · `DELETE /v1/friends/<id>` | friends: list, accept an invitation, remove |
| `PUT /v1/me/seasons/<year>` `{days: [{date, vertical, runs, distance, time, maxSpeed}]}` | the days of a season as the phone has them now; they replace what was there |
| `GET /v1/board?season=<year>` | one row for you and each friend |
| `PUT /v1/me/position` `{lat, lon, alt, speed, phase}` · `DELETE /v1/me/position` | where you are now, for your friends · take it back |
| `GET /v1/friends/positions` | the friends sharing right now, with their last position |
| `POST /v1/sessions/apple` · `POST /v1/sessions/google` `{token, name?}` | in with the token Apple or Google gave the phone; the account is made the first time |
| `PUT /v1/me/photo` (a JPEG up to 100 KB) · `DELETE /v1/me/photo` | your profile picture · take it off |
| `GET /v1/photos/<id>` | the picture of an account: yours or a friend's |

`/f/<code>` is the page of an invitation link: it opens the app with `skiapex://friend/<code>`.

## Run the tests

```
npm test
```

Node 20 or later, no dependencies: the Durable Object is replaced by an in-memory stand-in.

## Deploy

```
npx wrangler deploy
```

from this folder, signed in to Cloudflare (`npx wrangler login`), or with Workers Builds connected
to the repository with `server` as the root directory. The app looks for the server at
`https://skiapex.tbsgaming.win`; start it with `-server <url>` to use another one.

## Signing in with Apple and Google

Nothing to set for Apple: the tokens accepted are the ones made for the two apps
(`win.shadowbyte.skiapex`, `com.local.skiapex`); the variable `APPLE_AUDIENCES` (a list with
commas) replaces them. Google is off until the worker knows the app's OAuth client ID:

```
npx wrangler deploy --var GOOGLE_CLIENT_IDS:<id>.apps.googleusercontent.com
```

(or `[vars]` in `wrangler.toml`). The same ID goes in the app, in the build setting
`GOOGLE_CLIENT_ID` of `project.yml`: it is public, not a secret. Only an identifier and a name
are kept of who signs in this way: no email.
