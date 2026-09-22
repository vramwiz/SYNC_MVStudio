unit MVAnimationSequence;

// 動作単位と開始順を定義する。乱数状態を持たず、任意時刻の描画で同じ順序を返す。
interface

type
  TMVAnimationOrder = (maoForward, maoReverse, maoCenter, maoEdges, maoRandom);
  TMVAnimationUnit = (mauCharacter, mauLine, mauGroup, mauPhrase);

// ホストへ公開する短い選択肢名を返す。
function MVAnimationOrderName(Value: TMVAnimationOrder): string;
// 動作単位の選択肢名を返す。選択グループは文書へ登録済みの文字集合を指す。
function MVAnimationUnitName(Value: TMVAnimationUnit): string;
// 同時開始する左右の組を1段として数える。対象なしは0を返す。
function MVAnimationOrderSteps(Order, Count: Integer): Integer;
// 歌詞順のIndexを0始まりの開始段へ変換する。空白の負インデックスは最初の段にする。
function MVAnimationOrderRank(Order, Index, Count: Integer): Integer;

implementation

uses System.Math;

function MVAnimationOrderName(Value: TMVAnimationOrder): string;
const Names: array[TMVAnimationOrder] of string = ('正順', '逆順', '中央から', '両端から', 'ランダム');
begin
  Result := Names[Value];
end;

function MVAnimationUnitName(Value: TMVAnimationUnit): string;
const Names: array[TMVAnimationUnit] of string = ('文字', '行', '選択グループ', 'フレーズ全体');
begin
  Result := Names[Value];
end;

function MVAnimationOrderSteps(Order, Count: Integer): Integer;
begin
  Result := Max(0, Count);
  if Order in [Ord(maoCenter), Ord(maoEdges)] then Result := (Result + 1) div 2;
end;

function MVAnimationOrderRank(Order, Index, Count: Integer): Integer;
var Mask: Integer;
begin
  Result := 0;
  if (Index < 0) or (Count <= 1) then Exit;
  Index := Min(Index, Count - 1);
  case Order of
    Ord(maoReverse): Result := Count - 1 - Index;
    Ord(maoCenter): Result := Abs(2 * Index - (Count - 1)) div 2;
    Ord(maoEdges): Result := Min(Index, Count - 1 - Index);
    Ord(maoRandom):
      begin
        Mask := 1;
        while Mask < Count do Mask := Mask * 2;
        Dec(Mask);
        Result := Index;
        // 2の累乗範囲内の全単射を範囲内へ戻るまで適用し、重複のない順番にする。
        repeat
          Result := (Result * 157 + 101) and Mask;
          Result := Result xor (Result shr 3);
        until Result < Count;
      end;
  else
    Result := Index;
  end;
end;

end.
