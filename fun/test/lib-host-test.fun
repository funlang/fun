// lib-host: portable host services, Linux-verified behaviour.
// Only host-independent facts are asserted, so the snapshot is machine-neutral.
use 'fun/lib/lib-host.fun';

// IsLinux()/IsWindows() are host-specific; assert the invariant that exactly
// one supported host family matches, instead of printing the host's value.
?. IsUnix() or IsWindows();
?. IsWindows() <> IsUnix();
?. HostSep();
?. HostCurrPath().substr(0, 1) = '/';
?. HostCurrPath().length() > 1;
?. HostTempPath('').match(%/$%) != nil;
?. HostTempPath('x') = HostTempPath('').replace(%/$%, '') & '/x';

// lexical normalization: stable paths only
?. HostFullPath('/x/./y/../z');
?. HostFullPath('/');
?. HostFullPath('/a//b///c');
?. HostFullPath('rel/path') = HostCurrPath() & '/rel/path';

// --- command line: rebuilt from argv on Linux, Windows-style quoting ---
?. HostCommandLine().subpos('lib-host-test.fun') >= 0;
?. HostCommandLine().subpos(34.toChar()) < 0;   // no arg here needs quoting

// --- version probe: N.time() and 'host'.arg() read one compile-time constant ---
?. 2010.time() = 'host'.arg().getJson(fd:true).version;
?. 2010.time() >= 20250819;                  // threshold style used by lib-ajax
?. 2010.time() >= 20100000 and 2010.time() < 21000000;   // YYYYMMDD shape
