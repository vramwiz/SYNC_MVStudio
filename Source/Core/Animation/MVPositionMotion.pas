unit MVPositionMotion;

// 絶対時刻から追加の平行移動を求める。再生順や前フレームの状態には依存しない。
interface

uses System.Types, MVPositionMotionTypes, MVAnimationTime;

// 正規化済みの時間表を使う。UnitIndexは空白を除いた動作単位の通し番号。
// フレーズ単位は呼出し側が1組にまとめるため、開始順・位相差は0になる。
function EvaluateMVPositionMotion(const Settings: TMVPositionMotionSettings; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; UnitIndex, EntranceRank, ExitRank: Integer): TPointF;

implementation

uses System.Math;

function BlendProgress(Time, Boundary, HalfWidth: Double): Double;
begin
  if HalfWidth <= 0 then Exit(Ord(Time >= Boundary));
  Result := EnsureRange((Time - Boundary + HalfWidth) / (2 * HalfWidth), 0.0, 1.0);
  Result := Result * Result * (3 - 2 * Result);
end;

function MotionStrength(const Settings: TMVPositionMotionSettings; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; EntranceRank, ExitRank: Integer): Double;
var
  InStart, InEnd, OutStart, OutEnd, InLength, OutLength, HoldLength, Width, P: Double;
  HasIn, HasOut: Boolean;
begin
  InStart := Max(0, EntranceRank) * Schedule.EntranceDelay;
  InEnd := InStart + Schedule.EntranceTime;
  OutStart := Duration - Schedule.ExitSpan + Max(0, ExitRank) * Schedule.ExitDelay;
  OutEnd := OutStart + Schedule.ExitTime;
  InLength := Max(0.0, InEnd - InStart);
  OutLength := Max(0.0, OutEnd - OutStart);
  HasIn := InLength > 0;
  HasOut := OutLength > 0;
  if not HasIn then InEnd := 0;
  if not HasOut then OutStart := Duration;
  HoldLength := Max(0.0, OutStart - InEnd);
  if HasIn and HasOut and (HoldLength <= Duration * 1E-12) then
  begin
    // 尺を使い切る場合は存在しない表示中の強さを挟まず、登場から退場へ直接つなぐ。
    Width := Min(0.1, Min(InLength, OutLength) * 0.25);
    P := BlendProgress(Time, InEnd, Width);
    Exit(Settings.EntranceStrength + (Settings.ExitStrength - Settings.EntranceStrength) * P);
  end;
  if HasIn and not HasOut and (HoldLength <= Duration * 1E-12) then
    Exit(Settings.EntranceStrength);
  if HasOut and not HasIn and (HoldLength <= Duration * 1E-12) then
    Exit(Settings.ExitStrength);
  Result := Settings.HoldStrength;
  if HasIn then
  begin
    // 隣接区間の1/4以内、片側最大0.1秒。短い表示中でも前後の補間窓を重ねない。
    Width := Min(0.1, Min(InLength, HoldLength) * 0.25);
    P := BlendProgress(Time, InEnd, Width);
    Result := Settings.EntranceStrength + (Settings.HoldStrength - Settings.EntranceStrength) * P;
  end;
  if HasOut then
  begin
    Width := Min(0.1, Min(OutLength, HoldLength) * 0.25);
    P := BlendProgress(Time, OutStart, Width);
    Result := Result + (Settings.ExitStrength - Result) * P;
  end;
end;

procedure MotionPath(Kind: Integer; Phase: Double; out X, Y: Double);
begin
  X := 0;
  Y := 0;
  case TMVPositionMotionKind(Kind) of
    mpkReciprocate: X := Sin(Phase);
    mpkWave:
      begin
        X := Sin(Phase);
        Y := Sin(Pi * X);
      end;
    mpkEllipse:
      begin
        X := Cos(Phase);
        Y := Sin(Phase);
      end;
    mpkFigureEight:
      begin
        X := Sin(Phase);
        Y := Sin(2 * Phase);
      end;
    mpkDrift:
      begin
        X := 0.65 * Sin(Phase) + 0.25 * Sin(2 * Phase + 0.7) + 0.1 * Sin(3 * Phase + 2.1);
        Y := 0.6 * Cos(Phase + 0.4) + 0.25 * Sin(2 * Phase + 1.3) + 0.15 * Cos(3 * Phase);
      end;
    mpkJitter:
      begin
        // 整数倍の波を合成し、周期境界でも飛ばない再現可能な細かい震えにする。
        X := 0.5 * Sin(7 * Phase) + 0.3 * Sin(11 * Phase + 1.1) + 0.2 * Sin(17 * Phase + 2.4);
        Y := 0.5 * Cos(5 * Phase + 0.8) + 0.3 * Sin(13 * Phase) + 0.2 * Cos(19 * Phase + 1.7);
      end;
  end;
end;

function EvaluateMVPositionMotion(const Settings: TMVPositionMotionSettings; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; UnitIndex, EntranceRank, ExitRank: Integer): TPointF;
var Phase, Strength, X, Y, S, C: Double;
begin
  Result := PointF(0, 0);
  if (Settings.Kind = Ord(mpkNone)) or ((Settings.AmplitudeX = 0) and (Settings.AmplitudeY = 0)) or
    ((Settings.EntranceStrength = 0) and (Settings.HoldStrength = 0) and (Settings.ExitStrength = 0)) then Exit;
  if IsNan(Time) or IsInfinite(Time) or IsNan(Duration) or IsInfinite(Duration) or
    (Time < 0) or (Duration <= 0) or (Time >= Duration) then Exit;
  Strength := MotionStrength(Settings, Time, Duration, Schedule, EntranceRank, ExitRank);
  if Strength = 0 then Exit;
  // 開始遅延と状態の切替で時計を戻さない。正の位相差で次の単位が同じ軌道を遅れてたどる。
  Phase := 2 * Pi * Frac(Time / Settings.Period - Max(0, UnitIndex) * Settings.PhaseStep / 360);
  MotionPath(Settings.Kind, Phase, X, Y);
  SinCos(DegToRad(Settings.Direction), S, C);
  // 最後に出力軸ごとの幅を掛け、方向を変えても幅0の軸は動かさない。
  Result.X := (X * C - Y * S) * Settings.AmplitudeX * Strength;
  Result.Y := (X * S + Y * C) * Settings.AmplitudeY * Strength;
end;

end.
