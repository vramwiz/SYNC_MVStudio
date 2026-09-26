unit MVLayout;

// 文字単位のSkia画像と基準配置を作る。設定変更時だけ生成し、フレーム間で再利用する。
interface

uses System.Types, System.Skia, MVDocument;

type
  TMVLayoutUnit = record
    Image: ISkImage; // 装飾済み文字画像。参照カウントで寿命を管理する。
    BaseImage: ISkImage; // 時間装飾用の元文字。縁・影を含み、発光・色ずれ・枠は含まない。
    BaseShader: ISkShader; // 元文字のアルファで光を切り抜く、ローカル座標のシェーダー。
    GlowFilter, ChromaticFilter1, ChromaticFilter2: ISkColorFilter; // 書式色の固定フィルター。
    GlowBlur: ISkImageFilter; // 書式の半径を使う固定ぼかし。
    Style: TMVStyle; // 差分を解決済みの書式。時間装飾時も個別設定を保つ。
    Bounds: TRectF; // 文字の中心に対する装飾込み描画矩形。
    HitBounds: TRectF; // 光や色ずれに選択枠を膨らませない、元文字の矩形。
    Opacity: Single; // 書式の透明度。画像を保持して透明文字も再選択できる。
    Position: TPointF; // 出力中央からの文字中心座標。
    TrackingIndex: Single; // 改行を除いた行内順序と行中央との差。字間演出の基準。
    DelayIndex: Integer; // 空白・改行を除いたフレーズ内の順序。対象外は-1。
  end;

  TMVLayout = class
  private
    FUnits: TArray<TMVLayoutUnit>;
    FDelayCount: Integer; // 文字遅延の対象数。画像の有無やフォントへは依存しない。
  public
    // Documentから画像・配置を構築する。Skiaランタイム取得後に呼ぶ。
    constructor Create(const Document: TMVDocument);
    property Units: TArray<TMVLayoutUnit> read FUnits;
    property DelayCount: Integer read FDelayCount;
  end;

implementation

uses System.SysUtils, System.Math, System.Math.Vectors, System.UITypes,
  TextRendererTypes, TextRendererSkia, MVTextUnits, MVGlyphDecoration;

constructor TMVLayout.Create(const Document: TMVDocument);
var
  Renderer: TSkiaTextRenderer;
  Request: TTextRenderRequest;
  Raster: TTextRenderImage;
  Metrics: TTextRenderMetrics;
  Shadow: TTextRenderShadow;
  I, J, LineStart, LineEnd: Integer;
  X, Y, Advance, LineHeight, Width: Single;
  LayoutRect: TRect;
  Style: TMVStyle;
  TotalPixels: Int64;
