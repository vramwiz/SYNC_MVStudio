unit MVTransitionParts;

// 登場・退場の動きと見え方の選択肢を分類する。SDKの状態は保持しない。
interface

uses MVAnimationTypes;

type
  TMVTransitionPartKind = (mtpMotion, mtpVisibility);

// 分類ごとの選択肢数。
function MVTransitionPartCount(Kind: TMVTransitionPartKind): Integer;
// 表示順から固定IDと名前を返す。評価関数の出力は合成側で担当要素だけを取り出す。
function MVTransitionPartAt(Kind: TMVTransitionPartKind; Index: Integer): TMVAnimationDescriptor;
// 公開中の要素IDかを確認する。異なる分類のIDは拒否する。
function IsMVTransitionPartID(Kind: TMVTransitionPartKind; ID: Integer): Boolean;
// どちらかの要素が有効なら所要時間と文字遅延を使用する。
function HasMVTransitionParts(MotionID, VisibilityID: Integer): Boolean;

implementation

uses System.SysUtils, MVAnimationCatalog;

const
  MotionIDs: array[0..20] of Integer = (0, 2, 3, 4, 5, 7, 8, 15, 16, 17, 18, 26, 27, 29, 30, 31, 32, 33, 37, 38, 39);
  VisibilityIDs: array[0..8] of Integer = (0, 1, 9, 10, 24, 34, 35, 36, 6); // 文字送りも見え方として単独指定できる。

function MVTransitionPartCount(Kind: TMVTransitionPartKind): Integer;
begin
  if Kind = mtpMotion then Result := Length(MotionIDs) else Result := Length(VisibilityIDs);
end;

function MVTransitionPartAt(Kind: TMVTransitionPartKind; Index: Integer): TMVAnimationDescriptor;
var ID: Integer;
begin
  if (Index < 0) or (Index >= MVTransitionPartCount(Kind)) then
    raise EArgumentOutOfRangeException.Create('演出要素の一覧位置が範囲外です。');
  if Kind = mtpMotion then ID := MotionIDs[Index] else ID := VisibilityIDs[Index];
  if not FindMVAnimation(makTransition, ID, Result) then
    raise EArgumentException.Create('演出要素がカタログへ登録されていません。');
end;

function IsMVTransitionPartID(Kind: TMVTransitionPartKind; ID: Integer): Boolean;
var Candidate: Integer;
begin
  if Kind = mtpMotion then
  begin
    for Candidate in MotionIDs do if ID = Candidate then Exit(True);
  end
  else
    for Candidate in VisibilityIDs do if ID = Candidate then Exit(True);
  Result := False;
end;

function HasMVTransitionParts(MotionID, VisibilityID: Integer): Boolean;
begin
  Result := (MotionID <> 0) or (VisibilityID <> 0);
end;

end.
