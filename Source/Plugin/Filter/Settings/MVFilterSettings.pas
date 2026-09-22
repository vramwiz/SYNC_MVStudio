unit MVFilterSettings;

// AviUtl2項目の登録と値のコピーだけを担当する。GUI項目ポインタをコンテキストへ保持しない。
interface

uses AviUtl2FilterTypes, MVDocument;

const
  MV_EFFECT_NAME = 'MVスタジオ'; // AviUtl2での効果名。
  MV_DATA_ITEM = '拡張データ'; // バージョン付き文書の保存先。

type
  TMVSettings = record
    Document: TMVDocument; // 両モード共通の歌詞・書式・演出。文字単位は更新時に構築する。
    Data: string; // 拡張文書。ホスト管理文字列から複写済み。
    Extended: Boolean; // Trueなら拡張データを使用する。
    X, Y: Double; // 標準モードの中央原点座標。
    EntranceTime, ExitTime: Double; // ホストが唯一の保存元となる所要秒数。
  end;

// テーブル構築後に1回呼ぶ。Skiaや編集画面は初期化しない。
procedure RegisterMVSettings(Legacy: TFilterItemButtonCallback; Targeted: TFilterItemButtonCallback2);
// 本体バージョンに合うボタンABIと公開項目を選ぶ。旧本体へ未対応の種別を渡さない。
procedure ConfigureMVEditorCallback(Version: Cardinal);
// ホストが更新した今回の値を所有可能なスナップショットへコピーする。
function ReadMVSettings: TMVSettings;
// 組版に影響する値だけを比較するためのキー。時間と標準座標は含めない。
function MVSettingsKey(const Settings: TMVSettings): string;

implementation

uses System.SysUtils, System.Math, PluginFilterTable, MVAnimationTypes, MVAnimationCatalog,
  MVShapeFilterSettings, MVTransitionTiming, MVAnimationSequence, MVAppearanceFilterSettings,
  MVPositionMotionFilterSettings;

var
  ModeItem, InItem, OutItem, HoldItem: TFILTER_ITEM_SELECT;
  InDirectionItem, OutDirectionItem: TFILTER_ITEM_SELECT; // 各演出の登場元・退場先または変形軸。
  InTimingItem, OutTimingItem: TFILTER_ITEM_SELECT; // 短い文章で選ぶ登場・退場の進み方。
  InOrderItem, OutOrderItem, UnitItem: TFILTER_ITEM_SELECT; // 開始順と動かすまとまり。
  TextItem, FontItem, DataItem: TFILTER_ITEM_STRING;
  XItem, YItem, SizeItem, OutlineItem, SpacingItem, LineItem: TFILTER_ITEM_TRACK;
  InTimeItem, OutTimeItem, AmountItem, PeriodItem: TFILTER_ITEM_TRACK;
  InStrengthItem, HoldStrengthItem, OutStrengthItem: TFILTER_ITEM_TRACK; // 各状態の強さ倍率。100%が従来値。
  CurveAmountItem: TFILTER_ITEM_TRACK; // 波・S字・ジグザグ軌道の膨らみ。
  InDelayItem, OutDelayItem: TFILTER_ITEM_TRACK; // 選んだ動作単位の開始間隔。既存の項目名は維持する。
  ColorItem, EdgeColorItem: TFILTER_ITEM_COLOR;
  ShadowItem, BoldItem, ItalicItem: TFILTER_ITEM_CHECK;
  EditorItem: TFILTER_ITEM_BUTTON;
  StyleGroup, TimeGroup, MotionGroup, DataGroup: TFILTER_ITEM_GROUP;
  ModeOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  TransitionOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // カタログから生成するnil終端の登場・退場一覧。
  HoldOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // カタログから生成するnil終端の表示中一覧。
  TransitionNames: TArray<string>; // ホストが参照する名前をDLL寿命中保持する。
  HoldNames: TArray<string>; // 表示中の名前もホストへ渡した後は変更しない。
  TimingOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // 登場と退場が共有するnil終端の曲線一覧。
  TimingNames: TArray<string>; // ホストへ渡した文章をDLL寿命中保持する。
  DirectionOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM; // 上下左右とnil終端。
  DirectionNames: array[TMVAnimationDirection] of string; // ホストへ渡す名前の寿命を保持する。
  OrderOptions: array[0..5] of TFILTER_ITEM_SELECT_ITEM; // 5種類の開始順とnil終端。
  OrderNames: array[TMVAnimationOrder] of string; // 選択肢の名前をDLL寿命中保持する。
  UnitOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM; // 4種類の動作単位とnil終端。
  UnitNames: array[TMVAnimationUnit] of string; // 選択肢の名前をDLL寿命中保持する。
  StyleHide: array[0..11] of TFILTER_ITEM_HIDE_RULE; // 拡張モードでは旧座標・書式を表示しない。
  LegacyEditor: TFilterItemButtonCallback;
  TargetedEditor: TFilterItemButtonCallback2;

