{ G6.17 — регресія життєвого циклу керованих полів широкого IR.
  Запускати лише з -gh (heaptrc): відсутність leak — окрема умова shell.
  Мовні закони й числове значення тут не встановлюються. }
program test_wideir_lifetime;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes,SysUtils,wsm.t5m,wsm.d2source,wsm.physloc,
  wsm.domain,wsm.bind,wsm.wideir;

procedure Demand(Yes:Boolean;const Why:String);
begin
  if not Yes then raise Exception.Create('пам’ять широкого IR: '+Why);
end;

function ExactBits(Width:SizeInt;Last:AnsiChar):RawByteString;
begin
  SetLength(Result,Width);
  if Width>0 then begin
    FillChar(Result[1],Width,Ord('0'));
    Result[Width]:=Last;
  end;
end;

function ReadPinned(const Path:String):RawByteString;
var FileStream:TFileStream;
begin
  FileStream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Demand((FileStream.Size>0) and
      (FileStream.Size<=MAX_T5M_FILE_BYTES),'недопустимий pinned свідок');
    SetLength(Result,SizeInt(FileStream.Size));
    FileStream.ReadBuffer(Result[1],Length(Result));
  finally FileStream.Free;end;
end;

procedure Exercise(const Pinned:RawByteString);
var
  Tables:TDomainSet;
  Words:TExactWords;
  IR:TWideIR;
  Physical,Corrupted:RawByteString;
  I,Round,Opaque,Count24:SizeInt;
  Thrown:Boolean;
begin
  LoadPinnedDomains('external/sens',Tables);

  { Важливий випадок для managed fields: кожен наступний атом
    багаторазово переписує локальний запис Item.Bits в BuildWideIR.
    Клієнт і AST не повинні залишати осиротілих рядків. }
  SetLength(Words,66);
  Words[0]:='10';
  for I:=1 to 32 do Words[I]:=ExactBits(192,'1');
  for I:=33 to 64 do Words[I]:=ExactBits(12,'0');
  Words[65]:='01';
  Physical:=EncodeT5M(Words);
  for Round:=1 to 12 do begin
    BuildWideIR(Physical,Tables,IR);
    Demand((Length(IR.Roots)=1) and (Length(IR.Nodes)=65) and
      (IR.OpaqueLeaves=64) and (IR.PhysicalLeaves=64),
      'кількість фізичних листків/коренів');
    Demand((IR.Nodes[1].Width=192) and
      (IR.Nodes[1].Bits=ExactBits(192,'1')) and
      (IR.Nodes[64].Width=12) and
      (IR.Nodes[64].Bits=ExactBits(12,'0')) and
      (not IR.Nodes[64].HasPinnedKey),
      'ширина/провідні нулі або W12 названо законом');

    { Повторне присвоювання out IR мусить коректно зняти
      попередні посилання; реальний pinned SENS має два W24. }
    BuildWideIR(Pinned,Tables,IR);
    Count24:=0;
    for I:=0 to High(IR.Nodes) do
      if IR.Nodes[I].Width=24 then begin
        Demand(not IR.Nodes[I].HasPinnedKey,
          'чисто фізичне W24 помилково прийнято як закон');
        Inc(Count24);
      end;
    Demand(Count24=2,'у pinned джерелі немає двох W24');
  end;

  { D2 крапкова пара — похідна, але два дочірні бітові рядки
    повинні звільнятися разом зі структурою. }
  SetLength(Words,5);
  Words[0]:='10';
  Words[1]:='1';
  Words[2]:='11';
  Words[3]:=ExactBits(192,'0');
  Words[4]:='01';
  for Round:=1 to 6 do begin
    BuildWideIR(EncodeT5M(Words),Tables,IR);
    Demand((Length(IR.Nodes)=3) and (IR.Nodes[0].Kind=wkPair) and
      (not IR.Nodes[0].OwnWord) and
      (IR.Nodes[2].Width=192) and
      (IR.Nodes[2].Bits=ExactBits(192,'0')),
      'фізична крапкова пара не оборотна');
  end;

  { Пізня фізична помилка не має залишити часткових значень,
    а повторне успішне читання не повинно успадковувати пам’ять. }
  Corrupted:=Physical+#243;
  for Round:=1 to 6 do begin
    Thrown:=False;
    try BuildWideIR(Corrupted,Tables,IR);
    except on E:ET5MError do Thrown:=True; end;
    Demand(Thrown,'пізній T5M 243 помилково прийнято');
    Demand((Length(IR.Nodes)=0) and (Length(IR.Roots)=0) and
      (IR.OpaqueLeaves=0),'помилка залишила часткове IR');
    BuildWideIR(Physical,Tables,IR);
    Demand(IR.OpaqueLeaves=64,'відновлення після помилки');
  end;

  { Ширина за межами фізичного reader: не було часткової публікації. }
  SetLength(Words,2);
  Words[0]:=ExactBits(12,'1');
  Words[1]:=ExactBits(193,'1');
  Thrown:=False;
  try BuildWideIR(EncodeT5M(Words),Tables,IR);
  except on E:ED2SourceError do Thrown:=True; end;
  Demand(Thrown and (Length(IR.Nodes)=0),'W193 не відхилено атомарно');

  { Явне звільнення останнього результату, без Halt у тестах. }
  SetLength(IR.Nodes,0);
  SetLength(IR.Roots,0);
  SetLength(Words,0);
  SetLength(Tables,0);
  WriteLn('ШИРОКЕ-IR-ПАМ’ЯТЬ-ТЕСТ: pinned-W24=2 W12/W192=точні ',
    'ітерації=12 відмови=атомарні очікування=heaptrc-0');
end;

var Physical:RawByteString;
begin
  try
    Demand(ParamCount=1,'потрібен pinned .sens від кореневого SENS');
    Physical:=ReadPinned(ParamStr(1));
    Exercise(Physical);
    Physical:='';
  except
    on E:Exception do begin
      WriteLn(StdErr,'ШИРОКЕ-IR-ПАМ’ЯТЬ-ПОМИЛКА: ',E.Message);
      ExitCode:=1;
    end;
  end;
end.
