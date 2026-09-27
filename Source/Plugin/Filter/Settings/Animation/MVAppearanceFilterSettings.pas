unit MVAppearanceFilterSettings;

// 装飾の時間変化・光の走査・残像のホスト項目を登録する。文字の静的書式とは分けて扱う。
interface

uses MVAppearanceTypes;

// フィルター登録時に1回呼び、項目と名前の寿命をDLL全体で保つ。
procedure RegisterMVAppearanceSettings;
// 今回のホスト値を所有可能な設定レコードへ複写する。
function ReadMVAppearanceSettings: TMVAppearanceSettings;

implementation

uses AviUtl2FilterTypes, PluginFilterTable;

var
  DecorationGroup, SweepGroup, EchoGroup: TFILTER_ITEM_GROUP;
  ColorModeItem: TFILTER_ITEM_SELECT;
  ColorItem: TFILTER_ITEM_COLOR;
  ColorAmountItem: TFILTER_ITEM_TRACK;
  GlowPulseItem: TFILTER_ITEM_TRACK;
  ChromaticSwingItem: TFILTER_ITEM_TRACK;
  SweepModeItem: TFILTER_ITEM_SELECT;
  SweepColorItem: TFILTER_ITEM_COLOR;
  SweepAmountItem: TFILTER_ITEM_TRACK;
  SweepWidthItem: TFILTER_ITEM_TRACK;
  SweepAngleItem: TFILTER_ITEM_TRACK;
  SweepPeriodItem: TFILTER_ITEM_TRACK;
  EchoCountItem: TFILTER_ITEM_TRACK;
  EchoIntervalItem: TFILTER_ITEM_TRACK;
  EchoTransparencyItem: TFILTER_ITEM_TRACK;
  EchoDecayItem: TFILTER_ITEM_TRACK;
  ColorOptions, SweepOptions: array[0..3] of TFILTER_ITEM_SELECT_ITEM; // 3種類とnil終端。

procedure RegisterMVAppearanceSettings;
var Defaults: TMVAppearanceSettings;
begin
  Defaults := DefaultMVAppearance;
  ColorOptions[0].Name := 'なし';
  ColorOptions[1].Name := '指定色と往復';
  ColorOptions[1].Value := 1;
  ColorOptions[2].Name := '虹色が巡る';
  ColorOptions[2].Value := 2;
  SweepOptions[0].Name := 'なし';
  SweepOptions[1].Name := '繰り返す';
  SweepOptions[1].Value := 1;
  SweepOptions[2].Name := '一度だけ';
  SweepOptions[2].Value := 2;
  AddGroup(DecorationGroup, '装飾', 0);
  AddSelect(ColorModeItem, '装飾 色変化', Defaults.ColorMode, @ColorOptions[0]);
  AddColor(ColorItem, '装飾 変化色', (Defaults.Color shr 16) and $FF,
    (Defaults.Color shr 8) and $FF, Defaults.Color and $FF);
  AddTrack(ColorAmountItem, '装飾 変化量(%)', Defaults.ColorAmount * 100, 0, 100, 1);
  AddTrack(GlowPulseItem, '装飾 発光脈動(%)', Defaults.GlowPulse * 100, 0, 100, 1);
  AddTrack(ChromaticSwingItem, '装飾 色ずれ幅', Defaults.ChromaticSwing, 0, 64, 0.5);
  AddGroup(SweepGroup, '光', 0);
  AddSelect(SweepModeItem, '光 走査', Defaults.SweepMode, @SweepOptions[0]);
  AddColor(SweepColorItem, '光 色', (Defaults.SweepColor shr 16) and $FF,
    (Defaults.SweepColor shr 8) and $FF, Defaults.SweepColor and $FF);
  AddTrack(SweepAmountItem, '光 強さ(%)', Defaults.SweepAmount * 100, 0, 100, 1);
  AddTrack(SweepWidthItem, '光 半幅', Defaults.SweepWidth, 1, 1024, 1);
  AddTrack(SweepAngleItem, '光 角度', Defaults.SweepAngle, -180, 180, 1);
  AddTrack(SweepPeriodItem, '光 時間', Defaults.SweepPeriod, 0.05, 60, 0.01);
  AddGroup(EchoGroup, '残像', 0);
  AddTrack(EchoCountItem, '残像 枚数', Defaults.EchoCount, 0, 8, 1);
  AddTrack(EchoIntervalItem, '残像 間隔', Defaults.EchoInterval, 0.005, 1, 0.005);
  AddTrack(EchoTransparencyItem, '残像 透明度(%)', (1 - Defaults.EchoOpacity) * 100, 0, 100, 1);
  AddTrack(EchoDecayItem, '残像 減衰(%)', Defaults.EchoDecay * 100, 0, 100, 1);
end;

function ReadMVAppearanceSettings: TMVAppearanceSettings;
begin
  Result := DefaultMVAppearance;
  Result.ColorMode := ColorModeItem.Value;
  Result.Color := $FF000000 or Cardinal(ColorItem.R) shl 16 or
    Cardinal(ColorItem.G) shl 8 or ColorItem.B;
  Result.ColorAmount := ColorAmountItem.Value / 100;
  Result.GlowPulse := GlowPulseItem.Value / 100;
  Result.ChromaticSwing := ChromaticSwingItem.Value;
  Result.SweepMode := SweepModeItem.Value;
  Result.SweepColor := $FF000000 or Cardinal(SweepColorItem.R) shl 16 or
    Cardinal(SweepColorItem.G) shl 8 or SweepColorItem.B;
  Result.SweepAmount := SweepAmountItem.Value / 100;
  Result.SweepWidth := SweepWidthItem.Value;
  Result.SweepAngle := SweepAngleItem.Value;
  Result.SweepPeriod := SweepPeriodItem.Value;
  Result.EchoCount := Round(EchoCountItem.Value);
  Result.EchoInterval := EchoIntervalItem.Value;
  Result.EchoOpacity := 1 - EchoTransparencyItem.Value / 100;
  Result.EchoDecay := EchoDecayItem.Value / 100;
end;

end.
