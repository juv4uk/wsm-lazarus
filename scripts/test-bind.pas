program test_bind;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain, wsm.bind;
var T:TDomainSet; K:TDomainKey; Row:TDomainRow;
    Raised:Boolean; D,I,Count:Integer;
procedure Expect(B:Boolean; const Why:String);
begin if not B then begin WriteLn(StdErr,'BIND-FAIL ',Why); Halt(1); end; end;

{ Механічний test: фізичні pinned таблиці зібрано до temp-root.
  Усі рядки D1–D9 — реальні, D10 навмисно пізно пошкоджений. }
procedure TestAtomicPinnedLoad;
var
  Root, P, Data: String;
  Source, Target: TFileStream;
  CopyTables: TDomainSet;
  D: Integer;
  Failed: Boolean;
begin
  Root := 'build/m0.2/bind-atomic-d10';
  Expect(ForceDirectories(Root+'/lib/domains'),
    'не створено тимчасовий pinned-набір');
  try
    for D:=FirstDomain to LastDomain do begin
      P:='lib/domains/d'+IntToStr(D)+'.lisp';
      Source:=TFileStream.Create('external/sens/'+P,fmOpenRead or fmShareDenyWrite);
      try
        Target:=TFileStream.Create(Root+'/'+P,fmCreate);
        try Target.CopyFrom(Source,Source.Size);
        finally Target.Free end;
      finally Source.Free end;
    end;

    { Помилка відкриття ОСТАННЬОЇ таблиці: попередні D1–D9
      вже повністю зчитані, але зовнішньому caller їх не видно. }
    Expect(DeleteFile(Root+'/lib/domains/d10.lisp'),
      'не вдалося прибрати пізню pinned-таблицю');
    Failed:=False;
    try LoadPinnedDomains(RawByteString(Root),CopyTables);
    except on E:Exception do Failed:=True end;
    Expect(Failed,'відсутній D10 не був відхилений');
    for D:=FirstDomain to LastDomain do
      Expect(Length(CopyTables[D])=0,
        'часткові D1–D9 після відсутнього D10');

    { Не просто I/O: фізично існує некомплектна D10 таблиця
      з правильною 10-бітовою координатою, але 1023 рядків бракує. }
    Data:='(0000000000 (ук проба))'+#10;
    Target:=TFileStream.Create(Root+'/lib/domains/d10.lisp',fmCreate);
    try Target.WriteBuffer(Data[1],Length(Data));
    finally Target.Free end;
    Failed:=False;
    try LoadPinnedDomains(RawByteString(Root),CopyTables);
    except on E:EDomainError do Failed:=True end;
    Expect(Failed,'неповний D10 не відхилено');
    for D:=FirstDomain to LastDomain do
      Expect(Length(CopyTables[D])=0,
        'часткові D1–D9 після неповної D10');

    { G2.41: пізня D10 може бути фізично понад 1 МіБ.
      Таку копію слід відхилити ДО SetLength(Data,F.Size), а не
      після повного зчитування чи розбору тексту. }
    Data:=StringOfChar(' ',1024*1024+1);
    Target:=TFileStream.Create(Root+'/lib/domains/d10.lisp',fmCreate);
    try Target.WriteBuffer(Data[1],Length(Data));
    finally Target.Free end;
    Failed:=False;
    try LoadPinnedDomains(RawByteString(Root),CopyTables);
    except
      on E:EBindError do begin
        Failed:=Pos('D10:',E.Message)>0;
        Expect(Pos('1 МіБ',E.Message)>0,
          'адресна фізична межа повинна пояснити 1 МіБ');
      end;
    end;
    Expect(Failed,'пізня D10 понад 1 МіБ не відхилена рано');
    for D:=FirstDomain to LastDomain do
      Expect(Length(CopyTables[D])=0,
        'не можна публікувати D1–D9 після завеликої D10');

    { Тепер ранній D1 >1 МіБ повинен мати адресу саме D1,
      навіть коли після нього лежить ще одна завелика D10. }
    Target:=TFileStream.Create(Root+'/lib/domains/d1.lisp',fmCreate);
    try Target.WriteBuffer(Data[1],Length(Data));
    finally Target.Free end;
    Failed:=False;
    try LoadPinnedDomains(RawByteString(Root),CopyTables);
    except on E:EBindError do Failed:=Pos('D1:',E.Message)>0 end;
    Expect(Failed,'перша завелика D1 не відхилена до D10');
    for D:=FirstDomain to LastDomain do
      Expect(Length(CopyTables[D])=0,
        'не можна публікувати координати після завеликої D1');
    Data:='';

    { Відсутність або порожня D1 — окрема рання відмова.
      Не приймати 0 байтів як пусту ратифіковану таблицю. }
    Target:=TFileStream.Create(Root+'/lib/domains/d1.lisp',fmCreate);
    Target.Free;
    Failed:=False;
    try LoadPinnedDomains(RawByteString(Root),CopyTables);
    except on E:EBindError do Failed:=Pos('D1:',E.Message)>0 end;
    Expect(Failed,'порожній файл D1 не відхилено адресно');
    for D:=FirstDomain to LastDomain do
      Expect(Length(CopyTables[D])=0,
        'порожня D1 не може опублікувати часткові таблиці');

    { Справжній pinned authority той самий. Після відмови
      повторний повний допуск не залежить від старого стану. }
    LoadPinnedDomains('external/sens',CopyTables);
    for D:=FirstDomain to LastDomain do
      Expect(Length(CopyTables[D])=(1 shl D),
        'повторне завантаження pinned D1–D10 не відновилося');
    WriteLn('BIND-ATOMIC-OK late-missing-D10=reject ',
      'late-corrupt-D10=reject oversize-D10/D1=reject ',
      'empty-D1=reject partial=none recovery=all-10');
  finally
    for D:=FirstDomain to LastDomain do
      DeleteFile(Root+'/lib/domains/d'+IntToStr(D)+'.lisp');
    RemoveDir(Root+'/lib/domains');
    RemoveDir(Root+'/lib');
    RemoveDir(Root);
  end;
