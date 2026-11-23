use 'fun/lib/lib-host.fun';

########################################
# Linux FFI: C-library names without a matching shared object
########################################
# musl ships no libc.so.6 (only libc.musl-<cpu>.so.1), and a runtime package
# usually ships only the versioned soname (libm.so.6, not libm.so). getapi()
# therefore resolves a known C-library alias from the process image and tries
# versioned sonames for a bare name.
#
# The first probe uses a deliberately unresolvable alias (the musl soname on a
# glibc host) so it fails the same way it does on Alpine; the last one checks
# that an unknown library still raises instead of silently using a libc symbol.
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-libc-fallback.fun
########################################

var slen = 'libc.musl-x86_64.so.1'.getapi('strlen', 's:i');
?. slen('hello');              ?. ' <- libc alias fallback expect 5';

var slen2 = 'libc.musl-aarch64.so.1'.getapi('strlen', 's:i');
?. slen2('abcd');              ?. ' <- alias on another cpu name expect 4';

var sqrt = 'libm'.getapi('sqrt', 'd:d');
?. sqrt(9.0);                  ?. ' <- bare libm -> libm.so.6 expect 3';

# An unversioned soname is normalized before suffix probing, so 'libc.so'
# resolves even where only libc.so.6 (or no libc.so at all on musl) exists.
var slen3 = 'libc.so'.getapi('strlen', 's:i');
?. slen3('abc');               ?. ' <- libc.so normalization expect 3';

# A name that merely starts with a C-library stem must not be routed to the
# process image by IsGlobalLibName. musl's own loader treats any 'libc.*'
# name as libc before Fun sees the failure, so on musl this probe resolves by
# design; the platform snapshots record which answer the host gives. On
# glibc it must raise.
var prefix_aliased = false;
try
  'libc.something'.getapi('strlen', 's:i');
  prefix_aliased = true;
except
end try;
if prefix_aliased then
  ?. 'libc.* aliased by loader';
else
  ?. 'raised libc.something';
end if;

try
  'libdefinitely_missing.so.9'.getapi('strlen', 's:i');
  ?. 'unexpected';
except
  ?. 'raised';
end try;
