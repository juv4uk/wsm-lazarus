{$mode objfpc}{$H+}
program fpmake;

uses
  fpmkunit;

var
  P: TPackage;

begin
  with Installer do
  begin
    P := AddPackage('wsm-source');
    P.ShortName := 'wsmsrc';
    P.Directory := 'packages/wsm-source';
    P.Version := '0.1.0';
    P.Author := 'juv4uk';
    P.License := 'LicenseRef-Volnist';
    P.HomepageURL := 'https://github.com/juv4uk/wsm-lazarus';
    P.Description :=
      'Bounded UTF-8 structural reader for Ukrainian source projections.';
    P.Dependencies.Clear; { FPC RTL is intrinsic to the compiler toolchain. }
    P.SourcePath.Add('../../src');
    P.UnitDir := 'units/$(target)';
    P.Targets.AddUnit('wsm.source.pas');

    P := AddPackage('wsm-domain');
    P.ShortName := 'wsmdom';
    P.Directory := 'packages/wsm-domain';
    P.Version := '0.1.0';
    P.Author := 'juv4uk';
    P.License := 'LicenseRef-Volnist';
    P.HomepageURL := 'https://github.com/juv4uk/wsm-lazarus';
    P.Description :=
      'Exact-width domain-coordinate table mechanics; no language evaluator.';
    P.Dependencies.Clear;
    P.Dependencies.Add('wsm-source');
    P.SourcePath.Add('../../src');
    P.UnitPath.Add('packages/wsm-source/units/$(target)');
    P.UnitDir := 'units/$(target)';
    P.Targets.AddUnit('wsm.domain.pas');

    Run;
  end;
end.
