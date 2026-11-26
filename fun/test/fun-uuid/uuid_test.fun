use 'test.fun';
use '../../lib/uuid.fun';

fun isHexChar(c)
  result = '0123456789abcdef'.subpos(c) >= 0;
end fun;

// The 48-bit timestamp encoded in the first 12 hex characters of a UUID.
fun tsOf(u)
  var p = u.substr(0, 8) & u.substr(9, 4);
  result = 0;
  var hex = '0123456789abcdef';
  for i = 0 to p.length() - 1 do
    result = result * 16 + hex.subpos(p.substr(i, 1));
  end do;
end fun;

test('format', {
  var u = UUID();
  assert.equal(u.length(), 36, 'length');
  var i = 0;
  while i < 36 do
    var c = u.substr(i, 1);
    if i = 8 or i = 13 or i = 18 or i = 23 then
      assert.equal(c, '-', 'dash at ' & i);
    else
      assert.is_true(isHexChar(c), 'hex at ' & i);
    end if;
    i += 1;
  end do;
});

test('version and variant', {
  var u = UUID();
  assert.equal(u.substr(14, 1), '4');
  assert.is_true('89ab'.subpos(u.substr(19, 1)) >= 0);
  assert.equal(u, u.lower());
});

test('unique', {
  var seen = new [];
  var i = 0;
  while i < 1000 do
    seen[UUID()] = true;
    i += 1;
  end do;
  assert.equal(seen.@count(), 1000);
});

test('v7 format', {
  var u = UUID7();
  assert.equal(u.length(), 36, 'length');
  assert.equal(u.substr(14, 1), '7', 'version');
  assert.is_true('89ab'.subpos(u.substr(19, 1)) >= 0, 'variant');
  assert.equal(u, u.lower(), 'lowercase');
  var i = 0;
  while i < 36 do
    var c = u.substr(i, 1);
    if i = 8 or i = 13 or i = 18 or i = 23 then
      assert.equal(c, '-', 'dash at ' & i);
    else
      assert.is_true(isHexChar(c), 'hex at ' & i);
    end if;
    i += 1;
  end do;
});

test('v7 pinned timestamp', {
  var ms = 1700000000123;
  var u = UUID7(ms);
  assert.equal(tsOf(u), ms, 'timestamp matches the argument');
  // the timestamp lives in the leading 48 bits and leaves the rest random.
  assert.not_equal(u, UUID7(ms), 'random part differs between calls');
});

test('v7 clock', {
  var before = HostUnixMs();
  var u = UUID7();
  var after = HostUnixMs();
  var ts = tsOf(u);
  // the clock is read inside the call, so the stamp sits between the two
  // samples (allowing one millisecond for the reads to land either side).
  assert.is_true(ts >= before - 1 and ts <= after + 1,
                 'timestamp ' & ts & ' is between ' & before & ' and ' & after);
});

test('v7 unique in the same millisecond', {
  var seen = new [];
  var i = 0;
  var ts = HostUnixMs();
  while i < 1000 do
    seen[UUID7(ts)] = true;
    i += 1;
  end do;
  assert.equal(seen.@count(), 1000);
});

test('v7 bounds', {
  assert.equal(tsOf(UUID7(0)), 0);
  var max = 281474976710655;
  assert.equal(tsOf(UUID7(max)), max);
});

test('v7 bad args', {
  assert.raises({ UUID7(-1); }, 'must be an integer', 'negative');
  assert.raises({ UUID7(281474976710656); }, 'must be an integer', 'overflow');
  assert.raises({ UUID7('1700000000123'); }, 'must be an integer', 'string');
  assert.raises({ UUID7(1.5); }, 'must be an integer', 'float');
});