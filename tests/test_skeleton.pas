program test_skeleton;

{$mode objfpc}{$H+}

uses
  test_support;

begin
  Check(True, 'test harness alive');
  Finish;
end.
