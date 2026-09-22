unit MVPositionMotionTypes;

// 配置・既存演出から独立した位置モーションの値と保存用IDを定義する。
interface

type
  TMVPositionMotionKind = (mpkNone, mpkReciprocate, mpkWave, mpkEllipse, mpkFigureEight, mpkDrift, mpkJitter);
  TMVPositionMotionTarget = (mptAnimationUnit, mptPhrase);

  TMVPositionMotionSettings = record
    Kind: Integer; // なし0・往復1・波2・円/楕円3・8の字4・漂流5・震え6。保存IDは並べ替えない。
    AmplitudeX, AmplitudeY: Single; // 出力座標軸ごとの移動幅。0ならその軸を固定する。
    Period: Single; // 全区間を通じて進む軌道の周期。秒単位。
    Direction: Single; // 軌道の向き。幅を掛ける前に適用する回転角、度単位。
    Target: Integer; // 既存の動作単位0・フレーズ全体1。
    EntranceStrength, HoldStrength, ExitStrength: Single; // 追加移動だけの倍率。1が100%。
    PhaseStep: Single; // 次の動作単位へ与える位相の遅れ。度単位、0なら同位相。
  end;

// 旧文書でも元の配置を維持する無効状態を返す。
function DefaultMVPositionMotion: TMVPositionMotionSettings;
// 未知のID、非有限値、範囲外を保存・描画の手前で拒否する。
procedure ValidateMVPositionMotion(const Value: TMVPositionMotionSettings);
// ホスト選択肢の短い表現を返す。
function MVPositionMotionName(Kind: TMVPositionMotionKind): string;

implementation

uses System.SysUtils, System.Math;

function DefaultMVPositionMotion: TMVPositionMotionSettings;
begin
  Result := Default(TMVPositionMotionSettings);
  Result.AmplitudeX := 30;
  Result.AmplitudeY := 20;
  Result.Period := 2;
  Result.EntranceStrength := 1;
  Result.HoldStrength := 1;
  Result.ExitStrength := 1;
end;

procedure CheckRange(Value, LowValue, HighValue: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < LowValue) or (Value > HighValue) then
    raise EArgumentException.Create('追加の位置モーションの設定値が範囲外です。');
end;

procedure ValidateMVPositionMotion(const Value: TMVPositionMotionSettings);
begin
  CheckRange(Value.Kind, Ord(Low(TMVPositionMotionKind)), Ord(High(TMVPositionMotionKind)));
  CheckRange(Value.Target, Ord(Low(TMVPositionMotionTarget)), Ord(High(TMVPositionMotionTarget)));
  CheckRange(Value.AmplitudeX, 0, 2000);
  CheckRange(Value.AmplitudeY, 0, 2000);
  CheckRange(Value.Period, 0.05, 60);
  CheckRange(Value.Direction, -180, 180);
  CheckRange(Value.EntranceStrength, 0, 10);
  CheckRange(Value.HoldStrength, 0, 10);
  CheckRange(Value.ExitStrength, 0, 10);
  CheckRange(Value.PhaseStep, -360, 360);
end;

function MVPositionMotionName(Kind: TMVPositionMotionKind): string;
begin
  case Kind of
    mpkNone: Result := 'なし';
    mpkReciprocate: Result := '往復';
    mpkWave: Result := '波';
    mpkEllipse: Result := '円・楕円';
    mpkFigureEight: Result := '8の字';
    mpkDrift: Result := '漂流';
    mpkJitter: Result := '震え';
  else Result := 'なし';
  end;
end;

end.
