unit TextRendererSkiaPaints;

// 文字本体・縁・影の描画用と外接範囲計測用のペイントを準備する。

interface

uses
  System.Skia,
  TextRendererTypes;

type
  TSkiaTextPaints = record
    Fill          : ISkPaint;          // 文字本体の塗り。
    Outlines      : TArray<ISkPaint>;  // ぼかしを含む縁の描画用。
    OutlineLayout : TArray<ISkPaint>;  // ぼかしを除いた縁の計測用。
    Shadows       : TArray<ISkPaint>;  // 影の描画用。
  end;

// 縁と影の寸法を検証し、描画と計測で使うペイント一式を返す。
function CreateSkiaTextPaints(const ARequest: TTextRenderRequest): TSkiaTextPaints;

implementation

uses
  System.SysUtils;

function CreateSkiaTextPaints(const ARequest: TTextRenderRequest): TSkiaTextPaints;
var
  I: Integer;
begin
  Result := System.Default(TSkiaTextPaints);
  Result.Fill := TSkPaint.Create(TSkPaintStyle.Fill);
  Result.Fill.AntiAlias := True;
  Result.Fill.Color := ARequest.FillColor;

  SetLength(Result.Outlines, Length(ARequest.Outlines));
  SetLength(Result.OutlineLayout, Length(ARequest.Outlines));
  for I := 0 to High(ARequest.Outlines) do
  begin
    if ARequest.Outlines[I].Width < 0 then
      raise EArgumentOutOfRangeException.Create('Outline width must not be negative');
    if ARequest.Outlines[I].BlurRadius < 0 then
      raise EArgumentOutOfRangeException.Create('Outline blur must not be negative');
    Result.Outlines[I] := TSkPaint.Create(TSkPaintStyle.Stroke);
    Result.Outlines[I].AntiAlias := True;
    Result.Outlines[I].Color := ARequest.Outlines[I].Color;
    Result.Outlines[I].StrokeWidth := ARequest.Outlines[I].Width;
    Result.Outlines[I].StrokeJoin := TSkStrokeJoin.Round;
    Result.OutlineLayout[I] := TSkPaint.Create(TSkPaintStyle.Stroke);
    Result.OutlineLayout[I].AntiAlias := True;
    Result.OutlineLayout[I].Color := ARequest.Outlines[I].Color;
    Result.OutlineLayout[I].StrokeWidth := ARequest.Outlines[I].Width;
    Result.OutlineLayout[I].StrokeJoin := TSkStrokeJoin.Round;
    if ARequest.Outlines[I].BlurRadius > 0 then
      Result.Outlines[I].MaskFilter := TSkMaskFilter.MakeBlur(
        TSkBlurStyle.Normal, ARequest.Outlines[I].BlurRadius);
  end;

  SetLength(Result.Shadows, Length(ARequest.Shadows));
  for I := 0 to High(ARequest.Shadows) do
  begin
    if (ARequest.Shadows[I].BlurRadius < 0) or
      (ARequest.Shadows[I].SpreadRadius < 0) then
      raise EArgumentOutOfRangeException.Create('Shadow blur and spread must not be negative');
    if ARequest.Shadows[I].SpreadRadius > 0 then
      Result.Shadows[I] := TSkPaint.Create(TSkPaintStyle.StrokeAndFill)
    else
      Result.Shadows[I] := TSkPaint.Create(TSkPaintStyle.Fill);
    Result.Shadows[I].AntiAlias := True;
    Result.Shadows[I].Color := ARequest.Shadows[I].Color;
    Result.Shadows[I].StrokeJoin := TSkStrokeJoin.Round;
    Result.Shadows[I].StrokeWidth := ARequest.Shadows[I].SpreadRadius * 2;
    if ARequest.Shadows[I].BlurRadius > 0 then
      Result.Shadows[I].MaskFilter := TSkMaskFilter.MakeBlur(
        TSkBlurStyle.Normal, ARequest.Shadows[I].BlurRadius);
  end;
end;

end.
