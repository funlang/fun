use 'test.fun';
use '../../lib/uuid.fun';

fun isHexChar(c)
  result = '0123456789abcdef'.subpos(c) >= 0;
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