procedure ConfigureMVEditorCallback(Version: Cardinal);
begin
  // 2.1.3aはhideruleを認識せず、フィルター全体の登録を拒否する。
  // 使用SDKに対応する2.1.10以降でのみ公開し、旧本体では互換設定の折りたたみを使う。
  SetFilterHideRulesEnabled(Version >= 2011000);
  // callback2は2026-09-19 / AviUtl2 2.1.10から利用可能。
  if Version >= 2011000 then
  begin
    EditorItem.Callback := nil;
    EditorItem.Callback2 := TargetedEditor;
  end
  else
  begin
    EditorItem.Callback := LegacyEditor;
    EditorItem.Callback2 := nil;
  end;
end;

procedure BuildAnimationChoices(Kind: TMVAnimationKind; out Items: TArray<TFILTER_ITEM_SELECT_ITEM>;
  out Names: TArray<string>);
var I, Count: Integer; Item: TMVAnimationDescriptor;
begin
  Count := MVAnimationCount(Kind);
  SetLength(Names, Count);
  SetLength(Items, Count + 1);
  for I := 0 to Count - 1 do
  begin
    Item := MVAnimationAt(Kind, I);
    Names[I] := Item.Name;
    Items[I].Name := PChar(Names[I]);
    Items[I].Value := Item.ID;
  end;
  // SDKが末尾を読み越さないよう、未使用の最終項目を明示的に終端とする。
  Items[Count] := Default(TFILTER_ITEM_SELECT_ITEM);
end;
procedure BuildTimingChoices;
var I: Integer;
begin
  SetLength(TimingNames, MVTimingCount);
  SetLength(TimingOptions, MVTimingCount + 1);
  for I := 0 to MVTimingCount - 1 do
  begin
    TimingNames[I] := MVTimingName(I);
    TimingOptions[I].Name := PChar(TimingNames[I]);
    TimingOptions[I].Value := I;
  end;
  TimingOptions[MVTimingCount] := Default(TFILTER_ITEM_SELECT_ITEM);
end;

procedure RegisterMVSettings(Legacy: TFilterItemButtonCallback; Targeted: TFilterItemButtonCallback2);
const LegacyNames: array[0..11] of PWideChar = ('X', 'Y', 'フォント', '文字サイズ', '文字色', '太字', '斜体',
  '縁幅', '縁色', '影', '字間', '行間');
