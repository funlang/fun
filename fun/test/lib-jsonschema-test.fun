// jsonschema: FD/JSON schemas, every v0.x keyword, error paths and options.
// The snapshot contains booleans only, so it is host-neutral.
use 'fun/lib/jsonschema.fun';

var S = 'fun/test/jsonschema-user.fd'.load();

fun ok(data, schema, opts)
  result = JsonSchema.valid(data, schema or S, opts);
end fun;

fun bad(data, schema, opts)
  result = not JsonSchema.valid(data, schema or S, opts);
end fun;

fun kw(data, schema, opts)
  var r = JsonSchema.check(data, schema or S, opts);
  if r.ok then result = ''; else result = r.first.keyword; end if;
end fun;

fun at(data, schema, opts)
  var r = JsonSchema.check(data, schema or S, opts);
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

// --- text entry points: scalar roots keep their JSON type ---------------
?. JsonSchema.checkJson('{"id":1}', '{"type":"object","required":["id"]}').ok;
?. JsonSchema.checkJson('1', '{"type":"integer"}').ok;
?. JsonSchema.checkJson('null', '{"type":"null"}').ok;
?. JsonSchema.checkJson('[1,2]', '{"type":"array"}').ok;
?. JsonSchema.checkJson('"x"', '{"type":"string"}').ok;
?. JsonSchema.checkJson('true', '{"type":"boolean"}').ok;
?. JsonSchema.checkJson('bad', '{"type":"object"}').ok = false;
?. JsonSchema.checkJson('bad', '{"type":"object"}').first.keyword = 'parse';
?. JsonSchema.checkJson('1 x', '{"type":"number"}').ok = false;
?. JsonSchema.checkFd('id 1' & 10.toChar() & 'name ab',
                      '{"type":"object","required":["id"]}').ok;
?. JsonSchema.checkFd('', '{"type":"object"}').ok = false;
?. JsonSchema.validJson('1', '{"type":"integer"}');
?. JsonSchema.validFd('id 1', '{"type":"object"}');
?. JsonSchema.validFd('id 1', '{"type":"object","required":["name"]}') = false;

// --- schema text is parsed strictly ------------------------------------
var parseRaised = false;
try
  JsonSchema.parse('{bad');
except
  parseRaised = true;
end try;
?. parseRaised;
parseRaised = false;
try
  JsonSchema.parse('');
except
  parseRaised = true;
end try;
?. parseRaised;

// --- $ref / $defs, including escaped pointers and recursion -------------
var refS = '{"$defs":{"pos":{"type":"integer","minimum":1}},"type":"object","properties":{"id":{"$ref":"#/$defs/pos"}},"required":["id"]}';
?. ok('{"id":2}'.getJson(json: true), refS);
?. kw('{"id":0}'.getJson(json: true), refS) = 'minimum';
?. kw('{}'.getJson(json: true), '{"$ref":"#/$defs/missing","$defs":{}}') = '$ref';
?. kw(1, '{"$ref":"other.json#/x"}') = '$ref';
?. kw(1, '{"$ref":7}') = '$ref';

var escS = '{"$defs":{"a/b":{"type":"string"},"c~d":{"type":"integer"}},"properties":{"x":{"$ref":"#/$defs/a~1b"},"y":{"$ref":"#/$defs/c~0d"}}}';
?. ok('{"x":"s","y":2}'.getJson(json: true), escS);
?. kw('{"x":1,"y":"s"}'.getJson(json: true), escS) = 'type';

var recS = '{"$defs":{"node":{"type":"object","properties":{"next":{"$ref":"#/$defs/node"},"v":{"type":"integer"}},"required":["v"]}},"$ref":"#/$defs/node"}';
?. ok('{"v":1,"next":{"v":2,"next":{"v":3}}}'.getJson(json: true), recS);
?. kw('{"v":1,"next":{"v":"x"}}'.getJson(json: true), recS) = 'type';
?. JsonSchema.valid(1, '{"$ref":"#"}');

