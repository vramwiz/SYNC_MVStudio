unit MVPositionMotionFilterSettings;

// 既存アニメーションに加える位置モーションのホスト項目を登録する。
interface

uses MVPositionMotionTypes;

// フィルター登録時に1回呼び、選択肢名をDLL全体の寿命で保持する。
procedure RegisterMVPositionMotionSettings;
// 現在のホスト値を描画用の値へ複写する。
function ReadMVPositionMotionSettings: TMVPositionMotionSettings;

implementation

uses AviUtl2FilterTypes, PluginFilterTable;

var
  MotionGroup: TFILTER_ITEM_GROUP;
  KindItem, TargetItem: TFILTER_ITEM_SELECT;
  XItem, YItem, PeriodItem, DirectionItem, PhaseItem: TFILTER_ITEM_TRACK;
  InStrengthItem, HoldStrengthItem, OutStrengthItem: TFILTER_ITEM_TRACK;
  KindOptions: array[0..Ord(High(TMVPositionMotionKind)) + 1] of TFILTER_ITEM_SELECT_ITEM; // nil終端を含む。
  KindNames: array[TMVPositionMotionKind] of string;
  TargetOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;

procedure RegisterMVPositionMotionSettings;
var Defaults: TMVPositionMotionSettings; Kind: TMVPositionMotionKind;
begin
  Defaults := DefaultMVPositionMotion;
  for Kind := Low(TMVPositionMotionKind) to High(TMVPositionMotionKind) do
  begin
    KindNames[Kind] := MVPositionMotionName(Kind);
    KindOptions[Ord(Kind)].Name := PChar(KindNames[Kind]);
    KindOptions[Ord(Kind)].Value := Ord(Kind);
  end;
  TargetOptions[0].Name := '動かす単位に合わせる';
  TargetOptions[1].Name := 'フレーズ全体';
  TargetOptions[1].Value := Ord(mptPhrase);
  AddGroup(MotionGroup, '追加の位置モーション', 0);
  AddSelect(KindItem, '追加の動き', Defaults.Kind, @KindOptions[0]);
  AddSelect(TargetItem, '追加の適用対象', Defaults.Target, @TargetOptions[0]);
  AddTrack(XItem, '追加の横幅', Defaults.AmplitudeX, 0, 2000, 1);
  AddTrack(YItem, '追加の縦幅', Defaults.AmplitudeY, 0, 2000, 1);
  AddTrack(PeriodItem, '追加の周期', Defaults.Period, 0.05, 60, 0.01);
  AddTrack(DirectionItem, '追加の方向(度)', Defaults.Direction, -180, 180, 1);
  AddTrack(InStrengthItem, '追加の登場強さ(%)', Defaults.EntranceStrength * 100, 0, 1000, 1);
  AddTrack(HoldStrengthItem, '追加の表示中強さ(%)', Defaults.HoldStrength * 100, 0, 1000, 1);
  AddTrack(OutStrengthItem, '追加の退場強さ(%)', Defaults.ExitStrength * 100, 0, 1000, 1);
  AddTrack(PhaseItem, '追加の位相ずれ(度)', Defaults.PhaseStep, -360, 360, 1);
end;

function ReadMVPositionMotionSettings: TMVPositionMotionSettings;
begin
  Result := DefaultMVPositionMotion;
  Result.Kind := KindItem.Value;
  Result.Target := TargetItem.Value;
  Result.AmplitudeX := XItem.Value;
  Result.AmplitudeY := YItem.Value;
  Result.Period := PeriodItem.Value;
  Result.Direction := DirectionItem.Value;
  Result.EntranceStrength := InStrengthItem.Value / 100;
  Result.HoldStrength := HoldStrengthItem.Value / 100;
  Result.ExitStrength := OutStrengthItem.Value / 100;
  Result.PhaseStep := PhaseItem.Value;
end;

end.
