unit MVDecorationHandles;

// ScreenLayoutのフィルター直接編集を参考に、文字装飾の専用アイコンとドラッグ差分を定義する。
interface

uses System.Types, System.Skia, MVDocument, MVTransformGeometry;

type
  TMVDecorationHandle = (mdhNone, mdhOutlineWidth, mdhOutlineBlur, mdhShadowPosition, mdhShadowSpread, mdhShadowBlur);
  TMVDecorationPoints = array[mdhOutlineWidth..mdhShadowBlur] of TPointF;

// 選択枠の下へ操作を並べる。画面端では可視範囲へ寄せる。
function MVDecorationPoints(const Selection: TMVHandlePoints; Width, Height: Integer; DPI: Single): TMVDecorationPoints;
// アイコンのヒット判定と説明。画面座標の半径を使う。
function MVHitDecoration(const Points: TMVDecorationPoints; const P: TPointF; Radius: Single): TMVDecorationHandle;
function MVDecorationHint(Kind: TMVDecorationHandle): string;
// 選択文字の元の書式へ差分を加える。Deltaは画面ズームを除いた出力座標。
function MVDragDecoration(const Source: TMVDocument; const Indices: TArray<Integer>;
  Kind: TMVDecorationHandle; const Delta: TPointF): TMVDocument;
// ピクセルサイズ一定のアイコンを描く。ホストの出力画像には使わない。
procedure DrawMVDecorationHandles(const Canvas: ISkCanvas; const Points: TMVDecorationPoints;
  Radius: Single; Active: TMVDecorationHandle);

implementation

uses System.Math, MVStyleTypes;

function MVDecorationPoints(const Selection: TMVHandlePoints; Width, Height: Integer; DPI: Single): TMVDecorationPoints;
var H: TMVHandle; K: TMVDecorationHandle; X, Y, Step, Margin: Single;
begin
  X := Selection[mhNW].X;
  Y := Selection[mhNW].Y;
  for H := mhNW to mhW do
  begin
    X := Min(X, Selection[H].X);
    Y := Max(Y, Selection[H].Y);
  end;
  Step := 30 * DPI;
  Margin := 13 * DPI;
  X := EnsureRange(X + Margin, Margin, Max(Margin, Width - Margin - 4 * Step));
  Y := EnsureRange(Y + 30 * DPI, Margin, Max(Margin, Height - Margin));
  for K := mdhOutlineWidth to mdhShadowBlur do Result[K] := PointF(X + (Ord(K) - 1) * Step, Y);
end;

function MVHitDecoration(const Points: TMVDecorationPoints; const P: TPointF; Radius: Single): TMVDecorationHandle;
var K: TMVDecorationHandle;
begin
  for K := mdhOutlineWidth to mdhShadowBlur do
    if (Points[K] - P).Length <= Radius then Exit(K);
  Result := mdhNone;
end;

function MVDecorationHint(Kind: TMVDecorationHandle): string;
begin
  case Kind of
    mdhOutlineWidth: Result := '縁の太さ：左右にドラッグ';
    mdhOutlineBlur: Result := '縁のぼかし：左右にドラッグ';
    mdhShadowPosition: Result := '影の位置：上下左右にドラッグ';
    mdhShadowSpread: Result := '影の太さ：左右にドラッグ';
    mdhShadowBlur: Result := '影のぼかし：左右にドラッグ';
  else Exit('');
  end;
  Result := Result + '（Shiftで微調整、Escで取消）';
end;

function MVDragDecoration(const Source: TMVDocument; const Indices: TArray<Integer>;
  Kind: TMVDecorationHandle; const Delta: TPointF): TMVDocument;
