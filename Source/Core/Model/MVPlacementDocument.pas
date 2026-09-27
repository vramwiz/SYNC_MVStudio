unit MVPlacementDocument;

// ホストの歌詞・共通設定と、保存済みの個別配置を合成する。
interface

uses MVDocument;

// 保存文書のない歌詞に、出力画像へ収まる大きめの基準文字サイズを与える。
procedure FitMVInitialStyle(var Document: TMVDocument; Width, Height: Integer);
// ホストの文字・図形演出を検証して反映する。書式・歌詞・配置へは触れない。
procedure ApplyMVHostAnimation(var Document: TMVDocument; const Host: TMVDocument);
// 歌詞変更時は中央揃えの初期配置へ戻す。保存書式を保持し、演出は常にホストから反映する。
// 配列は再構成するため、元の保存文書と共有しない。
procedure ApplyMVHostDocument(var Document: TMVDocument; const Host: TMVDocument);

implementation

uses System.Math, MVTextUnits;

procedure FitMVInitialStyle(var Document: TMVDocument; Width, Height: Integer);
var I, CurrentLine, MaxLine, LineCount: Integer;
begin
  CurrentLine := 0;
  MaxLine := 0;
  LineCount := 1;
  for I := 0 to High(Document.Units) do
    if Document.Units[I].Text = #10 then
    begin
      MaxLine := Max(MaxLine, CurrentLine);
      CurrentLine := 0;
      Inc(LineCount);
    end
    else
      Inc(CurrentLine);
  MaxLine := Max(1, Max(MaxLine, CurrentLine));
  Document.Style.FontSize := EnsureRange(Min(Min(Height * 0.2, Width * 0.85 / MaxLine),
    Height * 0.7 / (LineCount * 1.3)), 4.0, 512.0);
end;

procedure ApplyMVHostAnimation(var Document: TMVDocument; const Host: TMVDocument);
begin
  ValidateMVAnimation(Host);
  Document.Hold := Host.Hold;
  Document.EntranceMotion := Host.EntranceMotion;
  Document.ExitMotion := Host.ExitMotion;
  Document.EntranceVisibility := Host.EntranceVisibility;
  Document.ExitVisibility := Host.ExitVisibility;
  Document.EntranceDirection := Host.EntranceDirection;
  Document.ExitDirection := Host.ExitDirection;
  Document.EntranceTiming := Host.EntranceTiming;
  Document.ExitTiming := Host.ExitTiming;
  Document.EntranceDelay := Host.EntranceDelay;
  Document.ExitDelay := Host.ExitDelay;
  Document.EntranceOrder := Host.EntranceOrder;
  Document.ExitOrder := Host.ExitOrder;
  Document.EntranceUnit := Host.EntranceUnit;
  Document.HoldUnit := Host.HoldUnit;
  Document.ExitUnit := Host.ExitUnit;
  Document.EntranceStrength := Host.EntranceStrength;
  Document.HoldStrength := Host.HoldStrength;
  Document.ExitStrength := Host.ExitStrength;
  Document.Amount := Host.Amount;
  Document.CurveAmount := Host.CurveAmount;
  Document.Period := Host.Period;
  Document.Shape := Host.Shape;
  Document.Appearance := Host.Appearance;
  Document.PositionMotion := Host.PositionMotion;
end;

procedure ApplyMVHostDocument(var Document: TMVDocument; const Host: TMVDocument);
begin
  SetMVText(Document, Host.Text);
  ApplyMVHostAnimation(Document, Host);
  ValidateMVDocument(Document);
end;

end.
