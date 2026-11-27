#!/bin/sh
# Live SMTP test for fun/lib/smtp: starts the python3 loopback fixture (the
# committed test PKI in fun/test/tls covers the STARTTLS/implicit-TLS ports),
# runs fun/test/lib-smtp-test.fun against it, tears the fixture down.
#
# Needs python3 (the fixture) and the interpreter built at src/prj/fun/funcmd.
# If python3 is missing this exits 2 so the regression runner reports a clear
# FAIL rather than a confusing diff.
cd "$(dirname "$0")/../.." || exit 2
MARKER=fun/test/.smtp-ready
OUTDIR=fun/test/.smtp-out
FUNCMD="${FUNCMD:-src/prj/fun/funcmd}"
[ -x "$FUNCMD" ] || FUNCMD="fun/fun"

if ! command -v python3 >/dev/null 2>&1; then
    echo "run-smtp.sh: python3 not found (needed for the SMTP fixture)" >&2
    exit 2
fi
if [ ! -x "$FUNCMD" ]; then
    echo "run-smtp.sh: $FUNCMD not built" >&2
    exit 2
fi

rm -rf "$MARKER" "$OUTDIR"
python3 fun/test/smtp-fixture.py "$MARKER" "$OUTDIR" >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT INT TERM

i=0
while [ $i -lt 20 ] && [ ! -f "$MARKER" ]; do
    sleep 0.5
    i=$((i + 1))
done
if [ ! -f "$MARKER" ]; then
    echo "run-smtp.sh: fixture did not become ready" >&2
    exit 2
fi

SSL_CERT_FILE="$PWD/fun/test/tls/ca.pem" "$FUNCMD" fun/test/lib-smtp-test.fun
rc=$?
rm -rf "$MARKER" "$OUTDIR"
exit $rc