end;

begin
  LoadPinnedDomains('external/sens',T);
  Count:=0;
  for D:=FirstDomain to LastDomain do begin
    Expect(Length(T[D])=(1 shl D),'pinned domain incomplete');
    for I:=0 to High(T[D]) do begin
      Expect(T[D][I].Key.Width=D,'domain width mismatch');
      Expect(T[D][I].Key.Bits=I,'domain coordinate not ordered');
      if T[D][I].Ukrainian='' then Continue;
      K:=BindUkrainian(T,T[D][I].Ukrainian);
      Expect(SameKey(K,T[D][I].Key),'global Ukrainian lookup not invertible');
      K:=BindUkrainianInDomain(T,T[D][I].Ukrainian,D);
      Expect(SameKey(K,T[D][I].Key),'scoped Ukrainian lookup not invertible');
      Expect(DomainRowByKey(T[D],K,Row),'coordinate reverse lookup missing');
      Expect(Row.Ukrainian=T[D][I].Ukrainian,'coordinate reverse projection mismatch');
      Inc(Count);
    end;
  end;
  K:=BindUkrainian(T,'так');
  Expect(SameKey(K,ExactKey('1')),'D1 yes');
  K:=BindUkrainian(T,'відкрити');
  Expect(SameKey(K,ExactKey('10')),'D2 open');
  K:=BindUkrainian(T,'за-умовою');
  Expect(SameKey(K,ExactKey('110')),'D3 cond');
  K:=BindUkrainian(T,'функція');
  Expect(SameKey(K,ExactKey('0010')),'D4 lambda');
  K:=BindUkrainian(T,'довжина');
  Expect(SameKey(K,ExactKey('000000')),'D6 length');
  K:=BindUkrainian(T,'символ-за-кодом');
  Expect(SameKey(K,ExactKey('00000000')),'D8 code-char');
  K:=BindUkrainian(T,'пояснити-відповідь');
  Expect(SameKey(K,ExactKey('000000001')),'D9 answer');
  K:=BindUkrainian(T,'якщо');
  Expect(SameKey(K,ExactKey('0000000110')),'D10 if');
  Raised:=False;
  try K:=BindUkrainian(T,'quote'); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'foreign spelling accepted');
  Raised:=False;
  try K:=BindUkrainian(T,''); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'empty spelling accepted');
  Raised:=False;
  try K:=BindUkrainianInDomain(T,'так',3); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'wrong-domain lookup accepted');
  Raised:=False;
  try K:=BindUkrainianInDomain(T,'так',0); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'unsupported domain accepted');
  T[1][0].Ukrainian:='за-умовою';
  Raised:=False;
  try K:=BindUkrainian(T,'за-умовою'); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'cross-domain ambiguity accepted');
  TestAtomicPinnedLoad;
  WriteLn('BIND-OK domains=10 checked=',Count,' unknown=reject ambiguity=reject');
end.
