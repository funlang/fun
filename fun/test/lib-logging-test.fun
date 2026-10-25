// logging: core, config, formatting, filters and extension contracts.
// All loggers use memory/capture handlers so the snapshot has no stderr noise.
use 'fun/lib/logging.fun';
use 'fun/lib/lib-host.fun';

class CaptureSink()
  var lines = new [];
  fun write(line) lines.@add(line); end fun;
  fun flush() end fun;
  fun close() end fun;
end class;

class CustomHandler()
  var seen = 0;
  fun enabled(level) result = true; end fun;
  fun handle(rec) seen += 1; end fun;
end class;

fun onlyInfo(rec)
  result = rec.level = 30;
end fun;

fun briefFmt(rec)
  result = rec.levelName & ':' & rec.message;
end fun;

fun onlyError(rec)
  result = rec.level >= 50;
end fun;

// --- levels and named logger identity -------------------------------------
?. logging.TRACE = 10;
?. logging.INFO = 30;
?. logging.WARNING = 40;
?. logging.ERROR = 50;
?. logging.CRITICAL = 60;

var same1 = logging.getLogger('unit.same');
var same2 = logging.getLogger('unit.same');
?. same1 = same2;
?. not (same1 = logging.getLogger('unit.other'));

// --- independent logger, levels and aliases -------------------------------
var m = logging.MemoryHandler();
var l = logging.newLogger([handlers: [m], level: 'info', name: 'unit']);

l.info('hello', [a: 1]);
?. m.records.@count() = 1;
?. m.records[0].message = 'hello';
?. m.records[0].levelName = 'INFO';
?. m.records[0].name = 'unit';
?. m.records[0].fields['a'] = 1;
?. m.records[0].source = nil;

l.debug('filtered');
?. m.records.@count() = 1;
l.warning('w1');
l.warn('w2');
l.error('e1');
l.critical('c1');
l.fatal('f1');
?. m.records.@count() = 6;
?. m.records[1].levelName = 'WARNING';
?. m.records[2].levelName = 'WARNING';
?. m.records[4].levelName = 'CRITICAL';
?. m.records[5].levelName = 'CRITICAL';

?. l.enabled('debug') = false;
?. l.enabled('info') = true;
?. l.enabled(50) = true;
?. l.enabled('off') = false;

// --- child fields and groups ----------------------------------------------
var c = l.with([rid: 'r1', a: 9]);
c.info('child', [a: 8, b: 2]);
?. m.records[6].fields['rid'] = 'r1';
?. m.records[6].fields['a'] = 8;
?. m.records[6].fields['b'] = 2;

var g = l.withGroup('http');
g.info('group', [method: 'GET', status: 200]);
?. m.records[7].fields['http.method'] = 'GET';
?. m.records[7].fields['http.status'] = 200;

var gg = g.withGroup('req');
gg.info('nested', [id: 7]);
?. m.records[8].fields['http.req.id'] = 7;

// --- handler level and filters --------------------------------------------
var cap = CaptureSink();
var h = logging.StreamHandler([
  sink: cap,
  level: 'error',
  formatter: logging.TextFormatter([show: ['message']])
]);
var hl = logging.newLogger([handlers: [h], level: 'debug']);
hl.warning('no');
hl.error('yes');
?. cap.lines.@count() = 1;
?. cap.lines[0] = 'yes';

var mf = logging.MemoryHandler([filters: [onlyInfo]]);
var fl = logging.newLogger([handlers: [mf], level: 'debug']);
fl.debug('no');
fl.info('yes');
?. mf.records.@count() = 1;
?. mf.records[0].message = 'yes';

// --- multi handler and custom handler -------------------------------------
var m1 = logging.MemoryHandler();
var m2 = logging.MemoryHandler();
var ml = logging.newLogger([handlers: [logging.MultiHandler([m1, m2])], level: 'info']);
ml.info('multi');
?. m1.records.@count() = 1;
?. m2.records.@count() = 1;

var ch = CustomHandler();
var cl = logging.newLogger([handlers: [ch], level: 'info']);
cl.info('custom');
?. ch.seen = 1;

var capFmt = CaptureSink();
var hFmt = logging.StreamHandler([sink: capFmt]);
var lfmt = logging.newLogger([
  handlers: [hFmt],
  formatter: logging.JsonFormatter([show: ['message']]),
  level: 'info'
]);
lfmt.info('json');
?. capFmt.lines[0] = '{"message":"json"}';

var fcap = CaptureSink();
var fh2 = logging.StreamHandler([sink: fcap, formatter: briefFmt]);
var fl2 = logging.newLogger([handlers: [fh2], level: 'info']);
fl2.info('fn');
?. fcap.lines[0] = 'INFO:fn';

