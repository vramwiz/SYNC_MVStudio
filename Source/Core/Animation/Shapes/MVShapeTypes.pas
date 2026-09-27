unit MVShapeTypes;

// 文字とは独立して選ぶ図形演出の固定IDと設定値。ホスト・JSON・描画で共有する。
interface

uses System.UITypes;

const
  MV_SHAPE_NONE      = 0; // 図形なし。旧データの既定値。
  MV_SHAPE_BAND      = 1; // フレーズを覆う帯の伸縮。
  MV_SHAPE_UNDERLINE = 2; // フレーズの下に線を描く。
  MV_SHAPE_RING      = 3; // 外側へ広がる楕円の波紋。
  MV_SHAPE_BURST     = 4; // 周囲へ小図形を飛散させる。
  MV_SHAPE_SHARDS    = 5; // 塗りの三角と細長い破片を漂わせる。

type
  TMVShapeSettings = record
    EffectID: Integer; // 保存する固定ID。文字の登場・退場IDとは別系統。
    Color: TAlphaColor; // 非乗算ARGB色。不透明度はOpacityを掛ける。
    Opacity: Single; // 全図形の不透明度。0..1。
    Padding: Single; // フレーズの外側へ設ける余白。出力ピクセル単位。
    LineWidth: Single; // 下線・リング・小図形の輪郭幅。出力ピクセル単位。
    Period: Single; // 波紋・飛散の反復周期。秒単位。
    Direction: Integer; // 帯の伸縮方向、下線の描き順。上0・下1・左2・右3。
    Foreground: Boolean; // Trueなら文字の前面、Falseなら背面へ合成する。
  end;

// なし・背面を既定とし、図形を選んだ時に使える初期値を返す。
function DefaultMVShapeSettings: TMVShapeSettings;
// ホスト選択肢数。末尾のnil終端は含めない。
function MVShapeCount: Integer;
// 固定IDの名前を返す。未知IDは「なし」とする。
function MVShapeName(ID: Integer): string;
// 保存と描画へ渡す有限値・範囲・固定IDを検証し、不正な値は例外にする。
procedure ValidateMVShapeSettings(const Settings: TMVShapeSettings);

implementation

uses System.SysUtils, System.Math;

const
  ShapeNames: array[0..5] of string = ('なし', '帯ワイプ', '下線描画', 'リング波紋', '小図形飛散', '光の破片');

function DefaultMVShapeSettings: TMVShapeSettings;
begin
  Result := Default(TMVShapeSettings);
  Result.Color := $FF60C8FF;
  Result.Opacity := 0.5;
  Result.Padding := 16;
  Result.LineWidth := 3;
  Result.Period := 2;
  Result.Direction := 2;
end;

function MVShapeCount: Integer;
begin
  Result := Length(ShapeNames);
end;

function MVShapeName(ID: Integer): string;
begin
  if (ID >= 0) and (ID < Length(ShapeNames)) then Result := ShapeNames[ID]
  else Result := ShapeNames[MV_SHAPE_NONE];
end;

procedure CheckShapeRange(Value, LowValue, HighValue: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < LowValue) or (Value > HighValue) then
    raise EArgumentException.Create('図形演出の設定値が有効な範囲外です。');
end;

procedure ValidateMVShapeSettings(const Settings: TMVShapeSettings);
begin
  CheckShapeRange(Settings.EffectID, 0, High(ShapeNames));
  CheckShapeRange(Settings.Opacity, 0, 1);
  CheckShapeRange(Settings.Padding, 0, 512);
  CheckShapeRange(Settings.LineWidth, 0.5, 64);
  CheckShapeRange(Settings.Period, 0.05, 120);
  CheckShapeRange(Settings.Direction, 0, 3);
end;

end.
