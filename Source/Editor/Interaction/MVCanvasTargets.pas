unit MVCanvasTargets;

// 配置キャンバスの文字本体への当たり判定と、移動先の吸着候補を求める。

interface

uses
  System.Types,
  MVDocument,
  MVLayout,
  MVSelection;

// 前面の文字から調べ、指定した文書座標にある文字の添字を返す。該当なしは-1。
function HitMVCanvasUnit(const Document: TMVDocument; Layout: TMVLayout; const Point: TPointF): Integer;
// 未選択文字と出力中央を候補に、画面ピクセル基準の許容距離でItemの位置を吸着する。
procedure SnapMVCanvasPosition(var Item: TMVPlacement; Layout: TMVLayout;
  Selection: TMVSelection; Zoom, PPI: Single);

implementation

uses
  System.Math,
  MVTransformGeometry;

function HitMVCanvasUnit(const Document: TMVDocument; Layout: TMVLayout; const Point: TPointF): Integer;
var
  I: Integer;
  Item: TMVPlacement;
begin
  for I := High(Layout.Units) downto 0 do
  begin
    if Layout.Units[I].Image = nil then
      Continue;
    Item := Document.Units[I];
    Item.X := Layout.Units[I].Position.X;
    Item.Y := Layout.Units[I].Position.Y;
    if MVHitBody(Item, Layout.Units[I].HitBounds, Point) then
      Exit(I);
  end;
  Result := -1;
end;

procedure SnapMVCanvasPosition(var Item: TMVPlacement; Layout: TMVLayout;
  Selection: TMVSelection; Zoom, PPI: Single);
var
  BestX: Single;
  BestY: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  Limit: Single;
  Target: TPointF;
begin
  Limit := 6 * PPI / 96 / Zoom;
  BestX := Limit;
  BestY := Limit;
  DX := 0;
  DY := 0;
  for I := -1 to High(Layout.Units) do
  begin
    if Selection.Contains(I) then
      Continue;
    if I < 0 then
      Target := PointF(0, 0)
    else
    begin
      if Layout.Units[I].Image = nil then
        Continue;
      Target := Layout.Units[I].Position;
    end;
    if Abs(Target.X - Item.X) < BestX then
    begin
      BestX := Abs(Target.X - Item.X);
      DX := Target.X - Item.X;
    end;
    if Abs(Target.Y - Item.Y) < BestY then
    begin
      BestY := Abs(Target.Y - Item.Y);
      DY := Target.Y - Item.Y;
    end;
  end;
  Item.X := Item.X + DX;
  Item.Y := Item.Y + DY;
end;

end.
