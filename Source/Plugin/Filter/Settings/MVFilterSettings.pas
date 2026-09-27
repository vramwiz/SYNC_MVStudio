unit MVFilterSettings;

// AviUtl2項目の登録と値のコピーだけを担当する。GUI項目ポインタをコンテキストへ保持しない。
interface

uses AviUtl2FilterTypes, MVDocument;

const
  MV_EFFECT_NAME = 'MVスタジオ'; // AviUtl2での効果名。
  MV_DATA_ITEM = '拡張データ'; // 既存プロジェクトの保存名を維持する内部項目。

type
  TMVSettings = record
    Document: TMVDocument; // 歌詞・演出と新規文書の既定書式。
    Data: string; // 配置と書式の保存文書。ホスト管理文字列から複写済み。
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
  TextItem, DataItem: TFILTER_ITEM_STRING; // ホスト所有の文字列。読取時に複写する。
  EditorItem: TFILTER_ITEM_BUTTON; // 対象を確定して専用編集画面を開く入口。
  DataGroup: TFILTER_ITEM_GROUP; // 内部保存データの折りたたみ見出し。
  DataHide: TFILTER_ITEM_HIDE_RULE; // 対応本体では旧保存文字列を表示しない。
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
begin
  LegacyEditor := Legacy;
  TargetedEditor := Targeted;
  AddButton(EditorItem, '編集', Legacy);
  ConfigureMVEditorCallback(0);
  AddString(TextItem, '歌詞', '');
  TextItem.ItemType := 'text'; // SDKの複数行項目はstringと同じ3ポインタ配置。
  RegisterMVAnimationSettings;
  RegisterMVPositionMotionSettings;
  RegisterMVExitAnimationSettings;
  RegisterMVShapeSettings;
  RegisterMVAppearanceSettings;
  AddGroup(DataGroup, '保存データ', 0);
  AddString(DataItem, MV_DATA_ITEM, '');
  AddHideRule(DataHide, MV_DATA_ITEM, nil, 0);
end;

function ReadMVSettings: TMVSettings;
begin
  Result := Default(TMVSettings);
  Result.Document := DefaultMVDocument;
  Result.Data := string(DataItem.Value);
  Result.Document.Text := string(TextItem.Value);
  ReadMVAnimationSettings(Result.Document, Result.EntranceTime, Result.ExitTime);
  Result.Document.Shape := ReadMVShapeSettings;
  Result.Document.Appearance := ReadMVAppearanceSettings;
  Result.Document.PositionMotion := ReadMVPositionMotionSettings;
  // UIの単一BPMを各評価器の秒単位周期へ変換して渡す。
  Result.Document.Shape.Period := Result.Document.Period;
  Result.Document.Appearance.Period := Result.Document.Period;
  Result.Document.PositionMotion.Period := Result.Document.Period;
end;

function MVSettingsKey(const Settings: TMVSettings): string;
begin
  Result := Format('%d:%s|%s', [Length(Settings.Document.Text), Settings.Document.Text, Settings.Data]);
end;

end.
