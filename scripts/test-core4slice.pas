{ Фізичний зворотний збір оригінального pinned Core4.
  Перевіряємо лише байти й структуру, а не виконання форм. }
program test_core4slice;
{$mode objfpc}{$H+}
uses SysUtils, wsm.core4slice, wsm.core4source, wsm.source;
var
  PackageData: TCore4SourcePackage;
  Physical, Rebuilt: RawByteString;
  I: SizeInt;
  One: TSourceDocument;
procedure Demand(Condition:Boolean; const MessageText:String);
begin
  if not Condition then raise Exception.Create('CORE4-ФОРМА-ПРОВАЛ: '+MessageText);
end;
begin
  if ParamCount<>1 then Halt(64);
  try
    SlicePinnedCore4(ParamStr(1),PackageData);
    Physical:=ReadPinnedCore4(ParamStr(1));
    Demand(Length(PackageData.Forms)=1223,
      'число форм pinned authority відрізняється від перевіреного SHA');
    Rebuilt:=PackageData.Prefix;
    for I:=0 to High(PackageData.Forms) do begin
      Demand(PackageData.Forms[I].StartByte=Length(Rebuilt)+1,
        'точний початок форми');
      Demand(PackageData.Forms[I].EndByteExclusive=
        PackageData.Forms[I].StartByte+Length(PackageData.Forms[I].Source),
        'точний напіввідкритий байтовий інтервал');
      Rebuilt:=Rebuilt+PackageData.Forms[I].Source;
      One:=ReadUkrainianSource(PackageData.Forms[I].Source);
      try
        Demand(Length(One.Forms)=1,'окрема вихідна форма');
        Demand(One.Forms[0].ByteOffset=1,'повторне читання без зсуву');
      finally One.Free end;
    end;
    Demand(Rebuilt=Physical,'повне відновлення початкових UTF-8 байтів');
    Demand(PackageData.Forms[0].StartByte>1,'враховано вихідний коментар');
    WriteLn('CORE4-ФОРМИ-ГАРАЗД форм=',Length(PackageData.Forms),
      ' байтів=',Length(Physical),
      ' фізичні-позиції=так відновлення=байт-у-байт виконання=ні');
  except on E:Exception do begin
    WriteLn(StdErr,E.Message);
    Halt(1);
  end end;
end.
