unit MVTestAssert;

// コンソール検証で失敗箇所を特定し、完了した検証数を集計する。
interface

// 条件がFalseならテスト名付き例外で実行を停止する。
procedure Check(Condition: Boolean; const Name: string);
// 成功した検証数を返す。
function CheckCount: Integer;

implementation

uses System.SysUtils;

var Count: Integer;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Count);
end;

function CheckCount: Integer;
begin
  Result := Count;
end;

end.
