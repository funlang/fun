#!/bin/sh
# Live TLS test for fun/lib/tls: starts the python3 loopback fixture (the
# committed test PKI in fun/test/tls), runs fun/test/lib-tls-test.fun against
# it, tears the fixture down.
#
# Needs python3 (the fixture) and the interpreter built at src/prj/fun/funcmd.
# If python3 is missing this exits 2 so the regression runner reports a clear
# FAIL rather than a confusing diff.
cd "$(dirname "$0")/../.." || exit 2
MARKER=fun/test/.tls-ready
FUNCMD="${FUNCMD:-src/prj/fun/funcmd}"
[ -x "$FUNCMD" ] || FUNCMD="fun/fun"

if ! command -v python3 >/dev/null 2>&1; then
    echo "run-tls.sh: python3 not found (needed for the TLS fixture)" >&2
    exit 2
fi
if [ ! -x "$FUNCMD" ]; then
    echo "run-tls.sh: $FUNCMD not built" >&2
    exit 2
fi

rm -f "$MARKER"
python3 fun/test/tls-fixture.py "$MARKER" >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT INT TERM

i=0
while [ $i -lt 20 ] && [ ! -f "$MARKER" ]; do
    sleep 0.5
    i=$((i + 1))
done
if [ ! -f "$MARKER" ]; then
    echo "run-tls.sh: fixture did not become ready" >&2
    exit 2
fi

SSL_CERT_FILE="$PWD/fun/test/tls/ca.pem" "$FUNCMD" fun/test/lib-tls-test.fun
rc=$?
rm -f "$MARKER"
exit $rc
