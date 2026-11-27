# smtp-demo

Builds a MIME message with the `smtp` standard library module and either
sends it through an SMTP server or prints it offline:

```sh
fun src/main.fun                 # offline: prints the message
SMTP_HOST=smtp.example.com SMTP_USER=me@example.com \
SMTP_PASS=secret SMTP_TO=you@example.com fun src/main.fun
```

Port defaults to 587 (STARTTLS when the server advertises it); set
`SMTP_PORT=465` for implicit TLS. Account fields are read from the
environment so no credentials land in the demo source.
