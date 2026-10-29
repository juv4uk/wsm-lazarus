{ G4.43: перепис pinned Core4 для вимірювання ЗАВАНТАЖЕННЯ, не семантики.
  Вхідна .lisp є лише українською людською проєкцією.
  Ідентичність законів та виконання не виводяться з написання «визначити».
  Лише чинний TCore4Runtime допускає початкові bindings із фізичного .sens.
  Doc і Runtime локальні owned об'єкти, звільняються навіть після відмови.
  Питання: чому «визначити» не є semantic dispatch? Хто підтвердив 3?
  Чи означає 3/1223 повну підтримку? Чому W24 не означає D24 число? }
program senscore4pokryttia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.core4source, wsm.source, wsm.core4runtime;

function Perepys(const Root:String):RawByteString;
var
  Doc:TSourceDocument;
  Runtime:TCore4Runtime;
  I,Total,Lexical,BodyLists,BodyAtoms,BodyStrings,BodyOther,Loaded:SizeInt;
  N,Body:TSourceNode;
begin
  Result:='';
  Doc:=nil;
  Runtime:=nil;
  try
    { Borrowed text bytes live in this call; Doc owns all parsed nodes. }
    Doc:=ReadUkrainianSource(ReadPinnedCore4(Root));
    Total:=Length(Doc.Forms);
    if Total=0 then raise Exception.Create('порожній український Core4');
    Lexical:=0;
    BodyLists:=0;BodyAtoms:=0;BodyStrings:=0;BodyOther:=0;
    for I:=0 to High(Doc.Forms) do begin
      N:=Doc.Forms[I];
      { ЛИШЕ структурне українське написання для статистики.
        Не допускає і не виконує ні D4, ні один похідний закон. }
      if (N.Kind=skList) and (Length(N.Children)>0) and
         (N.Children[0].Kind=skAtom) and
         (N.Children[0].Text='визначити') then begin
        Inc(Lexical);
        if Length(N.Children)<>3 then begin
          Inc(BodyOther);
          Continue;
        end;
        Body:=N.Children[2];
        case Body.Kind of
          skList:Inc(BodyLists);
          skAtom:Inc(BodyAtoms);
          skString:Inc(BodyStrings);
        end;
      end;
    end;
    { Runtime фізично читає pinned lib/core4.sens і допускає перші
      канонічні D2-форми. Це НЕ виконання всіх визначень джерела. }
    Runtime:=TCore4Runtime.Create(Root);
    Loaded:=Runtime.BindingCount;
    if (Loaded<1) or (Lexical<Loaded) then
      raise Exception.Create('лексичний і фізичний Core4 не узгоджені');
    Result:='CORE4-ПЕРЕПИС-ГАРАЗД форм-укр='+IntToStr(Total)+
      ' визначень-укр='+IntToStr(Lexical)+
      ' тіл-списків='+IntToStr(BodyLists)+
      ' тіл-атомів='+IntToStr(BodyAtoms)+
      ' тіл-рядків='+IntToStr(BodyStrings)+
      ' тіл-інших='+IntToStr(BodyOther)+
      ' завантажено-фізично='+IntToStr(Loaded)+
      ' виконання-всіх=не-доведено'+LineEnding;
  finally
    Runtime.Free;
    Doc.Free;
  end;
end;

var Answer:RawByteString;
begin
  if (ParamCount<>2) or (ParamStr(1)<>'--перепис') then begin
    WriteLn(StdErr,'CORE4-ПЕРЕПИС-ВІДМОВА: команда --перепис корінь');
    ExitCode:=64;
  end else begin
    try
      Answer:=Perepys(ParamStr(2));
      Write(Answer); { атомарний stdout лише після повного допуску }
      ExitCode:=0;
    except
      on E:Exception do begin
        WriteLn(StdErr,'CORE4-ПЕРЕПИС-ВІДМОВА: ',E.Message);
        ExitCode:=2;
      end;
    end;
  end;
end.
