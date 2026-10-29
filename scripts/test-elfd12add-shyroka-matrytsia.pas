{ G6.98: фізичні тестові свідки. Канон — тільки pinned SENS;
  детермінована host-матриця не є новим числовим законом. }
program test_elfd12add_shyroka_matrytsia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.numericplane;
const
  Cases = 256;
type
  TPair = record
    L, R: LongInt;
  end;
const
  Edges: array[0..15] of TPair = (
    (L:0;R:0), (L:1;R:-1), (L:2047;R:-2048),
    (L:-2048;R:2047), (L:2047;R:0), (L:-2048;R:0),
    (L:2046;R:1), (L:-2047;R:-1), (L:1023;R:1024),
    (L:-1024;R:-1024), (L:13;R:-11), (L:-17;R:19),
    (L:2047;R:-1), (L:-2048;R:1), (L:1;R:1), (L:-1;R:-1)
  );
var
  Dir: String;
  I, L, R, Sum: LongInt;
  Seed: QWord;

procedure Save(const Name: String; const Physical: RawByteString);
var Stream: TFileStream;
begin
  if Length(Physical)<>3 then
    raise Exception.Create('Точне D12 повинно мати три T5M байти');
  Stream:=TFileStream.Create(Dir+'/'+Name, fmCreate);
  try
    Stream.WriteBuffer(Physical[1], Length(Physical));
  finally
    Stream.Free;
  end;
end;

procedure OneCase(const Index, Left, Right: LongInt);
var
  ResultValue: LongInt;
  S: String;
begin
  ResultValue:=Left+Right; { host-модель лише для очікуваного свідка }
  if (Left < -2048) or (Left > 2047) or
     (Right < -2048) or (Right > 2047) or
     (ResultValue < -2048) or (ResultValue > 2047) then
    raise Exception.Create('Тест містить переповнення D12');
  S:=Format('%.4d',[Index]);
  Save(S+'-l.sens',EncodeNumericDecimal(IntToStr(Left),12));
  Save(S+'-r.sens',EncodeNumericDecimal(IntToStr(Right),12));
  Save(S+'-expected.sens',EncodeNumericDecimal(IntToStr(ResultValue),12));
end;

begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Seed:=$6A09E667; { фіксована host послідовність }
  for I:=0 to Cases-1 do begin
    if I<=High(Edges) then begin
      L:=Edges[I].L;
      R:=Edges[I].R;
    end else begin
      Seed:=(Seed*1664525+1013904223) and $FFFFFFFF;
      L:=LongInt((Seed shr 10) mod 2001)-1000;
      Seed:=(Seed*1664525+1013904223) and $FFFFFFFF;
      R:=LongInt((Seed shr 10) mod 2001)-1000;
    end;
    Sum:=L+R;
    if (Sum < -2048) or (Sum > 2047) then Halt(3);
    OneCase(I,L,R);
  end;
  WriteLn('ЕЛФ-Д12-МАТРИЦЯ-СВІДКИ випадків=',Cases,
    ' крайових=',Length(Edges),' решта=детерміновані');
end.

{ Фізичний тип: D12 результат має три owned T5M байти;
  Stream звільняється через try/finally; це не SENS REPL oracle.
  Питання: 1) Навіщо квота три байти? 2) Хто звільняє Stream?
  3) Для чого seed? 4) Чому межі -2048..2047?
  5) Чому незалежний SENS oracle запускаємо окремо? }
