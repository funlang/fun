// lib-param on Linux: the module used to fail at load (it needed lib-os, which
// cannot even be loaded here). Now it uses lib-host, so it loads and produces
// host-appropriate values.
use 'fun/lib/lib-param.fun';

?. CmdLineParams.@exe.substr(0, 1) = '/';
?. CmdLineParams.@path.match(%/$%) != nil;
?. CmdLineParams.@fun = 1.arg();
?. CmdLineParams.@exe.subpos('funcmd') >= 0 or CmdLineParams.@exe.subpos('/fun') >= 0;
?. CmdLineParams.@path.length() > 1;
