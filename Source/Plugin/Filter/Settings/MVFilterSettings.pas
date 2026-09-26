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

uses System.SysUtils, PluginFilterTable, MVAnimationFilterSettings, MVShapeFilterSettings,
  MVAppearanceFilterSettings, MVPositionMotionFilterSettings;

var
  ModeItem: TFILTER_ITEM_SELECT; // 標準互換設定と拡張文書のどちらを使用するか。
  TextItem, FontItem, DataItem: TFILTER_ITEM_STRING; // ホスト所有の文字列。読取時に複写する。
  XItem, YItem, SizeItem, OutlineItem, SpacingItem, LineItem: TFILTER_ITEM_TRACK; // 標準互換の座標と組版値。
  ColorItem, EdgeColorItem: TFILTER_ITEM_COLOR; // 標準互換の文字色と縁色。
  ShadowItem, BoldItem, ItalicItem: TFILTER_ITEM_CHECK; // 標準互換の書式切替。
  EditorItem: TFILTER_ITEM_BUTTON; // 対象を確定して専用編集画面を開く入口。
  StyleGroup, DataGroup: TFILTER_ITEM_GROUP; // 互換設定と内部保存データの折りたたみ見出し。
  ModeOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM; // 2モードとnil終端。DLL寿命中保持する。
  StyleHide: array[0..11] of TFILTER_ITEM_HIDE_RULE; // 拡張モードでは旧座標・書式を表示しない。
  LegacyEditor: TFilterItemButtonCallback; // callback2未対応の本体へ渡す通知先。
  TargetedEditor: TFilterItemButtonCallback2; // 対象情報を受け取れる本体へ渡す通知先。

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

procedure RegisterMVSettings(Legacy: TFilterItemButtonCallback; Targeted: TFilterItemButtonCallback2);
const LegacyNames: array[0..11] of PWideChar = ('X', 'Y', 'フォント', '文字サイズ', '文字色', '太字', '斜体',
  '縁幅', '縁色', '影', '字間', '行間');
var I: Integer;
begin
  ModeOptions[0].Name := '標準';
  ModeOptions[1].Name := '拡張';
  ModeOptions[1].Value := 1;
  AddSelect(ModeItem, '編集モード', 1, @ModeOptions[0]);
  LegacyEditor := Legacy;
  TargetedEditor := Targeted;
  AddButton(EditorItem, '拡張編集', Legacy);
  ConfigureMVEditorCallback(0);
  AddString(TextItem, '歌詞', '');
  TextItem.ItemType := 'text'; // SDKの複数行項目はstringと同じ3ポインタ配置。
  RegisterMVAnimationSettings;
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
  RegisterMVLegacyTransitionSettings;
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
  ReadMVAnimationSettings(Result.Document, Result.EntranceTime, Result.ExitTime);
  Result.Document.Shape := ReadMVShapeSettings;
  Result.Document.Appearance := ReadMVAppearanceSettings;
  Result.Document.PositionMotion := ReadMVPositionMotionSettings;
  Result.X := XItem.Value;
  Result.Y := YItem.Value;
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
