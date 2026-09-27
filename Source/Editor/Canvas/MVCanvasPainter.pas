unit MVCanvasPainter;

// 静止背景・文字・選択ハンドルをSkiaで合成し、VCLの描画先へ転送する。
interface

uses Winapi.Windows, System.SysUtils, System.Types, System.Skia, MVDocument, MVLayout,
  MVCanvasViewport, MVTransformGeometry, MVDecorationHandles;

// 操作状態から独立して背景と歌詞を描く。Bufferは次の描画でも再利用する。
procedure PaintMVEditorCanvas(DC: HDC; const Size, Output: TSize; const Document: TMVDocument;
  Layout: TMVLayout; const Background: ISkImage; const View: TMVViewport;
  const Handles: TMVHandlePoints; const Selected: TArray<Integer>; HandleSize: Single; Marquee: Boolean;
  const RangeStart, RangeEnd: TPointF; const Decoration: TMVDecorationPoints;
  ActiveDecoration: TMVDecorationHandle; var Buffer: TBytes);
implementation

uses MVRenderer, MVSelectionOverlay;

function BufferSurface(const Size: TSize; var Buffer: TBytes): ISkSurface;
begin
  SetLength(Buffer, Size.Width * Size.Height * 4);
  Result := TSkSurface.MakeRasterDirect(TSkImageInfo.Create(Size.Width, Size.Height,
    TSkColorType.BGRA8888, TSkAlphaType.Opaque), @Buffer[0], Size.Width * 4);
end;

procedure CopyToDC(DC: HDC; const Size: TSize; const Buffer: TBytes);
var Info: TBitmapInfo;
begin
  Info := Default(TBitmapInfo);
  Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  Info.bmiHeader.biWidth := Size.Width;
  Info.bmiHeader.biHeight := -Size.Height;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  StretchDIBits(DC, 0, 0, Size.Width, Size.Height, 0, 0, Size.Width, Size.Height,
    @Buffer[0], Info, DIB_RGB_COLORS, SRCCOPY);
end;

procedure PaintMVEditorCanvas(DC: HDC; const Size, Output: TSize; const Document: TMVDocument;
  Layout: TMVLayout; const Background: ISkImage; const View: TMVViewport;
  const Handles: TMVHandlePoints; const Selected: TArray<Integer>; HandleSize: Single; Marquee: Boolean;
  const RangeStart, RangeEnd: TPointF; const Decoration: TMVDecorationPoints;
  ActiveDecoration: TMVDecorationHandle; var Buffer: TBytes);
var Surface: ISkSurface; Brush: ISkPaint; I: Integer; H: TMVHandle; Points: TMVHandlePoints; Item: TMVPlacement;
begin
  Surface := BufferSurface(Size, Buffer);
  if Surface = nil then Exit;
  Surface.Canvas.Clear($FF202124);
  Surface.Canvas.Save;
  Surface.Canvas.Translate(View.Origin.X, View.Origin.Y);
  Surface.Canvas.Scale(View.Zoom, View.Zoom);
  Brush := TSkPaint.Create;
  Brush.Color := $FF383A40;
  Surface.Canvas.DrawRect(RectF(0, 0, Output.Width, Output.Height), Brush);
  Surface.Canvas.Save;
  try
    Surface.Canvas.ClipRect(RectF(0, 0, Output.Width, Output.Height));
    if Background <> nil then
      Surface.Canvas.DrawImageRect(Background, RectF(0, 0, Output.Width, Output.Height), TSkSamplingOptions.High);
  finally
    Surface.Canvas.Restore;
  end;
  // 出力枠は背景だけに適用し、編集時の文字は枠外も表示・選択できるようにする。
  DrawMVDocument(Surface.Canvas, Document, Layout, Output.Width, Output.Height, 0, 0, -1, 1, 0, 0);
  Surface.Canvas.Restore;
  if Length(Selected) > 1 then
    for I in Selected do
    begin
      Item := Document.Units[I]; Item.X := Layout.Units[I].Position.X; Item.Y := Layout.Units[I].Position.Y;
      Points := MVHandles(Item, Layout.Units[I].HitBounds, 0);
      for H := mhNW to mhRotate do Points[H] := View.ToScreen(Points[H], Output.Width, Output.Height);
      DrawMVSelection(Surface.Canvas, Points, 0);
    end;
  if HandleSize > 0 then DrawMVSelection(Surface.Canvas, Handles, HandleSize);
  if HandleSize > 0 then DrawMVDecorationHandles(Surface.Canvas, Decoration, HandleSize * 1.25, ActiveDecoration);
  if Marquee then DrawMVMarquee(Surface.Canvas, RangeStart, RangeEnd);
  Surface := nil;
  CopyToDC(DC, Size, Buffer);
end;

end.
