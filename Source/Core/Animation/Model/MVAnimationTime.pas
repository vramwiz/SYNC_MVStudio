unit MVAnimationTime;

// 文字と図形で共有する登場・退場の時間正規化。演出種類の判断は呼出し側が行う。
interface

type
  TMVAnimationSchedule = record
    EntranceTime, ExitTime: Double; // 正規化後の1動作単位あたりの動作時間。
    EntranceDelay, ExitDelay: Double; // 正規化後の隣接する開始段の間隔。
    EntranceSpan, ExitSpan: Double; // 最初の段の開始から最後の段の完了までの時間。
  end;

// 不正・負の時間は0、合計がDurationを超える場合は比率を保って縮める。
procedure NormalizeMVDurations(Duration: Double; var EntranceTime, ExitTime: Double);
// 空白を除いたUnitCountで全体時間を求め、所要時間と開始間隔を同じ比率で対象区間へ収める。
function BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, EntranceDelay, ExitDelay: Double;
  UnitCount: Integer): TMVAnimationSchedule; overload;
// 登場と退場で同時開始の組数が異なる場合に、それぞれの開始段数から全体区間を作る。
function BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, EntranceDelay, ExitDelay: Double;
  EntranceSteps, ExitSteps: Integer): TMVAnimationSchedule; overload;

implementation

uses System.Math;

function ValidMVTime(Value: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < 0) then Result := 0
  else Result := Value;
end;

procedure NormalizeMVDurations(Duration: Double; var EntranceTime, ExitTime: Double);
var Scale: Double;
begin
  EntranceTime := ValidMVTime(EntranceTime);
  ExitTime := ValidMVTime(ExitTime);
  if IsNan(Duration) or IsInfinite(Duration) or (Duration <= 0) then
  begin
    EntranceTime := 0;
    ExitTime := 0;
  end
  else if EntranceTime + ExitTime > Duration then
  begin
    Scale := Duration / (EntranceTime + ExitTime);
    EntranceTime := EntranceTime * Scale;
    ExitTime := ExitTime * Scale;
  end;
end;

function BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, EntranceDelay, ExitDelay: Double;
  UnitCount: Integer): TMVAnimationSchedule;
begin
  Result := BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, EntranceDelay, ExitDelay, UnitCount, UnitCount);
end;

function BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, EntranceDelay, ExitDelay: Double;
  EntranceSteps, ExitSteps: Integer): TMVAnimationSchedule;
var InGaps, OutGaps: Integer; Total, Scale: Double;
begin
  Result := Default(TMVAnimationSchedule);
  Result.EntranceTime := ValidMVTime(EntranceTime);
  Result.ExitTime := ValidMVTime(ExitTime);
  InGaps := Max(1, EntranceSteps) - 1;
  OutGaps := Max(1, ExitSteps) - 1;
  if InGaps > 0 then Result.EntranceDelay := ValidMVTime(EntranceDelay);
  if OutGaps > 0 then Result.ExitDelay := ValidMVTime(ExitDelay);
  Result.EntranceSpan := Result.EntranceTime + InGaps * Result.EntranceDelay;
  Result.ExitSpan := Result.ExitTime + OutGaps * Result.ExitDelay;
  Total := Result.EntranceSpan + Result.ExitSpan;
  NormalizeMVDurations(Duration, Result.EntranceSpan, Result.ExitSpan);
  if Total > 0 then
  begin
    Scale := (Result.EntranceSpan + Result.ExitSpan) / Total;
    Result.EntranceTime := Result.EntranceTime * Scale;
    Result.ExitTime := Result.ExitTime * Scale;
    Result.EntranceDelay := Result.EntranceDelay * Scale;
    Result.ExitDelay := Result.ExitDelay * Scale;
  end;
end;

end.