begin
  inherited Create;
  ValidateMVDocument(Document);
  SetLength(FUnits, Length(Document.Units));
  Renderer := TSkiaTextRenderer.Create;
  try
    TotalPixels := 0;
    X := 0;
    Y := 0;
    LineStart := 0;
    LineHeight := Max(4, Document.Style.FontSize * 1.3 + Document.Style.LineSpacing);
    for I := 0 to High(FUnits) do
    begin
      FUnits[I].DelayIndex := -1;
      if IsMVDelayUnit(Document.Units[I].Text) then
      begin
        FUnits[I].DelayIndex := FDelayCount;
        Inc(FDelayCount);
      end;
      if Document.Units[I].Text <> #10 then
      begin
        Style := ResolveMVStyle(Document.Style, Document.Units[I]);
        Request := TTextRenderRequest.Default;
        Request.FontFamilies := [Style.FontName, 'Yu Gothic UI', 'Segoe UI Emoji'];
        Request.FontSize := Style.FontSize;
        Request.FillColor := Style.Color;
        if Style.FillMode = 2 then Request.FillColor := 0;
        if Style.Bold then Include(Request.FontStyle, TTextRenderFontStyleItem.Bold);
        if Style.Italic then Include(Request.FontStyle, TTextRenderFontStyleItem.Italic);
        if (Style.OutlineWidth > 0) and (Style.FillMode <> 1) then
          Request.Outlines := [TTextRenderOutline.Create(Style.OutlineWidth, Style.OutlineBlur, Style.OutlineColor)];
        if Style.Shadow then
        begin
          Shadow := Default(TTextRenderShadow);
          Shadow.Color := Style.ShadowColor;
          Shadow.BlurRadius := Style.ShadowBlur;
          Shadow.SpreadRadius := Style.ShadowSpread;
          Shadow.Offset := PointF(Style.ShadowX, Style.ShadowY);
          Request.Shadows := [Shadow];
        end;
        Request.Text := Document.Units[I].Text;
        Raster := Renderer.Render(Request, Metrics);
        try
          LayoutRect := Raster.LayoutBounds;
          Advance := Max(Document.Style.FontSize * 0.25, LayoutRect.Width);
          FUnits[I].Position := PointF(X + Advance / 2, Y);
          FUnits[I].Bounds := RectF(Raster.Bounds.Left - LayoutRect.Left - Advance / 2,
            Raster.Bounds.Top - LayoutRect.Top - LayoutRect.Height / 2,
            Raster.Bounds.Right - LayoutRect.Left - Advance / 2,
            Raster.Bounds.Bottom - LayoutRect.Top - LayoutRect.Height / 2);
          if not Raster.IsEmpty then
            FUnits[I].Image := TSkImage.MakeRasterCopy(TSkImageInfo.Create(Raster.Width, Raster.Height,
              TSkColorType.RGBA8888, TSkAlphaType.Unpremul), Raster.Data, Raster.Stride);
          FUnits[I].HitBounds := FUnits[I].Bounds;
          FUnits[I].Opacity := Style.Opacity;
          FUnits[I].Style := Style;
          FUnits[I].BaseImage := FUnits[I].Image;
          if FUnits[I].BaseImage <> nil then
          begin
            FUnits[I].BaseShader := FUnits[I].BaseImage.MakeShader(
              TMatrix.CreateScaling(FUnits[I].Bounds.Width / FUnits[I].Image.Width,
                FUnits[I].Bounds.Height / FUnits[I].Image.Height) *
                TMatrix.CreateTranslation(FUnits[I].Bounds.Left, FUnits[I].Bounds.Top),
              TSkSamplingOptions.High, TSkTileMode.Decal, TSkTileMode.Decal);
            if FUnits[I].BaseShader = nil then raise EOutOfMemory.Create('文字の光マスクを作成できません。');
            FUnits[I].GlowFilter := TSkColorFilter.MakeBlend(Style.GlowColor, TSkBlendMode.SrcIn);
            FUnits[I].GlowBlur := TSkImageFilter.MakeBlur(Style.GlowRadius, Style.GlowRadius);
            FUnits[I].ChromaticFilter1 := TSkColorFilter.MakeBlend(Style.ChromaticColor1, TSkBlendMode.SrcIn);
            FUnits[I].ChromaticFilter2 := TSkColorFilter.MakeBlend(Style.ChromaticColor2, TSkBlendMode.SrcIn);
          end;
          FUnits[I].Image := DecorateMVGlyph(FUnits[I].Image, FUnits[I].HitBounds, Style, FUnits[I].Bounds);
          if FUnits[I].Image <> nil then
          begin
            TotalPixels := TotalPixels + Int64(FUnits[I].Image.Width) * FUnits[I].Image.Height;
            // 同じ画像への追加参照は重複計上せず、焼き込みで別画像になった場合だけ元画像も数える。
            if (FUnits[I].BaseImage <> nil) and (FUnits[I].BaseImage <> FUnits[I].Image) then
              TotalPixels := TotalPixels + Int64(FUnits[I].BaseImage.Width) * FUnits[I].BaseImage.Height;
            if TotalPixels > 16777216 then
              raise EArgumentException.Create('文字画像の合計サイズが上限を超えています。');
          end;
          X := X + Advance + Document.Style.Spacing;
        finally
          Raster.Free;
        end;
      end;
      if (Document.Units[I].Text = #10) or (I = High(FUnits)) then
      begin
        Width := Max(0, X - Document.Style.Spacing);
        for J := LineStart to I do FUnits[J].Position.X := FUnits[J].Position.X - Width / 2;
        LineEnd := I;
        if Document.Units[I].Text = #10 then Dec(LineEnd);
        for J := LineStart to LineEnd do
          FUnits[J].TrackingIndex := J - (LineStart + LineEnd) / 2;
        LineStart := I + 1;
        X := 0;
        if I < High(FUnits) then Y := Y + LineHeight;
      end;
    end;
    for I := 0 to High(FUnits) do
    begin
      FUnits[I].Position.Y := FUnits[I].Position.Y - Y / 2;
      if Document.Units[I].Positioned then
        FUnits[I].Position := PointF(Document.Units[I].X, Document.Units[I].Y);
    end;
  finally
    Renderer.Free;
  end;
end;

end.
