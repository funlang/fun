// Copyright (c) 2010-2026 Zhang WeiDong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Portable MD5/SHA1 for builds that cannot use advapi32.dll (Linux).
//
// It lives in its own unit on purpose: the core declares functions named MD5
// and SHA (see io.pas), and FPC identifiers are case-insensitive, so a `uses
// md5` next to them would be a duplicate identifier. This unit has no such
// symbol, so it can use FPC's bundled md5/sha1 units safely.
//
// FPC's MD5Buffer/SHA1Buffer take their buffer by `var`, so the const buffer
// from the caller is copied into a local array first.
//
// Windows is unaffected: it keeps the advapi32 implementation in libmd5.inc,
// and this unit is only pulled in under {$IfDef MD5}{$IfDef UNIX}.

unit funhash;

interface

function FunMD5 (const Buffer; Size: LongWord): string;
function FunSHA1(const Buffer; Size: LongWord): string;

implementation

uses md5, sha1;

function FunMD5(const Buffer; Size: LongWord): string;
var
  tmp: array of Byte;
begin
  SetLength(tmp, Size + 1); // +1 keeps a valid address for an empty input
  if Size > 0 then Move(Buffer, tmp[0], Size);
  result := MD5Print(MD5Buffer(tmp[0], Size));
end;

function FunSHA1(const Buffer; Size: LongWord): string;
var
  tmp: array of Byte;
begin
  SetLength(tmp, Size + 1);
  if Size > 0 then Move(Buffer, tmp[0], Size);
  result := SHA1Print(SHA1Buffer(tmp[0], Size));
end;

end.
