unit MVPlacementDocument;

// ホストの歌詞・共通設定と、保存済みの個別配置を合成する。
interface

uses MVDocument;

// ホストの文字・図形演出を検証して反映する。書式・歌詞・配置へは触れない。
procedure ApplyMVHostAnimation(var Document: TMVDocument; const Host: TMVDocument);
// 共通する前後の文字配置を残して歌詞を更新する。編集画面へ移行済みの書式は保持し、演出は常にホストから反映する。
// 配列は再構成するため、元の保存文書と共有しない。
procedure ApplyMVHostDocument(var Document: TMVDocument; const Host: TMVDocument);

implementation

uses MVTextUnits;

procedure ApplyMVHostAnimation(var Document: TMVDocument; const Host: TMVDocument);
begin
  ValidateMVAnimation(Host);
  Document.Entrance := Host.Entrance;
  Document.Hold := Host.Hold;
  Document.ExitEffect := Host.ExitEffect;
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
  Document.AnimationUnit := Host.AnimationUnit;
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
  if not Document.EditorSettings then
    Document.Style := Host.Style;
  ApplyMVHostAnimation(Document, Host);
  ValidateMVDocument(Document);
end;

end.
