# http-cors-demo

A small API and browser page showing the CORS middleware:

- preflight `OPTIONS` is answered before routing and authentication;
- `credentials: true` requires an exact origin and sends
  `Access-Control-Allow-Credentials: true`;
- `X-Request-Id` is exposed so browser JavaScript can read it;
- `Vary: Origin` keeps shared caches correct.

```text
package.fun             # manifest
src/main.fun            # API on :8080
web/index.html          # page served from :5173
```

## Run

`fun` below is the command-line binary (`fun.exe` on Windows). From the
repository root, after building, the in-tree binary is
`src/prj/fun/funcmd`; from this directory that is
`../../../src/prj/fun/funcmd`.

```text
cd fun/demos/http-cors-demo

# terminal 1: API on http://127.0.0.1:8080
fun run
# or: ../../../src/prj/fun/funcmd run

# terminal 2: page on http://127.0.0.1:5173
python3 -m http.server 5173 --bind 127.0.0.1 --directory web
```

Open <http://127.0.0.1:5173> and click the buttons.

The allowed origin is exactly `http://127.0.0.1:5173`; opening the page from
another origin is rejected by the browser (preflight returns 403, actual
requests have no `Access-Control-Allow-Origin`).

## Curl

The browser sends the preflight automatically. To see it directly:

```text
curl -i -X OPTIONS http://127.0.0.1:8080/api/public \
  -H 'Origin: http://127.0.0.1:5173' \
  -H 'Access-Control-Request-Method: GET'
```

Expected: `204` with `Access-Control-Allow-Origin`,
`Access-Control-Allow-Methods`, `Access-Control-Allow-Credentials`,
`Access-Control-Max-Age`, and `Vary`.

A simple request:

```text
curl -i http://127.0.0.1:8080/api/public \
  -H 'Origin: http://127.0.0.1:5173'
```

Expected: `200` with `Access-Control-Allow-Origin`,
`Access-Control-Allow-Credentials`, `Access-Control-Expose-Headers`, and
`Vary: Origin`.

A JSON POST triggers a preflight for `Content-Type`:

```text
curl -i -X OPTIONS http://127.0.0.1:8080/api/echo \
  -H 'Origin: http://127.0.0.1:5173' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type'
```

## Notes

- CORS is a browser read policy, not authentication or CSRF protection. The
  demo endpoints are public.
- `origins: ['*']` is the default for quick public APIs. It cannot be combined
  with `credentials: true`; credentialed APIs must list exact origins.
- Register CORS before authentication middleware. Preflight requests do not
  carry credentials and must not be rejected by auth.
- `headers` omitted means "reflect the requested headers"; list them explicitly
  when you want a fixed allowlist.
- In production, set explicit origins, use HTTPS, and keep `Vary: Origin`
  intact through proxies/CDNs.