var I: Integer; Direction: TMVAnimationDirection; Order: TMVAnimationOrder; MotionUnit: TMVAnimationUnit;
begin
  ModeOptions[0].Name := '標準';
  ModeOptions[1].Name := '拡張';
  ModeOptions[1].Value := 1;
  BuildAnimationChoices(makTransition, TransitionOptions, TransitionNames);
  BuildAnimationChoices(makHold, HoldOptions, HoldNames);
  BuildTimingChoices;
  for Order := Low(TMVAnimationOrder) to High(TMVAnimationOrder) do
  begin
    OrderNames[Order] := MVAnimationOrderName(Order);
    OrderOptions[Ord(Order)].Name := PChar(OrderNames[Order]);
    OrderOptions[Ord(Order)].Value := Ord(Order);
  end;
  for MotionUnit := Low(TMVAnimationUnit) to High(TMVAnimationUnit) do
  begin
    UnitNames[MotionUnit] := MVAnimationUnitName(MotionUnit);
    UnitOptions[Ord(MotionUnit)].Name := PChar(UnitNames[MotionUnit]);
    UnitOptions[Ord(MotionUnit)].Value := Ord(MotionUnit);
  end;
  for Direction := Low(TMVAnimationDirection) to High(TMVAnimationDirection) do
  begin
    DirectionNames[Direction] := MVAnimationDirectionName(Direction);
    DirectionOptions[Ord(Direction)].Name := PChar(DirectionNames[Direction]);
    DirectionOptions[Ord(Direction)].Value := Ord(Direction);
  end;
  AddSelect(ModeItem, '編集モード', 1, @ModeOptions[0]);
  LegacyEditor := Legacy;
  TargetedEditor := Targeted;
  AddButton(EditorItem, '拡張編集', Legacy);
  ConfigureMVEditorCallback(0);
  AddString(TextItem, '歌詞', '');
  TextItem.ItemType := 'text'; // SDKの複数行項目はstringと同じ3ポインタ配置。
  AddGroup(TimeGroup, '共通の時間', 1);
  AddTrack(InTimeItem, '登場時間', 0.3, 0, 10, 0.01);
  AddTrack(OutTimeItem, '退場時間', 0.3, 0, 10, 0.01);
  AddGroup(MotionGroup, '共通のアニメーション', 1);
  AddSelect(UnitItem, '動かす単位', Ord(mauCharacter), @UnitOptions[0]);
  // 既存プロジェクトの項目名を維持する。名称に「標準」があっても拡張に適用する。
  AddSelect(InItem, '標準の登場', 0, @TransitionOptions[0]);
  AddSelect(InDirectionItem, '登場方向', Ord(madDown), @DirectionOptions[0]);
  AddSelect(InTimingItem, '登場の動き方', MV_TIMING_DEFAULT, @TimingOptions[0]);
  AddTrack(InDelayItem, '登場の文字遅延', 0, 0, 1, 0.01);
  AddSelect(InOrderItem, '登場順', Ord(maoForward), @OrderOptions[0]);
  AddTrack(InStrengthItem, '登場の強さ(%)', 100, 0, 1000, 1);
  AddSelect(HoldItem, '標準の表示中', 0, @HoldOptions[0]);
  AddTrack(HoldStrengthItem, '表示中の強さ(%)', 100, 0, 1000, 1);
  AddSelect(OutItem, '標準の退場', 0, @TransitionOptions[0]);
  AddSelect(OutDirectionItem, '退場方向', Ord(madUp), @DirectionOptions[0]);
  AddSelect(OutTimingItem, '退場の動き方', MV_TIMING_DEFAULT, @TimingOptions[0]);
  AddTrack(OutDelayItem, '退場の文字遅延', 0, 0, 1, 0.01);
  AddSelect(OutOrderItem, '退場順', Ord(maoForward), @OrderOptions[0]);
  AddTrack(OutStrengthItem, '退場の強さ(%)', 100, 0, 1000, 1);
  AddTrack(AmountItem, '強さ', 60, 0, 2000, 1);
  AddTrack(CurveAmountItem, '曲がりの強さ', MV_DEFAULT_CURVE_AMOUNT, 0, 2000, 1);
  AddTrack(PeriodItem, '周期', 2, 0.05, 60, 0.01);
  RegisterMVPositionMotionSettings;
  RegisterMVShapeSettings;
  RegisterMVAppearanceSettings;
  AddGroup(StyleGroup, '標準互換の文字設定', 0);
  AddTrack(XItem, 'X', 0, -32768, 32768, 1);
  AddTrack(YItem, 'Y', 0, -32768, 32768, 1);
  AddString(FontItem, 'フォント', 'Yu Gothic UI');
  AddTrack(SizeItem, '文字サイズ', 100, 4, 512, 1);
  AddColor(ColorItem, '文字色', 255, 255, 255);
  AddCheck(BoldItem, '太字', 0);
  AddCheck(ItalicItem, '斜体', 0);
  AddTrack(OutlineItem, '縁幅', 2, 0, 32, 0.1);
  AddColor(EdgeColorItem, '縁色', 0, 0, 0);
  AddCheck(ShadowItem, '影', 0);
  AddTrack(SpacingItem, '字間', 0, -256, 512, 0.1);
  AddTrack(LineItem, '行間', 0, -256, 512, 0.1);
  for I := 0 to High(StyleHide) do AddHideRule(StyleHide[I], LegacyNames[I], '編集モード', 1);
  AddGroup(DataGroup, '拡張の保存データ', 0);
  AddString(DataItem, MV_DATA_ITEM, '');
