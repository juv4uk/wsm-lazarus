{ Компілятор: host x86-64 LEA з явним SIB, без мовного dispatch.
  Вхід: TX64Code (managed RawByteString), регістри r64, масштаб 1/2/4/8
  та signed disp8. Вихід: 4 або 5 машинних байтів у Code.Bytes.
  Ownership: Code лишається у caller; відмова не змінює буфер.
  LEA обчислює host-адресу, але не визначає Dn чи закон SENS.
  Питання: 1) Чому RSP заборонено як index у SIB?
  2) Чому RBP без disp вимагає окремого нульового disp8?
  3) Чому scale не є множенням у мові SENS?
  4) Чому всі перевірки відбуваються до конкатенації?
  5) Чому 256 байтів — host-квота, а не ширина домену? }
unit wsm.x64lea;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.x64code;
procedure X64LeaIndexed(var Code:TX64Code; Destination,Base,Index:TX64Reg;
                        Scale,Displacement:SizeInt);
implementation
const MaxHostCode=256;
procedure X64LeaIndexed(var Code:TX64Code; Destination,Base,Index:TX64Reg;
                        Scale,Displacement:SizeInt);
var ScaleBits,ModRM,SIB:Byte; Bytes:RawByteString;
begin
  if (Ord(Destination)>7) or (Ord(Base)>7) or (Ord(Index)>7) then
    raise EX64CodeError.Create('LEA: недопустимий host-регістр');
  if Index=xrSP then
    raise EX64CodeError.Create('LEA: RSP не може бути SIB-індексом');
  case Scale of
    1:ScaleBits:=0;
    2:ScaleBits:=1;
    4:ScaleBits:=2;
    8:ScaleBits:=3;
  else
    raise EX64CodeError.Create('LEA: масштаб має бути 1/2/4/8');
  end;
  if (Displacement < -128) or (Displacement > 127) then
    raise EX64CodeError.Create('LEA: зміщення не є signed disp8');
  { Для RBP mod=00,r/m=101 означав би RIP-relative. Потрібен mod=01
    і справжній нульовий disp8. RSP як base доступний через SIB. }
  if (Displacement=0) and (Base<>xrBP) then
    ModRM:=(Ord(Destination) shl 3) or 4
  else
    ModRM:=$40 or (Ord(Destination) shl 3) or 4;
  SIB:=(ScaleBits shl 6) or (Ord(Index) shl 3) or Ord(Base);
  Bytes:=#$48#$8D+AnsiChar(ModRM)+AnsiChar(SIB);
  if (Displacement<>0) or (Base=xrBP) then
    Bytes:=Bytes+AnsiChar(Byte(Displacement and $FF));
  if Length(Code.Bytes)>MaxHostCode-Length(Bytes) then
    raise EX64CodeError.Create('LEA: host-квота 256 байтів');
  Code.Bytes:=Code.Bytes+Bytes;
end;
end.
