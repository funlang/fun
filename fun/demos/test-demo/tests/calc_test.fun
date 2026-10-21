use 'test.fun';
use 'helpers.fun';
use '../src/lib.fun';

test('adds', {
  assert.equal(add(1, 2), 3);
});

test('adds with a shared helper', {
  assert_sum(2, 3, 5);
});

test('divides', {
  assert.equal(safe_div(6, 3), 2);
});

test('rejects division by zero', {
  assert.raises({ safe_div(1, 0); }, 'division by zero');
});