// --- allOf / anyOf / oneOf / not ---------------------------------------
?. ok(3, '{"allOf":[{"type":"integer"},{"minimum":2}]}');
?. kw(1, '{"allOf":[{"type":"integer"},{"minimum":2}]}') = 'minimum';
?. ok(3, '{"anyOf":[{"type":"string"},{"type":"integer"}]}');
?. kw(true, '{"anyOf":[{"type":"string"},{"type":"integer"}]}') = 'anyOf';
?. ok(3, '{"oneOf":[{"type":"integer"},{"type":"string"}]}');
?. kw(3, '{"oneOf":[{"type":"number"},{"type":"integer"}]}') = 'oneOf';
?. kw(3, '{"oneOf":[{"type":"string"},{"type":"boolean"}]}') = 'oneOf';
?. ok(3, '{"not":{"type":"string"}}');
?. kw('x', '{"not":{"type":"string"}}') = 'not';

// --- uniqueItems uses JSON equality (1 = 1.0) --------------------------
?. ok('[1,2,3]'.getJson(json: true), '{"uniqueItems":true}');
?. kw('[1,1.0]'.getJson(json: true), '{"uniqueItems":true}') = 'uniqueItems';
?. kw('[{"a":1},{"a":1}]'.getJson(json: true), '{"uniqueItems":true}') = 'uniqueItems';
?. kw('[{"a":1},{"a":2}]'.getJson(json: true), '{"uniqueItems":true}') = '';

// --- tuple items and additionalItems -----------------------------------
?. ok('[1,"a"]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}]}');
?. kw('[1,2]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}]}') = 'type';
?. ok('[1,"a",true]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}]}');
?. kw('[1,"a",true]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}],"additionalItems":false}') = 'additionalItems';
?. at('[1,"a",true]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}],"additionalItems":false}') = '/2';
?. ok('[1,"a",true]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}],"additionalItems":{"type":"boolean"}}');
?. kw('[1,"a",1]'.getJson(json: true), '{"items":[{"type":"integer"},{"type":"string"}],"additionalItems":{"type":"boolean"}}') = 'type';

// --- patternProperties / propertyNames / additionalProperties ---------
var patS = '{"type":"object","patternProperties":{"^s_":{"type":"string"},"^n_":{"type":"number"}},"additionalProperties":false}';
?. ok('{"s_a":"x","n_b":2}'.getJson(json: true), patS);
?. kw('{"s_a":1}'.getJson(json: true), patS) = 'type';
?. kw('{"other":1}'.getJson(json: true), patS) = 'additionalProperties';
?. ok('{"s_a":"x"}'.getJson(json: true), '{"type":"object","propertyNames":{"pattern":"^[a-z_]+$"}}');
?. kw('{"Bad":1}'.getJson(json: true), '{"type":"object","propertyNames":{"pattern":"^[a-z_]+$"}}') = 'propertyNames';
?. ok('{"s_a":"x"}'.getJson(json: true), '{"properties":{"s_a":{"type":"string"}},"patternProperties":{"^s_":{"minLength":1}},"additionalProperties":false}');

// --- format whitelist ---------------------------------------------------
?. ok('a@b.com', '{"format":"email"}');
?. kw('a b', '{"format":"email"}') = 'format';
?. ok('2024-02-29', '{"format":"date"}');
?. kw('2023-02-29', '{"format":"date"}') = 'format';
?. ok('2024-02-29T12:30:00Z', '{"format":"date-time"}');
?. kw('2024-02-29T25:30:00Z', '{"format":"date-time"}') = 'format';
?. ok('12:30:00+08:00', '{"format":"time"}');
?. ok('https://funlang.org/x', '{"format":"uri"}');
?. kw('not a uri', '{"format":"uri"}') = 'format';
?. ok('550e8400-e29b-41d4-a716-446655440000', '{"format":"uuid"}');
?. ok('127.0.0.1', '{"format":"ipv4"}');
?. kw('256.0.0.1', '{"format":"ipv4"}') = 'format';
?. ok('example.com', '{"format":"hostname"}');
?. ok('^a+$', '{"format":"regex"}');
?. kw('(', '{"format":"regex"}') = 'format';
?. ok('anything', '{"format":"made-up"}');

// --- strict mode knows the new keywords ---------------------------------
?. ok(1, '{"type":"integer","$defs":{"x":{"type":"string"}},"allOf":[{"minimum":0}]}', [strict: true]);
?. kw(1, '{"type":"integer","unknownKw":1}', [strict: true]) = 'schema';
