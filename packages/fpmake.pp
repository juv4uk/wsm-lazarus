{$mode objfpc}{$H+}
program fpmake;

uses
  fpmkunit;

var
  P: TPackage;
  T: TTarget;

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
    P.SourcePath.Add('../../src');
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
    P.Dependencies.Add('wsm-source');
    P.SourcePath.Add('../../src');
    P.UnitPath.Add('../wsm-source/units/$(target)');
    T := P.Targets.AddUnit('wsm.domain.pas');
    T.Dependencies.AddUnit('wsm.source');

    Run;
  end;
end.
