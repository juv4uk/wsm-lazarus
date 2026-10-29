{ G6.38 — справжній native Linux x86-64 для п'яти Д3 механізмів.
  Фізичні випадки за pinned D3, D7 SYN=дані, числа D12+ не підмінювати.
  Відповідь — T5M байти, не host Unicode / число чи ASCII. }
program test_elfprobe_all;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfprobe,wsm.binaryexec;
var
  Root:String;
  Passed,Rejected:SizeInt;
  Exec:TBinaryExecutor;

procedure Require(Yes:Boolean;const Why:String);
begin
  if not Yes then raise Exception.Create('МАШИНА-ПЯТЬ-Д3-ПРОВАЛ: '+Why);
end;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;

procedure Positive(const LabelText:String;Profile:TNativeELFProfile;
  const SourceWords,ResultWords:array of RawByteString);
var Physical,Expected,Answer,Independent:RawByteString;
begin
  Physical:=EncodeT5M(W(SourceWords));
  Expected:=EncodeT5M(W(ResultWords));
  Independent:=Exec.ExecutePhysicalT5M(Physical);
  Require(Independent=Expected,
    LabelText+' базовий фізичний D3 виконавець не підтвердив свідка');
  Answer:='не-успіх';
  ExecutePinnedNativeELF(Physical,RawByteString(Root),Profile,Answer);
  Require(Answer=Expected,LabelText+' справжній ELF не повернув точний T5M');
  Inc(Passed);
end;

procedure NegativeRaw(const LabelText:String;Profile:TNativeELFProfile;
  const Physical:RawByteString);
var Answer:RawByteString;Failed:Boolean;
begin
  Answer:='застаріла-відповідь';
  Failed:=False;
  try
    ExecutePinnedNativeELF(Physical,RawByteString(Root),Profile,Answer);
  except on E:EELFProbeError do Failed:=True end;
  Require(Failed and (Answer=''),LabelText+' не закрив помилку та out T5M');
  Inc(Rejected);
end;

procedure Negative(const LabelText:String;Profile:TNativeELFProfile;
  const Words:array of RawByteString);
begin
  NegativeRaw(LabelText,Profile,EncodeT5M(W(Words)));
end;

var
  QuoteSource,EqSource:RawByteString;
begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Потрібен pinned корінь SENS');Halt(64);
  end;
  Root:=ParamStr(1);
  Passed:=0;Rejected:=0;
  Exec:=TBinaryExecutor.Create(RawByteString(Root));
  try
    { D3:001 — точний цитований D7 SYN не стає функцією/числом. }
    Positive('цитата-D7-SYN',npQuote,['10','001','0010110','01'],
      ['0010110']);
    Positive('цитата-D1-нуль',npQuote,['10','001','0','01'],['0']);
    Positive('цитата-D1-один',npQuote,['10','001','1','01'],['1']);

    Positive('атом-D1-нуль',npAtom,['10','010','0','01'],['1']);
    Positive('атом-D3-порожній',npAtom,
      ['10','010','000','01'],['1']);
    Positive('атом-CONS',npAtom,
      ['10','010','10','111','0','1','01','01'],['0']);

    Positive('тотожність-00',npEq,['10','101','0','0','01'],['1']);
    Positive('тотожність-01',npEq,['10','101','0','1','01'],['0']);
    Positive('тотожність-10',npEq,['10','101','1','0','01'],['0']);
    Positive('тотожність-11',npEq,['10','101','1','1','01'],['1']);

    Positive('перше-00',npSelector,
      ['10','100','10','111','0','0','01','01'],['0']);
    Positive('перше-01',npSelector,
      ['10','100','10','111','0','1','01','01'],['0']);
    Positive('перше-10',npSelector,
      ['10','100','10','111','1','0','01','01'],['1']);
    Positive('перше-11',npSelector,
      ['10','100','10','111','1','1','01','01'],['1']);
    Positive('решта-00',npSelector,
      ['10','011','10','111','0','0','01','01'],['0']);
    Positive('решта-01',npSelector,
      ['10','011','10','111','0','1','01','01'],['1']);
    Positive('решта-10',npSelector,
      ['10','011','10','111','1','0','01','01'],['0']);
    Positive('решта-11',npSelector,
      ['10','011','10','111','1','1','01','01'],['1']);

    Positive('умова-вичерпана',npCond,['10','110','01'],['000']);
    Positive('умова-істинна',npCond,
      ['10','110','10','1','1','01','01'],['1']);
    Positive('умова-хибний-тест',npCond,
      ['10','110','10','0','1','01','01'],['000']);
    Positive('умова-машинне-EQ',npCond,
      ['10','110','10','1','10','101','1','1','01','01','01'],['1']);

    QuoteSource:=EncodeT5M(W(['10','001','0010110','01']));
    EqSource:=EncodeT5M(W(['10','101','0','1','01']));
    NegativeRaw('D7-цитата-не-ATOM',npAtom,QuoteSource);
    NegativeRaw('D7-цитата-не-EQ',npEq,QuoteSource);
    NegativeRaw('D7-цитата-не-селектор',npSelector,QuoteSource);
    NegativeRaw('D7-цитата-не-умова',npCond,QuoteSource);
    NegativeRaw('EQ-не-цитата',npQuote,EqSource);
    NegativeRaw('EQ-не-ATOM',npAtom,EqSource);
    NegativeRaw('EQ-не-селектор',npSelector,EqSource);
    NegativeRaw('EQ-не-умова',npCond,EqSource);
    NegativeRaw('порожній-T5M',npQuote,'');
    NegativeRaw('неканонічний-байт-243',npAtom,#$F3);
    Negative('відкрито-але-не-закрито',npCond,
      ['10','110','10','1','1']);
    Negative('D12-не-D1-предикат',npCond,
      ['10','110','10','000000000000','1','01','01']);
    Negative('D12-не-D1-ATOM',npAtom,
      ['10','010','000000000000','01']);
    Negative('D12-не-D1-EQ',npEq,
      ['10','101','000000000000','0','01']);
    Negative('D12-не-D1-CONS',npSelector,
      ['10','100','10','111','000000000000','1','01','01']);
    Negative('голий-D1-не-виклик',npQuote,['0']);
    { G6.42: обхід exact provenance ЗАБОРОНЕНО навіть коли старий
      binary emitter раніше відхиляв таку форму власною перевіркою.
      D7 SYN може бути цитованим значенням, але НЕ головою виклику. }
    Negative('D7-SYN-не-виклична-голова',npQuote,
      ['10','0010110','1','01']);
    Negative('D12-не-виклична-голова',npAtom,
      ['10','000000000000','1','01']);
    Negative('D3-порожній-не-виклична-голова',npCond,
      ['10','000','1','01']);
    Negative('неправильна-арність-після-IR',npQuote,
      ['10','001','1','0','01']);
    Require((Passed=22) and (Rejected=20),'Лічильники фізичних свідків');
    WriteLn('МАШИНА-ПЯТЬ-D3-ГАРАЗД Linux=x86-64 ELF=',
      Passed,' негативні=',Rejected,
      ' stdout=T5M-byte-exact D7=SYN-дані D12+=відхилено');
  finally Exec.Free end;
end.

{ Типи: Profile — приватна host категорія ЕМІТЕРА, не семантичний Dn.
  Physical/Answer — packed T5M, Answer надходить від Linux kernel
  stdout тільки після повної byte-exact перевірки; виконавчий ELF
  та його власний temp-каталог знищуються самим probe.
  1) Чому 7-бітний SYN не є арифметичним D12?
  2) Чому ExactIR відхиляє D7 SYN як голову, але дозволяє цитату?
  3) Чому відмова не може залишити старий Answer?
  4) Чому CLI українською не визначає binary dispatch?
  5) Чому нативний FPC executor — свідок, але не SENS REPL oracle? }
