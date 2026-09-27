unit MVDocument;

// 1フレーズの保存可能な値を定義する。ホストのポインタと描画資源は保持しない。
interface

uses System.SysUtils, System.UITypes, MVShapeTypes, MVStyleTypes, MVAppearanceTypes, MVPositionMotionTypes;

const
  MV_DOCUMENT_VERSION = 11; // 状態ごとに独立した動作単位を保存する。
  MV_MAX_TEXT_LENGTH = 1024; // 異常設定による組版の過大な負荷を抑える。
  MV_MAX_UNITS = 512; // 1フレーズ内の配置要素数の上限。
  MV_MAX_DATA_LENGTH = 32767; // ホストの単行文字列項目へ保存する上限。
  MV_DEFAULT_CURVE_AMOUNT = 30; // 波・S字・ジグザグ軌道の既定の膨らみ。出力ピクセル単位。

type
  TMVStyle = MVStyleTypes.TMVStyle;

  TMVPlacement = record
    Text: string; // 表示上の文字単位。改行も1要素として保持する。
    X, Y: Single; // 出力画像の中央を原点とする配置オフセット。
    Scale: Single; // 個別倍率。1が基準サイズ。
    ScaleX, ScaleY: Single; // 縦横独立倍率。旧保存データでは各1として復元する。
    Shear: Single; // 回転前の横せん断。回転文字をまとめて縦横拡縮しても形状を保つ。
    Angle: Single; // 個別回転角度。度単位。
    Style: TMVStyle; // StyleFieldsに含まれる項目だけ共通書式を上書きする。
    StyleFields: TMVStyleFields; // 変更していない項目は共通書式を継承する。
    AnimationGroup: Integer; // 永続的な動作グループ。0は未登録、1..MV_MAX_UNITSは同時に動く集合。
    Positioned: Boolean; // Falseなら組版結果の位置を使用する。
  end;


  TMVDocument = record
    EditorSettings: Boolean; // 旧文書との保存形式互換用。書式の管理先は常に保存文書。
    Text: string; // 1フレーズ全体の歌詞。LFで改行を保持する。
    Style: TMVStyle; // フレーズ共通の書式。
    Units: TArray<TMVPlacement>; // 編集画面で扱う文字単位の配置。
    Hold: Integer; // 表示中演出の安定した識別値。
    EntranceMotion, ExitMotion: Integer; // 動きの固定ID。0は動かさない。
    EntranceVisibility, ExitVisibility: Integer; // 見え方の固定ID。0は表示効果なし。
    EntranceDirection: Integer; // 登場元または変形軸。上0・下1・左2・右3。
    ExitDirection: Integer; // 退場先または変形軸。上0・下1・左2・右3。
    EntranceTiming: Integer; // 登場の動き方の固定ID。0は従来の種類ごとの曲線。
    ExitTiming: Integer; // 退場の動き方の固定ID。登場とは独立して選ぶ。
    EntranceDelay: Single; // 次の動作単位が登場を始めるまでの秒数。0なら全て同時。
    ExitDelay: Single; // 次の動作単位が退場を始めるまでの秒数。0なら全て同時。
    EntranceOrder, ExitOrder: Integer; // 正順0・逆順1・中央2・両端3・固定ランダム4。
    EntranceUnit, HoldUnit, ExitUnit: Integer; // 各状態の単位。文字0・行1・登録グループ2・全体3。
    EntranceStrength, HoldStrength, ExitStrength: Single; // 既存の演出への倍率。1が100%、0..10。
    Amount: Single; // 移動・揺れの強さ。出力ピクセル単位。
    CurveAmount: Single; // 波・S字・ジグザグの曲がりの強さ。0なら直線移動。
    Period: Single; // 表示中の反復周期。秒単位。
    Shape: TMVShapeSettings; // 文字の演出とは別に重ねる、フレーズ追従の図形演出。
    Appearance: TMVAppearanceSettings; // 動作とは独立した装飾・走査光・残像。
    PositionMotion: TMVPositionMotionSettings; // 全状態を通じて既存の位置へ加える移動。
  end;

// 共通書式に文字単位の上書きを重ね、描画用の実効書式を返す。
function ResolveMVStyle(const Common: TMVStyle; const Item: TMVPlacement): TMVStyle;
// 静止表示を基本とした空フレーズを返す。
function DefaultMVDocument: TMVDocument;
// 動的配列を分離し、編集・Undoで共有データを書き換えない複製を返す。
function CloneMVDocument(const Source: TMVDocument): TMVDocument;
// 保存・描画に受け渡せる有限値と制限内の設定か検証し、不正値は例外にする。
procedure ValidateMVDocument(const Document: TMVDocument);
// 組版に関係しない演出設定だけを検証する。不正値は例外にする。
procedure ValidateMVAnimation(const Document: TMVDocument);

implementation

uses System.Math, MVAnimationTypes, MVAnimationCatalog, MVTransitionTiming, MVAnimationSequence, MVTransitionParts;

