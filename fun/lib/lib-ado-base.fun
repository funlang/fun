// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ado-base: the platform-neutral ADO constants shared by the Windows
// backend (lib-ado.fun, ADODB.Connection) and the Unix backend
// (lib-ado-unx.fun, SQLite), plus the schema layer (lib-ado-schema.fun and
// lib-ado-schema-unx.fun).
//
// OpenSchema values come from ADO's SchemaEnum; the ad* values come from
// DataTypeEnum. They are part of the ADO API contract, so both backends and
// both schema files must use the same numbers.

// ConnectionModeEnum
var adModeRead          = 1;
var adModeShareDenyNone = 16;

// SchemaEnum
var adSchemaCatalogs         = 1;  // database
var adSchemaSchemata         = 17; // schema
var adSchemaTables           = 20; // table
var adSchemaColumns          = 4;  // columns
var adSchemaPrimaryKeys      = 28; // primary keys
var adSchemaForeignKeys      = 27; // foreign keys
var adSchemaProviderTypes    = 22; // provider types
var adSchemaDBInfoLiterals   = 31; // special symbols

// DataTypeEnum
var adEmpty = 0x0;
var adTinyInt = 0x10;
var adSmallInt = 0x2;
var adInteger = 0x3;
var adBigInt = 0x14;
var adUnsignedTinyInt = 0x11;
var adUnsignedSmallInt = 0x12;
var adUnsignedInt = 0x13;
var adUnsignedBigInt = 0x15;
var adSingle = 0x4;
var adDouble = 0x5;
var adCurrency = 0x6;
var adDecimal = 0xE;
var adNumeric = 0x83;
var adBoolean = 0xB;
var adError = 0xA;
var adUserDefined = 0x84;
var adVariant = 0xC;
var adIDispatch = 0x9;
var adIUnknown = 0xD;
var adGUID = 0x48;
var adDate = 0x7;
var adDBDate = 0x85;
var adDBTime = 0x86;
var adDBTimeStamp = 0x87;
var adBSTR = 0x8;
var adChar = 0x81;
var adVarChar = 0xC8;
var adLongVarChar = 0xC9;
var adWChar = 0x82;
var adVarWChar = 0xCA;
var adLongVarWChar = 0xCB;
var adBinary = 0x80;
var adVarBinary = 0xCC;
var adLongVarBinary = 0xCD;
var adChapter = 0x88;
var adFileTime = 0x40;
var adDBFileTime = 0x89;
var adPropVariant = 0x8A;
var adVarNumeric = 0x8B;
