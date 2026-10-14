// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

var HKEY_CLASSES_ROOT   = 0x80000000;
var HKEY_CURRENT_USER   = 0x80000001;
var HKEY_LOCAL_MACHINE  = 0x80000002;
var HKEY_USERS          = 0x80000003;
var HKEY_CURRENT_CONFIG = 0x80000005;

var HKCR = HKEY_CLASSES_ROOT;
var HKCU = HKEY_CURRENT_USER;
var HKLM = HKEY_LOCAL_MACHINE;
var HKUS = HKEY_USERS;
var HKCC = HKEY_CURRENT_CONFIG;

var REG_SZ    = 1;
var REG_DWORD = 4;

var MAX_KEY_LENGTH   = 514;
var MAX_VALUE_LENGTH = 32768;

var advapi = 'advapi32.dll';
var RegOpenKey     = advapi.getapi('RegOpenKey',      'isp:i');
var RegCreateKey   = advapi.getapi('RegCreateKey',    'isp:i');
var RegDeleteKey   = advapi.getapi('RegDeleteKey',    'is:i');
var RegFlushKey    = advapi.getapi('RegFlushKey',     'i:i');
var RegCloseKey    = advapi.getapi('RegCloseKey',     'i:i');
var RegSetValue    = advapi.getapi('RegSetValueEx',   'isiisi:i');
var RegDeleteValue = advapi.getapi('RegDeleteValue',  'is:i');
var RegQueryValue  = advapi.getapi('RegQueryValueEx', 'isippp:i');
var RegEnumKey     = advapi.getapi('RegEnumKey',      'iipi:i');
var RegEnumValue   = advapi.getapi('RegEnumValue',    'iippippp:i');
//var RegQueryKey    = advapi.getapi('RegQueryInfoKey', 'ippppppppppp:i');

class Registry()
  var handle = 0;

  // ========================================================================
  fun OpenKey(hkey, keyName)
    return 0 = RegOpenKey(hkey, keyName, var handle);
  end fun;

  fun CreateKey(hkey, keyName)
    return 0 = RegCreateKey(hkey, keyName, var handle);
  end fun;

  fun DeleteKey(hkey, keyName)
    return 0 = RegDeleteKey(hkey, keyName);
  end fun;

  fun FlushKey()
    return 0 = RegFlushKey(handle);
  end fun;

  fun CloseKey()
    return 0 = RegCloseKey(handle);
  end fun;

  fun SetValue(name, value, type)
    value &= '';
    return 0 = RegSetValue(handle, name, 0, type or REG_SZ, value, value.length());
  end fun;

  fun SetIntValue(name, value)
    return 0 = RegSetValue(handle, name, 0, REG_DWORD, int2str(value), 4);
    fun int2str(int)
      result = '';
      for i = 0 to 3*8 step 8 do
        var b = int >> i;
        result &= b.toChar();
      end do;
    end fun;
  end fun;

  fun DeleteValue(name)
    return 0 = RegDeleteValue(handle, name);
  end fun;

  fun GetValue(name)
    var len = 0;
    RegQueryValue(handle, name, 0, 0, 0, var len); //?. len;
    result = ' '.x(len) & 0.toChar();
    RegQueryValue(handle, name, 0, 0, var result, var len); //?. '[$@] $len'.eval();
    result = result.substr(0, len);
    result = result.replace(/[\s\x0-\x20]++$/, '');
  end fun;

  fun GetSubKeys()
    result = nil;
    var i = 0;
    loop
      var name = ' '.x(MAX_KEY_LENGTH + 1);
      var ret = RegEnumKey(handle, i, var name, MAX_KEY_LENGTH);
      exit when ret <> 0;
      result &= name.replace(/\s++$/, '') & '\r\n'.escape();
      i += 1;
    end loop;
  end fun;

  fun GetValues()
    result = nil;
    var i = 0;
    loop
      var len = 0;
      RegEnumValue(handle, i, 0, 0, 0, 0, 0, var len);
      var name  = ' '.x(MAX_KEY_LENGTH + 1);
      var value = ' '.x(len + 1);
      var ret = RegEnumValue(handle, i, var name, MAX_KEY_LENGTH, 0, 0, var value, var len);
      exit when ret <> 0;
      result &= name.replace(/\s++$/, '') & ':' & value.replace(/\s++$/, '') & '\r\n'.escape();
      i += 1;
    end loop;
  end fun;
end class;
