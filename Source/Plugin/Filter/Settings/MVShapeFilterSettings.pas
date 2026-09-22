unit MVShapeFilterSettings;

// 図形演出専用のAviUtl2項目を登録し、所有可能な設定値へ複写する。
interface

uses MVShapeTypes;

// フィルターの項目登録中に1回呼ぶ。名前と選択肢はDLL寿命中保持する。
procedure RegisterMVShapeSettings;
// 今回のホスト値を返す。文書へ適用する際に共通の検証を通す。
function ReadMVShapeSettings: TMVShapeSettings;

implementation

uses AviUtl2FilterTypes, PluginFilterTable, MVAnimationTypes;

var
  ShapeGroup: TFILTER_ITEM_GROUP;
  EffectItem, DirectionItem, LayerItem: TFILTER_ITEM_SELECT;
  ColorItem: TFILTER_ITEM_COLOR;
  OpacityItem, PaddingItem, LineWidthItem, PeriodItem: TFILTER_ITEM_TRACK;
  EffectOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // 末尾にnil終端を置く。
  EffectNames: TArray<string>; // ホストが参照する選択肢名を保持する。
  DirectionOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM; // 上下左右とnil終端。
  DirectionNames: array[TMVAnimationDirection] of string; // 動的文字列の寿命を保持する。
  LayerOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM; // 背面・前面とnil終端。

procedure RegisterMVShapeSettings;
var I: Integer; Defaults: TMVShapeSettings; Direction: TMVAnimationDirection;
begin
  Defaults := DefaultMVShapeSettings;
  SetLength(EffectNames, MVShapeCount);
  SetLength(EffectOptions, MVShapeCount + 1);
  for I := 0 to MVShapeCount - 1 do
  begin
    EffectNames[I] := MVShapeName(I);
    EffectOptions[I].Name := PChar(EffectNames[I]);
    EffectOptions[I].Value := I;
  end;
  EffectOptions[MVShapeCount] := Default(TFILTER_ITEM_SELECT_ITEM);
  for Direction := Low(TMVAnimationDirection) to High(TMVAnimationDirection) do
  begin
    DirectionNames[Direction] := MVAnimationDirectionName(Direction);
    DirectionOptions[Ord(Direction)].Name := PChar(DirectionNames[Direction]);
    DirectionOptions[Ord(Direction)].Value := Ord(Direction);
  end;
  LayerOptions[0].Name := '背面';
  LayerOptions[1].Name := '前面';
  LayerOptions[1].Value := 1;
  AddGroup(ShapeGroup, '図形アニメーション', 1);
  AddSelect(EffectItem, '図形演出', Defaults.EffectID, @EffectOptions[0]);
  AddColor(ColorItem, '図形色', (Defaults.Color shr 16) and $FF, (Defaults.Color shr 8) and $FF,
    Defaults.Color and $FF);
  AddTrack(OpacityItem, '図形不透明度', Defaults.Opacity * 100, 0, 100, 1);
  AddTrack(PaddingItem, '図形余白', Defaults.Padding, 0, 512, 1);
  AddTrack(LineWidthItem, '図形線幅', Defaults.LineWidth, 0.5, 64, 0.5);
  AddTrack(PeriodItem, '図形周期', Defaults.Period, 0.05, 60, 0.01);
  AddSelect(DirectionItem, '図形方向', Defaults.Direction, @DirectionOptions[0]);
  AddSelect(LayerItem, '図形の重なり', Ord(Defaults.Foreground), @LayerOptions[0]);
end;

function ReadMVShapeSettings: TMVShapeSettings;
begin
  Result := DefaultMVShapeSettings;
  Result.EffectID := EffectItem.Value;
  Result.Color := $FF000000 or Cardinal(ColorItem.R) shl 16 or Cardinal(ColorItem.G) shl 8 or ColorItem.B;
  Result.Opacity := OpacityItem.Value / 100;
  Result.Padding := PaddingItem.Value;
  Result.LineWidth := LineWidthItem.Value;
  Result.Period := PeriodItem.Value;
  Result.Direction := DirectionItem.Value;
  Result.Foreground := LayerItem.Value = 1;
end;

end.
