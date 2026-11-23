# Ski Apex server

Accounts, friends and the leaderboards among friends, for the **Amici** tab of the app. A Cloudflare
Worker with one Durable Object (SQLite-backed: it runs on the free plan).

## What it keeps

- For each account: a name, a password hash (PBKDF2-SHA256 with a random salt), the hashes of the
  tokens of the phones signed in, the list of friends, an invitation code.
- For each season an account shares: the **totals** only — days on the snow, vertical, runs,
  distance, time, top speed.

It never receives tracks, places or positions. Deleting the account from the app deletes all of it.

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
