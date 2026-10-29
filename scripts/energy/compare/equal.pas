program energy_equal;
{$mode objfpc}{$H+}
{$INLINE OFF}
uses SysUtils;

type
  TEqual = function(Left,Right:QWord):Boolean;

function ExactEqual(Left,Right:QWord):Boolean;
begin
  Result:=Left=Right;
end;

var
  Line:String;
  Count,I,Matches:QWord;
  EqualFn:TEqual;
begin
  EqualFn:=@ExactEqual;
  WriteLn('READY'); Flush(Output);
  while not EOF(Input) do begin
    ReadLn(Line);
    if not TryStrToQWord(Line,Count) or (Count<1) or (Count>1000000000) then
      Halt(2);
    Matches:=0;
    for I:=0 to Count-1 do
      if EqualFn((I*17+3) and 255,(I*17+3) and 255) then Inc(Matches);
    if Matches<>Count then Halt(3);
    WriteLn('OK',#9,Count,#9,Matches*161); Flush(Output);
  end;
end.

{ Питання: як procvar впливає на виклик? Де перевіряється результат?
  Чому фізичний SENS-байт 1 дає checksum 161? Що не входить у вимір? }
