# http-session-demo

A small login/session page:

- `POST /api/login` stores the user in `req.session` and rotates the SID;
- `GET /api/me` reads the session;
- `GET /api/count` increments a value stored server-side;
- `POST /api/logout` sets `req.session = nil`, destroying the session and cookie.

```text
package.fun             # manifest
src/main.fun            # API + static page on :8080
web/index.html          # same-origin page
```

## Run

`fun` below is the command-line binary (`fun.exe` on Windows). From the
repository root, after building, the in-tree binary is
`src/prj/fun/funcmd`; from this directory that is
`../../../src/prj/fun/funcmd`.

```text
cd fun/demos/http-session-demo
fun run
# or: ../../../src/prj/fun/funcmd run
```

Open <http://127.0.0.1:8080/>. Login, then click `GET /api/me` and
`GET /api/count`; the browser sends the `sid` cookie automatically.

## Curl

Use a cookie jar:

```text
curl -i -c /tmp/fun-sid.txt -b /tmp/fun-sid.txt \
  -X POST http://127.0.0.1:8080/api/login \
  -H 'Content-Type: application/json' \
  -d '{"user":"alice"}'
```

The response sets `sid=...; Path=/; HttpOnly; SameSite=Lax`. Then:

```text
curl -i -c /tmp/fun-sid.txt -b /tmp/fun-sid.txt http://127.0.0.1:8080/api/me
curl -i -c /tmp/fun-sid.txt -b /tmp/fun-sid.txt http://127.0.0.1:8080/api/count
curl -i -c /tmp/fun-sid.txt -b /tmp/fun-sid.txt -X POST http://127.0.0.1:8080/api/logout
```

After logout the cookie is cleared and `/api/me` returns `{"user":null}`.

## Notes

- Only a random SID is stored in the cookie; session data is in the server.
- `SessionRegenerate(req)` after login prevents session fixation; the old SID
  is destroyed.
- Session data must be JSON-serializable (it is compared before/after the
  handler to decide whether to save).
- The default cookie is `HttpOnly`, `SameSite=Lax`, `Path=/`; set `secure: true`
  behind HTTPS.
- SameSite helps with CSRF but is not a complete CSRF defense. State-changing
  routes should still use a CSRF token.
- The in-memory store is per process. For multiple instances, pass a shared
  `store` implementing `get(sid)`, `set(sid, data, ttl)`, `destroy(sid)`.
- For a cross-site SPA, CORS must allow credentials with an exact origin, the
  cookie needs `secure: true` and `sameSite: 'None'`, and browser third-party
  cookie restrictions may still block it; a same-site/BFF deployment is safer.
