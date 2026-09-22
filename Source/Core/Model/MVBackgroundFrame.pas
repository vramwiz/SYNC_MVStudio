unit MVBackgroundFrame;

// 編集開始時の参照背景を所有する。文書保存やUndoには含めない。
interface

uses System.SysUtils;

type
  TMVBackgroundFrame = record
    Width, Height: Integer; // 合成前の入力画像寸法。文字と同じ出力座標で表示する。
    Pixels: TBytes; // 非乗算RGBA8888。取得側が独立した配列を所有する。
    // 正の寸法と必要な画素領域が揃っているか確認する。
    function IsValid: Boolean;
  end;

implementation

function TMVBackgroundFrame.IsValid: Boolean;
begin
  Result := (Width > 0) and (Height > 0) and (Int64(Width) * Height <= 16777216) and
    (Int64(Width) * Height * 4 = Length(Pixels));
end;

end.
