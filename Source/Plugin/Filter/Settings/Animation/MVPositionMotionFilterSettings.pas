unit MVPositionMotionFilterSettings;

// 既存アニメーションに加える位置モーションのホスト項目を登録する。
interface

uses MVPositionMotionTypes;

// フィルター登録時に1回呼び、選択肢名をDLL全体の寿命で保持する。
procedure RegisterMVPositionMotionSettings;
// 現在のホスト値を描画用の値へ複写する。
function ReadMVPositionMotionSettings: TMVPositionMotionSettings;

implementation

uses AviUtl2FilterTypes, PluginFilterTable, MVAnimationSequence;

var
  MotionGroup: TFILTER_ITEM_GROUP;
  KindItem, UnitItem: TFILTER_ITEM_SELECT;
  XItem, YItem, DirectionItem, PhaseItem: TFILTER_ITEM_TRACK;
  InStrengthItem, HoldStrengthItem, OutStrengthItem: TFILTER_ITEM_TRACK;
  KindOptions: array[0..Ord(High(TMVPositionMotionKind)) + 1] of TFILTER_ITEM_SELECT_ITEM; // nil終端を含む。
  KindNames: array[TMVPositionMotionKind] of string;
  UnitOptions: array[0..Ord(High(TMVAnimationUnit)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  UnitNames: array[TMVAnimationUnit] of string;

procedure RegisterMVPositionMotionSettings;
var Defaults: TMVPositionMotionSettings; Kind: TMVPositionMotionKind; MotionUnit: TMVAnimationUnit;
begin
  Defaults := DefaultMVPositionMotion;
  for Kind := Low(TMVPositionMotionKind) to High(TMVPositionMotionKind) do
  begin
    KindNames[Kind] := MVPositionMotionName(Kind);
    KindOptions[Ord(Kind)].Name := PChar(KindNames[Kind]);
    KindOptions[Ord(Kind)].Value := Ord(Kind);
  end;
  for MotionUnit := Low(TMVAnimationUnit) to High(TMVAnimationUnit) do
  begin
    UnitNames[MotionUnit] := MVAnimationUnitName(MotionUnit);
    UnitOptions[Ord(MotionUnit)].Name := PChar(UnitNames[MotionUnit]);
    UnitOptions[Ord(MotionUnit)].Value := Ord(MotionUnit);
  end;
  AddGroup(MotionGroup, '非同期', 0);
  AddSelect(KindItem, '非同期 動き', Defaults.Kind, @KindOptions[0]);
  AddSelect(UnitItem, '非同期 単位', Defaults.UnitMode, @UnitOptions[0]);
  AddTrack(XItem, '非同期 横幅', Defaults.AmplitudeX, 0, 2000, 1);
  AddTrack(YItem, '非同期 縦幅', Defaults.AmplitudeY, 0, 2000, 1);
  AddTrack(DirectionItem, '非同期 方向(度)', Defaults.Direction, -180, 180, 1);
  AddTrack(InStrengthItem, '非同期 前強さ(%)', Defaults.EntranceStrength * 100, 0, 1000, 1);
  AddTrack(HoldStrengthItem, '非同期 中強さ(%)', Defaults.HoldStrength * 100, 0, 1000, 1);
  AddTrack(OutStrengthItem, '非同期 後強さ(%)', Defaults.ExitStrength * 100, 0, 1000, 1);
  AddTrack(PhaseItem, '非同期 位相(度)', Defaults.PhaseStep, -360, 360, 1);
end;

function ReadMVPositionMotionSettings: TMVPositionMotionSettings;
begin
  Result := DefaultMVPositionMotion;
  Result.Kind := KindItem.Value;
  Result.UnitMode := UnitItem.Value;
  Result.AmplitudeX := XItem.Value;
  Result.AmplitudeY := YItem.Value;
  Result.Direction := DirectionItem.Value;
  Result.EntranceStrength := InStrengthItem.Value / 100;
  Result.HoldStrength := HoldStrengthItem.Value / 100;
  Result.ExitStrength := OutStrengthItem.Value / 100;
  Result.PhaseStep := PhaseItem.Value;
end;

end.