var I: Integer; S, Before: TMVStyle; Item: TMVPlacement; D: TPointF; Amount: Single; Fields: TMVStyleFields;
begin
  Result := CloneMVDocument(Source);
  for I in Indices do
  begin
    Item := Source.Units[I];
    Before := ResolveMVStyle(Source.Style, Item);
    S := Before;
    Amount := Delta.X / (Item.Scale * Sqrt(Item.ScaleX * Item.ScaleY));
    D := MVRotate(Delta, -Item.Angle);
    D.X := D.X - Item.Shear * D.Y;
    D := PointF(D.X / (Item.Scale * Item.ScaleX), D.Y / (Item.Scale * Item.ScaleY));
    case Kind of
      mdhOutlineWidth: S.OutlineWidth := EnsureRange(S.OutlineWidth + Amount, Single(0), Single(32));
      mdhOutlineBlur: S.OutlineBlur := EnsureRange(S.OutlineBlur + Amount, Single(0), Single(64));
      mdhShadowPosition:
        begin
          S.ShadowX := EnsureRange(S.ShadowX + D.X, Single(-512), Single(512));
          S.ShadowY := EnsureRange(S.ShadowY + D.Y, Single(-512), Single(512));
        end;
      mdhShadowSpread: S.ShadowSpread := EnsureRange(S.ShadowSpread + Amount, Single(0), Single(64));
      mdhShadowBlur: S.ShadowBlur := EnsureRange(S.ShadowBlur + Amount, Single(0), Single(64));
    end;
    if MVStyleDifferences(Before, S) = [] then Continue;
    if Kind in [mdhShadowPosition, mdhShadowSpread, mdhShadowBlur] then S.Shadow := True
    else
    begin
      if (Kind = mdhOutlineBlur) and (S.OutlineWidth = 0) then S.OutlineWidth := 2;
      if (S.OutlineWidth > 0) and (S.FillMode = 1) then S.FillMode := 0;
    end;
    Fields := MVStyleDifferences(Before, S);
    ApplyMVStyleFields(Result.Units[I].Style, S, Fields);
    Result.Units[I].StyleFields := Result.Units[I].StyleFields + Fields;
  end;
end;

procedure DrawMVDecorationHandles(const Canvas: ISkCanvas; const Points: TMVDecorationPoints;
  Radius: Single; Active: TMVDecorationHandle);
var K: TMVDecorationHandle; P: ISkPaint; I: Integer;
begin
  P := TSkPaint.Create;
  P.AntiAlias := True;
  for K := mdhOutlineWidth to mdhShadowBlur do
  begin
    Canvas.Save;
    try
      Canvas.Translate(Points[K].X, Points[K].Y);
      Canvas.Scale(Radius / 10, Radius / 10);
      P.Style := TSkPaintStyle.Fill;
      P.Color := $FF303238;
      if K = Active then P.Color := $FF775020;
      Canvas.DrawCircle(0, 0, 11, P);
      P.Color := $FFFFBB66;
      P.Style := TSkPaintStyle.Stroke;
      P.StrokeWidth := 1.4;
      case K of
        mdhOutlineWidth:
          begin
            Canvas.DrawRect(RectF(-6, -6, 6, 6), P);
            Canvas.DrawRect(RectF(-3, -3, 3, 3), P);
          end;
        mdhOutlineBlur, mdhShadowBlur:
          begin
            Canvas.DrawCircle(0, 0, 3, P);
            P.Style := TSkPaintStyle.Fill;
            for I := 0 to 7 do Canvas.DrawCircle(Cos(I * Pi / 4) * 7, Sin(I * Pi / 4) * 7, 1, P);
            if K = mdhShadowBlur then Canvas.DrawRect(RectF(-7, -7, -2, -2), P);
          end;
        mdhShadowPosition:
          begin
            Canvas.DrawRect(RectF(-6, -6, 1, 1), P);
            Canvas.DrawRect(RectF(-1, -1, 6, 6), P);
            Canvas.DrawLine(-4, 5, 5, -4, P);
          end;
        mdhShadowSpread:
          begin
            P.StrokeWidth := 3;
            Canvas.DrawRect(RectF(-4, -4, 4, 4), P);
            P.StrokeWidth := 1;
            Canvas.DrawRect(RectF(-7, -7, 7, 7), P);
          end;
      end;
    finally Canvas.Restore; end;
  end;
end;

end.