function ResolveMVStyle(const Common: TMVStyle; const Item: TMVPlacement): TMVStyle;
begin
  Result := Common;
  ApplyMVStyleFields(Result, Item.Style, Item.StyleFields);
end;

function DefaultMVDocument: TMVDocument;
begin
  Result := Default(TMVDocument);
  Result.Style := DefaultMVStyle;
  Result.EntranceDirection := Ord(madDown);
  Result.ExitDirection := Ord(madUp);
  Result.Amount := 60;
  Result.EntranceStrength := 1;
  Result.HoldStrength := 1;
  Result.ExitStrength := 1;
  Result.CurveAmount := MV_DEFAULT_CURVE_AMOUNT;
  Result.Period := 2;
  Result.Shape := DefaultMVShapeSettings;
  Result.Appearance := DefaultMVAppearance;
  Result.PositionMotion := DefaultMVPositionMotion;
end;

function CloneMVDocument(const Source: TMVDocument): TMVDocument;
begin
  Result := Source;
  Result.Units := Copy(Source.Units);
end;

procedure CheckRange(Value, LowValue, HighValue: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < LowValue) or (Value > HighValue) then
    raise EArgumentException.Create('設定値が有効な範囲外です。');
end;

procedure ValidateMVAnimation(const Document: TMVDocument);
begin
  if not IsMVAnimationID(makHold, Document.Hold) then
    raise EArgumentException.Create('未対応のアニメーションが指定されています。');
  if not IsMVTransitionPartID(mtpMotion, Document.EntranceMotion) or
    not IsMVTransitionPartID(mtpMotion, Document.ExitMotion) or
    not IsMVTransitionPartID(mtpVisibility, Document.EntranceVisibility) or
    not IsMVTransitionPartID(mtpVisibility, Document.ExitVisibility) then
    raise EArgumentException.Create('未対応の動きまたは見え方が指定されています。');
  if not IsMVTimingID(Document.EntranceTiming) or not IsMVTimingID(Document.ExitTiming) then
    raise EArgumentException.Create('未対応のアニメーションの動き方が指定されています。');
  CheckRange(Document.Amount, 0, 2000);
  CheckRange(Document.EntranceStrength, 0, 10);
  CheckRange(Document.HoldStrength, 0, 10);
  CheckRange(Document.ExitStrength, 0, 10);
  CheckRange(Document.EntranceOrder, 0, Ord(High(TMVAnimationOrder)));
  CheckRange(Document.ExitOrder, 0, Ord(High(TMVAnimationOrder)));
  CheckRange(Document.EntranceUnit, 0, Ord(High(TMVAnimationUnit)));
  CheckRange(Document.HoldUnit, 0, Ord(High(TMVAnimationUnit)));
  CheckRange(Document.ExitUnit, 0, Ord(High(TMVAnimationUnit)));
  CheckRange(Document.CurveAmount, 0, 2000);
  CheckRange(Document.EntranceDelay, 0, 1);
  CheckRange(Document.ExitDelay, 0, 1);
  CheckRange(Document.EntranceDirection, Ord(Low(TMVAnimationDirection)), Ord(High(TMVAnimationDirection)));
  CheckRange(Document.ExitDirection, Ord(Low(TMVAnimationDirection)), Ord(High(TMVAnimationDirection)));
  CheckRange(Document.Period, 0.05, 120);
  ValidateMVShapeSettings(Document.Shape);
  ValidateMVAppearance(Document.Appearance);
  ValidateMVPositionMotion(Document.PositionMotion);
end;

procedure ValidateMVDocument(const Document: TMVDocument);
var
  Item: TMVPlacement;
  Joined: string;
begin
  if (Length(Document.Text) > MV_MAX_TEXT_LENGTH) or (Length(Document.Units) > MV_MAX_UNITS) then
    raise EArgumentException.Create('1フレーズの文字数が上限を超えています。');
  ValidateMVStyle(Document.Style);
  ValidateMVAnimation(Document);
  Joined := '';
  for Item in Document.Units do
  begin
    ValidateMVStyle(ResolveMVStyle(Document.Style, Item));
    CheckRange(Item.X, -32768, 32768);
    CheckRange(Item.Y, -32768, 32768);
    CheckRange(Item.Scale, 0.05, 10);
    CheckRange(Item.ScaleX, 0.05, 10);
    CheckRange(Item.ScaleY, 0.05, 10);
    CheckRange(Item.Shear, -100, 100);
    CheckRange(Item.Angle, -3600, 3600);
    CheckRange(Item.AnimationGroup, 0, MV_MAX_UNITS);
    if Item.Text = '' then
      raise EArgumentException.Create('空の文字配置は保存できません。');
    Joined := Joined + Item.Text;
  end;
  if Joined <> Document.Text then
    raise EArgumentException.Create('歌詞と文字配置が一致しません。');
end;

end.
