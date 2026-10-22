# http-bearer-demo

A small API and page showing Bearer token authentication:

- `GET /api/public` is open;
- `GET /api/me` requires `Authorization: Bearer demo-token`;
- missing credentials get a `Bearer realm="demo"` challenge;
- an invalid token adds `error="invalid_token"`;
- the token is never stored in `req.auth`.

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
cd fun/demos/http-bearer-demo
fun run
# or: ../../../src/prj/fun/funcmd run
```

Open <http://127.0.0.1:8080/>. The page calls the API with the token in the
input (default `demo-token`).

## Curl

Missing credentials:

```text
curl -i http://127.0.0.1:8080/api/me
```

Expected: `401` with `WWW-Authenticate: Bearer realm="demo"`.

Invalid token:

```text
curl -i http://127.0.0.1:8080/api/me \
  -H 'Authorization: Bearer wrong-token'
```

Expected: `401` with `Bearer realm="demo", error="invalid_token"`.

Malformed header:

```text
curl -i http://127.0.0.1:8080/api/me \
  -H 'Authorization: Bearer'
```

Expected: `401` with `Bearer realm="demo", error="invalid_request"`.

Valid token:

```text
curl -i http://127.0.0.1:8080/api/me \
  -H 'Authorization: Bearer demo-token'
```

Expected: `200` and `{"sub":"demo-user","scheme":"bearer"}`.

## Notes

- Only the `Authorization` header is read; query/form tokens are not accepted.
- The verifier is application code. Real applications should validate an
  opaque token against a store, or verify a JWT signature and claims.
- Bearer tokens are secrets: use HTTPS and do not log `req.credentials`.
- `demo-token` is fixed for demonstration only; never use it in production.
- Basic and Bearer are separate scheme middlewares; pick one per route/group.
