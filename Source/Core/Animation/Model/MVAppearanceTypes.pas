unit MVAppearanceTypes;

// 装飾の時間変化、光の走査、過去時刻の残像を定義する。描画資源や前フレームは保持しない。
interface

uses System.UITypes;

type
  TMVAppearanceSettings = record
    ColorMode: Integer; // 0=なし、1=指定色と往復、2=虹色が巡る。
    Color: TAlphaColor; // 往復する相手の色。
    ColorAmount: Single; // 色変化の混合率。0..1。
    GlowPulse: Single; // 発光の強弱への置換率。0..1、0は元の発光。
    ChromaticSwing: Single; // 元の色ずれ距離へ加える往復振幅。0..64px。
    Period: Single; // 色・発光・色ずれが1周する秒数。
    SweepMode: Integer; // 0=なし、1=繰り返す、2=一度だけ。
    SweepColor: TAlphaColor; // 文字の上を走る光の色。
    SweepAmount: Single; // 光の不透明度。0..1。
    SweepWidth: Single; // 光の帯の半幅。出力ピクセル単位。
    SweepAngle: Single; // 光の進行方向。0は右、90は下。
    SweepPeriod: Single; // 1回の走査秒数。一度だけの場合もこの時間で通過する。
    EchoCount: Integer; // 過去の文字像の枚数。0はなし、最大8。
    EchoInterval: Single; // 隣接する残像の時間差。秒単位。
    EchoOpacity: Single; // 最も新しい残像の不透明度。0..1。
    EchoDecay: Single; // 1枚古くなるごとに掛ける減衰率。0..1。
  end;

  TMVAppearanceFrame = record
    Active: Boolean; // 静止編集・区間外ではFalse。
    Dynamic: Boolean; // 時間装飾が設定されている間は同じ合成経路を使い、周期端の画像切替を避ける。
    TintColor: TAlphaColor; // 混合率をアルファへ含めた今回の色。
    GlowMix, GlowWave: Single; // 元の発光と周期波を混ぜる比率、および波の値。
    ChromaticOffset: Single; // 今回の色ずれへの追加距離。
    ChromaticMargin: Single; // 周期中の最大追加距離。クリップ範囲を安定させる。
    SweepVisible: Boolean; // 光の走査を描く時刻か。
    SweepProgress: Single; // 走査の進行。0..1。
    SweepColor: TAlphaColor; // 強さをアルファへ反映した光の色。
    SweepWidth, SweepAngle: Single; // 帯の半幅と進行方向。
  end;

// 追加演出を全て無効にした初期設定。
function DefaultMVAppearance: TMVAppearanceSettings;
// 有限値・既知ID・負荷上限を検証し、不正値は例外にする。
procedure ValidateMVAppearance(const Value: TMVAppearanceSettings);
// 現在時刻からだけ装飾を評価する。負時間の編集表示では元の書式を使う。
function EvaluateMVAppearance(const Value: TMVAppearanceSettings; Time, Duration: Double): TMVAppearanceFrame;

implementation

uses System.Math, System.SysUtils;

function DefaultMVAppearance: TMVAppearanceSettings;
begin
  Result := Default(TMVAppearanceSettings);
  Result.Color := $FF80DFFF;
  Result.ColorAmount := 1;
  Result.Period := 2;
  Result.SweepColor := $FFFFFFFF;
  Result.SweepAmount := 0.8;
  Result.SweepWidth := 60;
  Result.SweepPeriod := 2;
  Result.EchoInterval := 0.05;
  Result.EchoOpacity := 0.4;
  Result.EchoDecay := 0.65;
end;

procedure CheckValue(Value, Minimum, Maximum: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < Minimum) or (Value > Maximum) then
    raise EArgumentException.Create('装飾アニメーションの設定値が範囲外です。');
end;

procedure ValidateMVAppearance(const Value: TMVAppearanceSettings);
begin
  CheckValue(Value.ColorMode, 0, 2);
  CheckValue(Value.ColorAmount, 0, 1);
  CheckValue(Value.GlowPulse, 0, 1);
  CheckValue(Value.ChromaticSwing, 0, 64);
  CheckValue(Value.Period, 0.05, 120);
  CheckValue(Value.SweepMode, 0, 2);
  CheckValue(Value.SweepAmount, 0, 1);
  CheckValue(Value.SweepWidth, 1, 1024);
  CheckValue(Value.SweepAngle, -180, 180);
  CheckValue(Value.SweepPeriod, 0.05, 60);
  CheckValue(Value.EchoCount, 0, 8);
  CheckValue(Value.EchoInterval, 0.005, 1);
  CheckValue(Value.EchoOpacity, 0, 1);
  CheckValue(Value.EchoDecay, 0, 1);
end;

function Rainbow(Phase: Double): TAlphaColor;
var H, X: Double; R, G, B: Integer;
begin
  H := Frac(Phase) * 6;
  X := 255 * (1 - Abs(H - 2 * Floor(H / 2) - 1));
  R := 0; G := 0; B := 0;
  case Trunc(H) of
    0: begin R := 255; G := Round(X); end;
    1: begin R := Round(X); G := 255; end;
    2: begin G := 255; B := Round(X); end;
    3: begin G := Round(X); B := 255; end;
    4: begin R := Round(X); B := 255; end;
    5: begin R := 255; B := Round(X); end;
  end;
  Result := $FF000000 or Cardinal(R shl 16) or Cardinal(G shl 8) or Cardinal(B);
end;

function AlphaColor(Color: TAlphaColor; Amount: Double): TAlphaColor;
begin
  Result := (Color and $FFFFFF) or (Cardinal(Round((Color shr 24) * EnsureRange(Amount, 0.0, 1.0))) shl 24);
end;

function EvaluateMVAppearance(const Value: TMVAppearanceSettings; Time, Duration: Double): TMVAppearanceFrame;
var Phase, Wave: Double;
begin
  Result := Default(TMVAppearanceFrame);
  if IsNan(Time) or IsInfinite(Time) or IsNan(Duration) or IsInfinite(Duration) or
    (Time < 0) or (Time >= Duration) then Exit;
  Result.Active := True;
  Result.Dynamic := ((Value.ColorMode <> 0) and (Value.ColorAmount > 0)) or
    (Value.GlowPulse > 0) or (Value.ChromaticSwing > 0) or
    ((Value.SweepMode <> 0) and (Value.SweepAmount > 0));
  Phase := Frac(Time / Value.Period);
  Wave := 0.5 - 0.5 * Cos(2 * Pi * Phase);
  case Value.ColorMode of
    1: Result.TintColor := AlphaColor(Value.Color, Value.ColorAmount * Wave);
    2: Result.TintColor := AlphaColor(Rainbow(Phase), Value.ColorAmount);
  end;
  Result.GlowMix := Value.GlowPulse;
  Result.GlowWave := Wave;
  Result.ChromaticOffset := Value.ChromaticSwing * Sin(2 * Pi * Phase);
  Result.ChromaticMargin := Value.ChromaticSwing;
  Result.SweepVisible := (Value.SweepMode <> 0) and (Value.SweepAmount > 0) and
    ((Value.SweepMode = 1) or (Time < Value.SweepPeriod));
  Result.SweepProgress := Frac(Time / Value.SweepPeriod);
  Result.SweepColor := AlphaColor(Value.SweepColor, Value.SweepAmount);
  Result.SweepWidth := Value.SweepWidth;
  Result.SweepAngle := Value.SweepAngle;
end;

end.
