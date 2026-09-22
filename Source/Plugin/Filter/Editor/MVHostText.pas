unit MVHostText;

// 編集APIが返すエイリアス形式の文字列を、配置用の歌詞へ復元する。
interface

// 改行の\nとバックスラッシュの\\だけを1回復号する。未知の並びは原文を保持する。
// 描画コールバックの生文字列やBase64拡張データには適用しない。
function DecodeMVHostText(const Value: string): string;

implementation

function DecodeMVHostText(const Value: string): string;
var Source, Target: Integer; C: Char;
begin
  SetLength(Result, Length(Value));
  Source := 1;
  Target := 0;
  while Source <= Length(Value) do
  begin
    C := Value[Source];
    if (C = '\') and (Source < Length(Value)) then
      case Value[Source + 1] of
        'n': begin C := #10; Inc(Source); end;
        '\': Inc(Source);
      end;
    Inc(Target);
    Result[Target] := C;
    Inc(Source);
  end;
  SetLength(Result, Target);
end;

end.
