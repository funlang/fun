// lib-os-lnx: the common lib-os surface on Linux.
// Host-dependent (absolute paths, /proc, exit codes), snap-friendly.
use 'fun/lib/lib-os-lnx.fun';

?. GetCurrPath().substr(0, 1) = '/';
?. GetTempPath('').substr(-1) = '/';
?. GetFullPath('a/../b') = GetCurrPath() & '/b';
?. GetCodePage() = 65001;
?. OSVersion().length() > 0;

?. execWait('sh', '-c "exit 7"', '', 0, false, 0, nil) = 7;
?. tryExecWait('sh', '-c "exit 3"', '', 0, false, 0, nil) = 3;

?. GetPId() > 0;
var procName = GetProcName(GetPId(), nil);
?. procName.substr(-6) = 'funcmd' or procName.substr(-3) = 'fun';

?. tryFind('funcmd', 'src/prj/fun').length() > 0;
?. tryFind('base', 'src/prj/fun') = 'base';

var d = GetTempPath('sd-' & GetPId() & '.tmp');
d.save('x');
?. d.size() > 0;
SafeDelete(d);
?. d.size() = 0;

try GetWinPath(); ?. 'not raised'; except ?. 'raised'; end try;
