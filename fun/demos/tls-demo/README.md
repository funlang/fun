# tls-demo

Fetches `https://example.com/` with the `tls` standard library module:
default certificate verification (system CA store), SNI, and the
`io.Reader`/`io.Writer` stream contract.

```sh
fun src/main.fun
```

TLS comes from the host system — libssl on Linux/macOS, SChannel on Windows.
fun ships no crypto library of its own.
