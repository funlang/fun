// jsonschema: FD/JSON schemas, every v0 keyword, error paths and options.
// The snapshot contains booleans only, so it is host-neutral.
use 'fun/lib/jsonschema.fun';

var S = 'fun/test/jsonschema-user.fd'.load();

fun ok(data, schema)
  result = JsonSchema.valid(data, schema or S);
end fun;

fun bad(data, schema)
  result = not JsonSchema.valid(data, schema or S);
end fun;

fun kw(data, schema)
  var r = JsonSchema.check(data, schema or S);
  if r.ok then result = ''; else result = r.first.keyword; end if;
end fun;

fun at(data, schema)
  var r = JsonSchema.check(data, schema or S);
  if r.ok then result = ''; else result = r.first.path; end if;
end fun;

var good = '{"id":5,"tags":["a"],"name":"abc","score":3,"role":"user","kind":"fixed","maybe":null,"meta":{"x":"y"}}'.getJson(json: true);

// --- the happy path and the FD/JSON inputs --------------------------------
?. ok(good);
?. JsonSchema.valid(good, '{"type":"object","required":["id"]}');
?. JsonSchema.valid(good, 'type object' & 10.toChar() & 'required' & 10.toChar() & '  - id');
?. JsonSchema.parse('{"type":"object"}').type = 'object';

// --- required / properties / additionalProperties -------------------------
?. kw('{"id":5}'.getJson(json: true)) = 'required';
?. kw('{"id":5,"tags":["a"],"x":1}'.getJson(json: true)) = 'additionalProperties';
?. at('{"id":5,"tags":["a"],"x":1}'.getJson(json: true)) = '/x';
?. bad('{"id":5,"tags":["a"],"meta":{"x":1}}'.getJson(json: true));
?. at('{"id":5,"tags":["a"],"meta":{"x":1}}'.getJson(json: true)) = '/meta/x';

// --- integer / number -----------------------------------------------------
?. ok('{"id":5.0,"tags":["a"]}'.getJson(json: true));
?. kw('{"id":5.5,"tags":["a"]}'.getJson(json: true)) = 'type';
?. kw('{"id":0,"tags":["a"]}'.getJson(json: true)) = 'minimum';
?. kw('{"id":101,"tags":["a"]}'.getJson(json: true)) = 'maximum';
?. kw('{"id":1,"tags":["a"],"score":0}'.getJson(json: true)) = 'exclusiveMinimum';
?. kw('{"id":1,"tags":["a"],"score":10}'.getJson(json: true)) = 'exclusiveMaximum';

// --- string bounds, pattern and UTF-8 code points -------------------------
?. kw('{"id":1,"tags":["a"],"name":"a"}'.getJson(json: true)) = 'minLength';
?. kw('{"id":1,"tags":["a"],"name":"abcdef"}'.getJson(json: true)) = 'maxLength';
?. kw('{"id":1,"tags":["a"],"name":"Ab"}'.getJson(json: true)) = 'pattern';
?. JsonSchema.valid('中文', '{"type":"string","minLength":2,"maxLength":2}');
?. JsonSchema.valid('中文', '{"type":"string","minLength":3}') = false;
?. JsonSchema.valid('😀', '{"minLength":1,"maxLength":1}');

// --- array bounds and items ----------------------------------------------
?. kw('{"id":1,"tags":[]}'.getJson(json: true)) = 'minItems';
?. kw('{"id":1,"tags":["a","b","c"]}'.getJson(json: true)) = 'maxItems';
?. kw('{"id":1,"tags":[1]}'.getJson(json: true)) = 'type';
?. at('{"id":1,"tags":[1]}'.getJson(json: true)) = '/tags/0';

// --- enum / const, including deep equality --------------------------------
?. kw('{"id":1,"tags":["a"],"role":"root"}'.getJson(json: true)) = 'enum';
?. kw('{"id":1,"tags":["a"],"kind":"other"}'.getJson(json: true)) = 'const';
?. JsonSchema.valid('[1,2]'.getJson(json: true), '{"enum":[[1,2]]}');
?. JsonSchema.valid('{"a":1}'.getJson(json: true), '{"enum":[{"a":1}]}');
?. JsonSchema.valid('{"a":2}'.getJson(json: true), '{"enum":[{"a":1}]}') = false;
?. JsonSchema.valid(1.0, '{"enum":[1]}');
?. JsonSchema.valid(true, '{"enum":[1]}') = false;

// --- type lists, null and JSON Pointer escaping ---------------------------
?. JsonSchema.valid(nil, '{"type":["string","null"]}');
?. JsonSchema.valid(1, '{"type":["string","null"]}') = false;
?. JsonSchema.valid('[]'.getJson(json: true), '{"type":"array"}');
?. JsonSchema.valid('{}'.getJson(json: true), '{"type":"object"}');
?. at('[1]'.getJson(json: true)) = '';
?. kw('[1]'.getJson(json: true)) = 'type';
?. kw(nil) = 'type';
?. JsonSchema.check('{"a/b":1,"c~d":"x"}'.getJson(json: true),
  '{"type":"object","properties":{"a/b":{"type":"integer"},"c~d":{"type":"integer"}},"additionalProperties":false}').first.path = '/c~0d';

// --- options and assert ---------------------------------------------------
?. JsonSchema.valid(1, '{"type":"number","unknownKw":1}', [strict: true]) = false;
?. JsonSchema.valid(1, '{"type":"number","unknownKw":1}');
?. JsonSchema.check('{"a":1,"b":2,"c":3}'.getJson(json: true),
  '{"properties":{},"additionalProperties":false}', [maxErrors: 2]).errors.@count() = 2;

var raised = false;
try
  JsonSchema.assert('{"id":1}'.getJson(json: true), S);
except
  raised = true;
end try;
?. raised;
?. JsonSchema.assert(good, S);
