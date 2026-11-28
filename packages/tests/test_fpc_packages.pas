program test_fpc_packages;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  SysUtils,
  wsm.source,
  wsm.domain;

procedure Require(Condition: Boolean; const MessageText: String);
begin
  if not Condition then
  begin
    WriteLn(StdErr, 'FPC-PACKAGES-FAIL ', MessageText);
    Halt(1);
  end;
end;

procedure TestSourceReader;
var
  Doc: TSourceDocument;
  Root: TSourceNode;
  Rejected: Boolean;
begin
  Doc := ReadUkrainianSource('(корінь "два слова" (дитина атом))');
  try
    Require(Length(Doc.Forms) = 1, 'очікувався один кореневий вузол');
    Root := Doc.Forms[0];
    Require(Root.Kind = skList, 'корінь має бути списком');
    Require(Length(Root.Children) = 3, 'втрачено дочірні вузли');
    Require(Root.Children[0].Text = 'корінь', 'зіпсовано UTF-8 atom');
    Require(Root.Children[1].Kind = skString, 'рядок не збережено як string');
    Require(Root.Children[1].Text = '"два слова"',
      'змінено точні байти string');
    Require(Root.Children[2].Kind = skList, 'вкладений список втрачено');
  finally
    Doc.Free;
  end;

  Rejected := False;
  try
    Doc := ReadUkrainianSource(')');
    Doc.Free;
  except
    on E: ESourceError do
      Rejected := True;
  end;
  Require(Rejected, 'reader прийняв зайву закривальну дужку');
end;

procedure TestDomainMechanics;
const
  Fixture =
    '(domain-table-1' + LineEnding +
    ' (0 (ук fixture-zero) (укр fixture-zero) (san zero) (en zero) (LISP zero) (sym z))' + LineEnding +
    ' (1 (ук fixture-one) (укр fixture-one) (san one) (en one) (LISP one) (sym o)))';
var
  Rows: TDomainTable;
  Key: TDomainKey;
  Row: TDomainRow;
  Rejected: Boolean;
begin
  LoadDomainTable(Fixture, 1, Rows);
  Require(Length(Rows) = 2, 'fixture-таблиця має містити дві координати');
  Require(SameKey(Rows[0].Key, ExactKey('0')), 'втрачено D1:0');
  Require(SameKey(Rows[1].Key, ExactKey('1')), 'втрачено D1:1');

  Require(UkrainianKey(Rows, 'fixture-one', Key),
    'не знайдено тестову поверхню ук');
  Require(SameKey(Key, ExactKey('1')), 'поверхня повернула іншу координату');
  Require(DomainRowByKey(Rows, ExactKey('1'), Row),
    'не знайдено точний доменний ключ');
  Require(Row.Ukrainian = 'fixture-one', 'неправильне зворотне зіставлення');
  Require(not SameKey(ExactKey('1'), ExactKey('01')),
    'ширина координати не бере участі в ідентичності');
  Require(KeyBits(ExactKey('0000001001')) = '0000001001',
    'втрачено ширину або провідні нулі D10');

  Rejected := False;
  try
    Key := ExactKey('00x');
  except
    on E: EDomainError do
      Rejected := True;
  end;
  Require(Rejected, 'прийнято не двійкову координату');

  Rejected := False;
  try
    LoadDomainTable(Fixture + LineEnding + '(стороння-форма)', 1, Rows);
  except
    on E: EDomainError do
      Rejected := True;
  end;
  Require(Rejected, 'прийнято сторонню top-level форму');
  Require(Length(Rows) = 0, 'після відмови опубліковано стару/часткову таблицю');
end;

begin
  TestSourceReader;
  TestDomainMechanics;
  WriteLn('FPC-PACKAGES-OK source=1 domain=1 negative=4 ownership=checked');
end.