end;

function ReadMVSettings: TMVSettings;
begin
  Result := Default(TMVSettings);
  Result.Document := DefaultMVDocument;
  Result.Extended := ModeItem.Value = 1;
  Result.Data := string(DataItem.Value);
  Result.Document.Text := string(TextItem.Value);
  Result.Document.Style.FontName := string(FontItem.Value);
  Result.Document.Style.FontSize := SizeItem.Value;
  Result.Document.Style.Color := $FF000000 or Cardinal(ColorItem.R) shl 16 or Cardinal(ColorItem.G) shl 8 or ColorItem.B;
  Result.Document.Style.OutlineColor := $FF000000 or Cardinal(EdgeColorItem.R) shl 16 or
    Cardinal(EdgeColorItem.G) shl 8 or EdgeColorItem.B;
  Result.Document.Style.OutlineWidth := OutlineItem.Value;
  Result.Document.Style.Bold := BoldItem.Value <> 0;
  Result.Document.Style.Italic := ItalicItem.Value <> 0;
  Result.Document.Style.Shadow := ShadowItem.Value <> 0;
  Result.Document.Style.Spacing := SpacingItem.Value;
  Result.Document.Style.LineSpacing := LineItem.Value;
  Result.Document.Entrance := InItem.Value;
  Result.Document.ExitEffect := OutItem.Value;
  Result.Document.EntranceDirection := InDirectionItem.Value;
  Result.Document.ExitDirection := OutDirectionItem.Value;
  Result.Document.EntranceTiming := InTimingItem.Value;
  Result.Document.ExitTiming := OutTimingItem.Value;
  NormalizeMVDirection(Result.Document.Entrance, Result.Document.EntranceDirection, False);
  NormalizeMVDirection(Result.Document.ExitEffect, Result.Document.ExitDirection, True);
  Result.Document.Hold := HoldItem.Value;
  Result.Document.EntranceDelay := InDelayItem.Value;
  Result.Document.ExitDelay := OutDelayItem.Value;
  Result.Document.EntranceOrder := InOrderItem.Value;
  Result.Document.ExitOrder := OutOrderItem.Value;
  Result.Document.AnimationUnit := UnitItem.Value;
  Result.Document.EntranceStrength := InStrengthItem.Value / 100;
  Result.Document.HoldStrength := HoldStrengthItem.Value / 100;
  Result.Document.ExitStrength := OutStrengthItem.Value / 100;
  Result.Document.Amount := AmountItem.Value;
  Result.Document.CurveAmount := CurveAmountItem.Value;
  Result.Document.Period := PeriodItem.Value;
  Result.Document.Shape := ReadMVShapeSettings;
  Result.Document.Appearance := ReadMVAppearanceSettings;
  Result.Document.PositionMotion := ReadMVPositionMotionSettings;
  Result.X := XItem.Value;
  Result.Y := YItem.Value;
  Result.EntranceTime := InTimeItem.Value;
  Result.ExitTime := OutTimeItem.Value;
end;

function MVSettingsKey(const Settings: TMVSettings): string;
var D: TMVDocument;
begin
  D := Settings.Document;
  Result := Format('%d:%s|%s|%.9g|%u|%u|%.9g|%d%d%d|%.9g|%.9g',
    [Length(D.Text), D.Text, D.Style.FontName, D.Style.FontSize, D.Style.Color, D.Style.OutlineColor,
    D.Style.OutlineWidth, Ord(D.Style.Bold), Ord(D.Style.Italic), Ord(D.Style.Shadow), D.Style.Spacing,
    D.Style.LineSpacing], TFormatSettings.Invariant);
  if Settings.Extended and (Settings.Data <> '') then Result := 'E:' + Settings.Data + '|' + Result;
end;

end.
