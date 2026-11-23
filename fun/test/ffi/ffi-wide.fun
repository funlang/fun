use 'fun/lib/lib-host.fun';

########################################
# Unix FFI (Linux / macOS): wide strings ('w')
########################################
# Fun strings are UTF-8; at the FFI boundary 'w' is converted to a real
# wchar_t* buffer (UCS-4, 4 bytes per character, on both Linux and macOS) and
# a 'w' return is converted back to UTF-8. Before this, 'w' passed a char* that
# a wide C API would read as wchar_t, which is undefined behaviour.
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-wide.fun
########################################

var wcslen = LibC().getapi('wcslen', 'w:i');
?. wcslen('hello');           ?. ' <- wcslen("hello") expect 5';
?. wcslen('中文');             ?. ' <- wcslen("中文") expect 2';

var wcscmp = LibC().getapi('wcscmp', 'ww:i');
?. wcscmp('abc', 'abc');      ?. ' <- wcscmp equal expect 0';
?. wcscmp('abc', 'abd') < 0;  ?. ' <- wcscmp abc<abd expect true';
?. wcscmp('abd', 'abc') > 0;  ?. ' <- wcscmp abd>abc expect true';

var wcschr = LibC().getapi('wcschr', 'wi:w');
?. wcschr('hello', 108);      ?. ' <- wcschr("hello", l) expect llo';
?. wcschr('hello', 122) = nil; ?. ' <- wcschr("hello", z) expect true';
