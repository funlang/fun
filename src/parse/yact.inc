//[act-
       procedure A1; begin
         yyaccept; 
       end;
       procedure A2; begin
         builder.BuildError(yyv[yysp-0]); yyabort; 
       end;
       procedure A3; begin
         builder.BuildIf(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A4; begin
         builder.BuildIf(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1], true); 
       end;
       procedure A5; begin
         builder.BuildElse(yyv[yysp-0]); 
       end;
       procedure A6; begin
         builder.BuildCase(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A7; begin
         builder.BuildWhen(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A8; begin
         builder.BuildLoop(yyv[yysp-0]); 
       end;
       procedure A9; begin
         builder.BuildLoop(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A10; begin
         builder.BuildForIn(yyv[yysp-4], yyv[yysp-0], yyv[yysp-3], yyv[yysp-1]); 
       end;
       procedure A11; begin
         builder.BuildForIn(yyv[yysp-6], yyv[yysp-0], yyv[yysp-3], yyv[yysp-1], yyv[yysp-5].text); 
       end;
       procedure A12; begin
         builder.BuildForIn(yyv[yysp-6], yyv[yysp-0], yyv[yysp-5], yyv[yysp-1], '', yyv[yysp-3].text); 
       end;
       procedure A13; begin
         builder.BuildForIn(yyv[yysp-8], yyv[yysp-0], yyv[yysp-5], yyv[yysp-1], yyv[yysp-7].text, yyv[yysp-3].text); 
       end;
       procedure A14; begin
         builder.BuildFor(yyv[yysp-6], yyv[yysp-0], yyv[yysp-5], yyv[yysp-3], yyv[yysp-1]); 
       end;
       procedure A15; begin
         builder.BuildFor(yyv[yysp-8], yyv[yysp-0], yyv[yysp-7], yyv[yysp-5], yyv[yysp-3], yyv[yysp-1].node); 
       end;
       procedure A16; begin
         builder.BuildTry(yyv[yysp-0]); 
       end;
       procedure A17; begin
         builder.BuildExcept(yyv[yysp-0]); 
       end;
       procedure A18; begin
         builder.BuildFinally(yyv[yysp-0]); 
       end;
       procedure A19; begin
         builder.BuildFun(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A20; begin
         builder.BuildClass(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A21; begin
         builder.BuildClass(yyv[yysp-4], yyv[yysp-0], yyv[yysp-3], yyv[yysp-0], yyv[yysp-1].node); 
       end;
       procedure A22; begin
         
       end;
       procedure A23; begin
         
       end;
       procedure A24; begin
         if builder.BuildEnd(yyv[yysp-0]).val = -1 then yy_done; 
       end;
       procedure A25; begin
         if builder.BuildEnd(yyv[yysp-0]).val = -1 then yy_done; 
       end;
       procedure A26; begin
         
       end;
       procedure A27; begin
         
       end;
       procedure A28; begin
         
       end;
       procedure A29; begin
         
       end;
       procedure A30; begin
         
       end;
       procedure A31; begin
         
       end;
       procedure A32; begin
         
       end;
       procedure A33; begin
         
       end;
       procedure A34; begin
         
       end;
       procedure A35; begin
         builder.BuildEnd(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A36; begin
         builder.BuildExit(yyv[yysp-0]); 
       end;
       procedure A37; begin
         builder.BuildExit(yyv[yysp-2], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A38; begin
         builder.BuildNext(yyv[yysp-0]); 
       end;
       procedure A39; begin
         builder.BuildNext(yyv[yysp-2], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A40; begin
         builder.BuildReturn(yyv[yysp-0]); 
       end;
       procedure A41; begin
         builder.BuildReturn(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A42; begin
         builder.BuildRaise(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A43; begin
         builder.BuildUse(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A44; begin
         builder.BuildUse(yyv[yysp-3], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0].text); 
       end;
       procedure A45; begin
         builder.BuildVar(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A46; begin
         builder.BuildVar(yyv[yysp-3], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0].node); 
       end;
       procedure A47; begin
         builder.BuildVar(yyv[yysp-3], yyv[yysp-0], yyv[yysp-2], builder.BuildFunDef(yyv[yysp-3], yyv[yysp-0], yyv[yysp-1].node, true, yyv[yysp-2].text).node, true); 
       end;
       procedure A48; begin
         builder.BuildReturn(yyval, yyval, yyval); builder.BuildEnd(yyval, true); 
       end;
       procedure A49; begin
         builder.BuildSet(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0]); 
       end;
       procedure A50; begin
         builder.BuildSet(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0], yyv[yysp-1].text); 
       end;
       procedure A51; begin
         builder.BuildCall(yyv[yysp-0]); 
       end;
       procedure A52; begin
         builder.BuildEcho(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A53; begin
         builder.BuildEcho(yyv[yysp-2], yyv[yysp-0], yyv[yysp-0], #13#10); 
       end;
       procedure A54; begin
         builder.BuildEcho(yyv[yysp-2], yyv[yysp-0], yyv[yysp-0], ' '); 
       end;
       procedure A55; begin
         builder.BuildEcho(yyv[yysp-2], yyv[yysp-0], yyv[yysp-0], #9); 
       end;
       procedure A56; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A57; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A58; begin
         yyval := builder.CreateExp(yyv[yysp-1], yyv[yysp-0], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A59; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A60; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A61; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A62; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A63; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A64; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0], true); 
       end;
       procedure A65; begin
         yyval := builder.CreateExp(yyv[yysp-1], yyv[yysp-0], yyv[yysp-1], yyv[yysp-0], true); 
       end;
       procedure A66; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A67; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A68; begin
         yyval := builder.BuildFunDef(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1].node); 
       end;
       procedure A69; begin
         yyval := builder.BuildFunDef(yyv[yysp-1], yyv[yysp-0], yyv[yysp-1].node); 
       end;
       procedure A70; begin
         yyval := builder.BuildFunDef(yyv[yysp-0], yyv[yysp-0], nil); 
       end;
       procedure A71; begin
         yyval := builder.BuildFunDef(yyv[yysp-1], yyv[yysp-0], yyv[yysp-1].node, true); yylast := yyval; 
       end;
       procedure A72; begin
         builder.BuildReturn(yyval, yyval, yyval); builder.BuildEnd(yyval, true); yyval := yylast; 
       end;
       procedure A73; begin
         yyval := builder.BuildFunDef(yyv[yysp-1], yyv[yysp-0], builder.CreateNames(yyv[yysp-1]).node, true); yylast := yyval; 
       end;
       procedure A74; begin
         builder.BuildReturn(yyval, yyval, yyval); builder.BuildEnd(yyval, true); yyval := yylast; 
       end;
       procedure A75; begin
         yyval := builder.BuildFunDef(yyv[yysp-0], yyv[yysp-0], nil, true); yylast := yyval; 
       end;
       procedure A76; begin
         builder.BuildReturn(yyval, yyval, yyval); builder.BuildEnd(yyval, true); yyval := yylast; 
       end;
       procedure A77; begin
         yyval := builder.CreateFunFun(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A78; begin
         yyval := builder.CreateSetNew(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A79; begin
         yyval := builder.CreateRef(yyv[yysp-1], yyv[yysp-0], yyv[yysp-0]); 
       end;
       procedure A80; begin
         yyval := builder.CreateDotAny(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-1], yyv[yysp-0]); 
       end;
       procedure A81; begin
         yyval := builder.CreateFunExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-0], builder.CreateValues(yyv[yysp-2])); 
       end;
       procedure A82; begin
         yyval := builder.CreateFunExp(yyv[yysp-2], yyv[yysp-0], builder.CreateFunFun(yyv[yysp-0], yyv[yysp-0], yyv[yysp-0]), builder.CreateValues(yyv[yysp-2])); 
       end;
       procedure A83; begin
         
       end;
       procedure A84; begin
         
       end;
       procedure A85; begin
         
       end;
       procedure A86; begin
         
       end;
       procedure A87; begin
         
       end;
       procedure A88; begin
         yyval := builder.CreateExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A89; begin
         
       end;
       procedure A90; begin
         
       end;
       procedure A91; begin
         yyval := builder.CreateId(yyv[yysp-0]); 
       end;
       procedure A92; begin
         yyval := builder.CreateId(yyv[yysp-1], true); 
       end;
       procedure A93; begin
         yyval := builder.CreateVarExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0]); 
       end;
       procedure A94; begin
         yyval := builder.CreateVarExp(yyv[yysp-3], yyv[yysp-0], yyv[yysp-3], yyv[yysp-1], false, true); 
       end;
       procedure A95; begin
         yyval := builder.CreateVarExp(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0], true); 
       end;
       procedure A96; begin
         yyval := builder.CreateNum(yyv[yysp-0]); 
       end;
       procedure A97; begin
         yyval := builder.CreateNum(yyv[yysp-0], yyv[yysp-1].text); 
       end;
       procedure A98; begin
         yyval := builder.CreateStr(yyv[yysp-0]); 
       end;
       procedure A99; begin
         yyval := builder.CreateTime(yyv[yysp-0]); 
       end;
       procedure A100; begin
         yyval := builder.CreateConst(yyv[yysp-0], true); 
       end;
       procedure A101; begin
         yyval := builder.CreateConst(yyv[yysp-0], false); 
       end;
       procedure A102; begin
         yyval := builder.CreateConst(yyv[yysp-0], NullValue); 
       end;
       procedure A103; begin
         yyval := builder.CreateRegex(yyv[yysp-0]); 
       end;
       procedure A104; begin
         
       end;
       procedure A105; begin
         yyval := builder.CreateNames(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A106; begin
         yyval := builder.CreateFunExp(yyv[yysp-3], yyv[yysp-0], yyv[yysp-3], yyv[yysp-1]); 
       end;
       procedure A107; begin
         yyval := builder.CreateSetConst(yyv[yysp-2], yyv[yysp-0], yyv[yysp-1]); 
       end;
       procedure A108; begin
         yyval := builder.CreateSetConst(yyv[yysp-3], yyv[yysp-0], yyv[yysp-2]); 
       end;
       procedure A109; begin
         yyval := builder.CreateSetIndex(yyv[yysp-3], yyv[yysp-0], yyv[yysp-3], yyv[yysp-1]); 
       end;
       procedure A110; begin
         yyval := builder.CreateSetIndex(yyv[yysp-4], yyv[yysp-0], yyv[yysp-4], yyv[yysp-1], '.'); 
       end;
       procedure A111; begin
         yyval := EmptyResult; 
       end;
       procedure A112; begin
         yyval := builder.CreateNames(yyv[yysp-0]); 
       end;
       procedure A113; begin
         yyval := builder.CreateNames(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0]); 
       end;
       procedure A114; begin
         yyval := EmptyResult; 
       end;
       procedure A115; begin
         yyval := builder.CreateValues(yyv[yysp-0]); 
       end;
       procedure A116; begin
         yyval := builder.CreateValues(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0]); 
       end;
       procedure A117; begin
         
       end;
       procedure A118; begin
         yyval := builder.CreateValue(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0]); 
       end;
       procedure A119; begin
         yyval := builder.CreateValue(yyv[yysp-2], yyv[yysp-0], yyv[yysp-2], yyv[yysp-0], true); 
       end;
//-act]
procedure AX_Init; begin
  AX[1] := @A1;
  AX[2] := @A2;
  AX[3] := @A3;
  AX[4] := @A4;
  AX[5] := @A5;
  AX[6] := @A6;
  AX[7] := @A7;
  AX[8] := @A8;
  AX[9] := @A9;
  AX[10] := @A10;
  AX[11] := @A11;
  AX[12] := @A12;
  AX[13] := @A13;
  AX[14] := @A14;
  AX[15] := @A15;
  AX[16] := @A16;
  AX[17] := @A17;
  AX[18] := @A18;
  AX[19] := @A19;
  AX[20] := @A20;
  AX[21] := @A21;
  AX[22] := @A22;
  AX[23] := @A23;
  AX[24] := @A24;
  AX[25] := @A25;
  AX[26] := @A26;
  AX[27] := @A27;
  AX[28] := @A28;
  AX[29] := @A29;
  AX[30] := @A30;
  AX[31] := @A31;
  AX[32] := @A32;
  AX[33] := @A33;
  AX[34] := @A34;
  AX[35] := @A35;
  AX[36] := @A36;
  AX[37] := @A37;
  AX[38] := @A38;
  AX[39] := @A39;
  AX[40] := @A40;
  AX[41] := @A41;
  AX[42] := @A42;
  AX[43] := @A43;
  AX[44] := @A44;
  AX[45] := @A45;
  AX[46] := @A46;
  AX[47] := @A47;
  AX[48] := @A48;
  AX[49] := @A49;
  AX[50] := @A50;
  AX[51] := @A51;
  AX[52] := @A52;
  AX[53] := @A53;
  AX[54] := @A54;
  AX[55] := @A55;
  AX[56] := @A56;
  AX[57] := @A57;
  AX[58] := @A58;
  AX[59] := @A59;
  AX[60] := @A60;
  AX[61] := @A61;
  AX[62] := @A62;
  AX[63] := @A63;
  AX[64] := @A64;
  AX[65] := @A65;
  AX[66] := @A66;
  AX[67] := @A67;
  AX[68] := @A68;
  AX[69] := @A69;
  AX[70] := @A70;
  AX[71] := @A71;
  AX[72] := @A72;
  AX[73] := @A73;
  AX[74] := @A74;
  AX[75] := @A75;
  AX[76] := @A76;
  AX[77] := @A77;
  AX[78] := @A78;
  AX[79] := @A79;
  AX[80] := @A80;
  AX[81] := @A81;
  AX[82] := @A82;
  AX[83] := @A83;
  AX[84] := @A84;
  AX[85] := @A85;
  AX[86] := @A86;
  AX[87] := @A87;
  AX[88] := @A88;
  AX[89] := @A89;
  AX[90] := @A90;
  AX[91] := @A91;
  AX[92] := @A92;
  AX[93] := @A93;
  AX[94] := @A94;
  AX[95] := @A95;
  AX[96] := @A96;
  AX[97] := @A97;
  AX[98] := @A98;
  AX[99] := @A99;
  AX[100] := @A100;
  AX[101] := @A101;
  AX[102] := @A102;
  AX[103] := @A103;
  AX[104] := @A104;
  AX[105] := @A105;
  AX[106] := @A106;
  AX[107] := @A107;
  AX[108] := @A108;
  AX[109] := @A109;
  AX[110] := @A110;
  AX[111] := @A111;
  AX[112] := @A112;
  AX[113] := @A113;
  AX[114] := @A114;
  AX[115] := @A115;
  AX[116] := @A116;
  AX[117] := @A117;
  AX[118] := @A118;
  AX[119] := @A119;
end;