var gmf = logging.MemoryHandler();
logging.config([handlers: [gmf], level: 'info', filters: [onlyError]]);
var gfl = logging.getLogger('unit.filtered');
gfl.info('no');
gfl.error('yes');
?. gmf.records.@count() = 1;
?. gmf.records[0].message = 'yes';

var imf = logging.MemoryHandler();
var ifl = logging.newLogger([handlers: [imf], level: 'info', filters: [onlyError]]);
ifl.info('no');
ifl.error('yes');
?. imf.records.@count() = 1;

// --- file handlers ---------------------------------------------------------
var fp = HostTempPath('fun-logging-test.log');
if fp.size() then fp.move(); end if;
var fh = logging.FileHandler([
  path: fp,
  formatter: logging.TextFormatter([show: ['message']])
]);
var flog = logging.newLogger([handlers: [fh], level: 'info']);
flog.info('file-line');
var ftxt = fp.load();
?. ftxt.subpos('file-line') >= 0;
if fp.size() then fp.move(); end if;

var rp = HostTempPath('fun-logging-rotate.log');
if rp.size() then rp.move(); end if;
if (rp & '.1').size() then (rp & '.1').move(); end if;
if (rp & '.2').size() then (rp & '.2').move(); end if;
var rh = logging.RotatingFileHandler([
  path: rp,
  maxSize: 10,
  backups: 2,
  formatter: logging.TextFormatter([show: ['message']])
]);
var rlog = logging.newLogger([handlers: [rh], level: 'info']);
rlog.info('111111');
rlog.info('222222');
?. rp.load().subpos('222222') >= 0;
?. (rp & '.1').load().subpos('111111') >= 0;
if rp.size() then rp.move(); end if;
if (rp & '.1').size() then (rp & '.1').move(); end if;
if (rp & '.2').size() then (rp & '.2').move(); end if;

// --- text / JSON formatters ------------------------------------------------
var rec = new [];
rec['time'] = nil;
rec['level'] = 30;
rec['levelName'] = 'INFO';
rec['name'] = 'fmt';
rec['message'] = 'hello';
var flds = new [];
flds['b'] = 'two words';
flds['a'] = 1;
rec['fields'] = flds;
rec['source'] = nil;

var tf = logging.TextFormatter([show: ['level', 'name', 'message', 'fields']]);
?. tf.format(rec) = 'INFO fmt hello a=1 b="two words"';

var sf = logging.TextFormatter([show: ['message', 'source']]);
?. sf.format(rec) = 'hello';

rec['message'] = 'a' & 10.toChar() & 'b';
?. tf.format(rec) = 'INFO fmt a' & 92.toChar() & 'nb a=1 b="two words"';
rec['message'] = 'hello';

var jf = logging.JsonFormatter([show: ['level', 'name', 'message', 'fields']]);
var js = jf.format(rec);
var jo = js.getJson(json: true);
?. jo['level'] = 'INFO';
?. jo['name'] = 'fmt';
?. jo['message'] = 'hello';
?. jo['a'] = 1;
?. jo['b'] = 'two words';

// --- global config, handler replacement and reset -------------------------
logging.config([level: 'debug']);
?. logging.getLogger('unit.partial').enabled('debug') = true;

var lm = logging.MemoryHandler();
logging.config([handlers: [lm], level: 'warning', levels: ['unit.debug': 'debug']]);
var dl = logging.getLogger('unit.debug');
var ol = logging.getLogger('unit.other');
dl.debug('named-yes');
ol.debug('named-no');
?. lm.records.@count() = 1;
?. lm.records[0].message = 'named-yes';

var gm = logging.MemoryHandler();
var root = logging.config([handlers: [gm], level: 'warning']);
?. root = logging.getLogger();
?. root = logging.getLogger('');
var gl = logging.getLogger('unit.global');
gl.info('filtered');
gl.warn('yes');
?. gm.records.@count() = 1;
?. gm.records[0].message = 'yes';

var gm2 = logging.MemoryHandler();
logging.config([handlers: [gm2], level: 'error']);
gl.info('filtered');
gl.error('error');
?. gm.records.@count() = 1;
?. gm2.records.@count() = 1;
?. gm2.records[0].message = 'error';

var im = logging.MemoryHandler();
var il = logging.newLogger([handlers: [im], level: 'debug', name: 'independent']);
il.debug('independent');
gl.info('filtered');
?. im.records.@count() = 1;
?. gm2.records.@count() = 1;

logging.reset();
?. logging.getLogger('after.reset').enabled('debug') = false;
