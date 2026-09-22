unit MVGroupEffects;

// まとまり共通の変形・切り抜き・グリッチを適用し、元の文字の重ね順で描く。
interface

uses System.Skia, MVDocument, MVLayout, MVAnimationGroups, MVAnimationTypes, MVAppearanceRenderer;

// 出力の中央原点へ移動済みのCanvasへ、動作グループに所属する1文字を描く。
procedure DrawMVGroupedGlyph(const Canvas: ISkCanvas; const Item: TMVPlacement; const Glyph: TMVLayoutUnit;
  const Group: TMVAnimationGroup; const Motion: TMVMotion; const Context: TMVAppearanceContext; const Paint: ISkPaint);

implementation

uses System.Types, MVGlyphEffects, MVGlyphPatterns;

procedure DrawMVGroupMember(const Canvas: ISkCanvas; const Item: TMVPlacement; const Glyph: TMVLayoutUnit;
  const Motion: TMVMotion; const Context: TMVAppearanceContext; const Paint: ISkPaint);
var LocalMotion: TMVMotion;
begin
  Canvas.Translate(Glyph.Position.X, Glyph.Position.Y);
  Canvas.Rotate(Item.Angle);
  Canvas.Skew(Item.Shear, 0);
  Canvas.Scale(Item.Scale * Item.ScaleX, Item.Scale * Item.ScaleY);
  LocalMotion := DefaultMVMotion;
  LocalMotion.Opacity := Motion.Opacity;
  LocalMotion.BlurSigma := Motion.BlurSigma;
  DrawMVStyledGlyph(Canvas, Glyph, LocalMotion, Context, Paint);
end;

procedure DrawMVGroupedGlyph(const Canvas: ISkCanvas; const Item: TMVPlacement; const Glyph: TMVLayoutUnit;
  const Group: TMVAnimationGroup; const Motion: TMVMotion; const Context: TMVAppearanceContext; const Paint: ISkPaint);
var I: Integer; Band: TRectF; Offset: Single;
begin
  if (Motion.ClipRight <= Motion.ClipLeft) or (Motion.ClipBottom <= Motion.ClipTop) or
    ((Motion.Mask <> mamNone) and (Motion.MaskVisibility <= 0)) then Exit;
  Canvas.Save;
  try
    Canvas.Translate(Group.Pivot.X + Motion.X + Motion.Tracking * Group.TrackingIndex, Group.Pivot.Y + Motion.Y);
    Canvas.Rotate(Motion.Angle);
    Canvas.Scale(Motion.Scale * Motion.ScaleX, Motion.Scale * Motion.ScaleY);
    Canvas.Translate(-Group.Pivot.X, -Group.Pivot.Y);
    ClipMVAnimatedBounds(Canvas, Group.Bounds, Motion);
    if Motion.GlitchAmount <= 0.01 then
      DrawMVGroupMember(Canvas, Item, Glyph, Motion, Context, Paint)
    else
      for I := 0 to MV_GLITCH_BANDS - 1 do
      begin
        Offset := MVGlitchBandOffset(I, Motion);
        Band := MVGlitchBandBounds(Group.Bounds, I, Motion.GlitchAmount);
        Canvas.Save;
        try
          Canvas.ClipRect(Band, TSkClipOp.Intersect, False);
          Canvas.Translate(Offset, 0);
          DrawMVGroupMember(Canvas, Item, Glyph, Motion, Context, Paint);
        finally
          Canvas.Restore;
        end;
      end;
  finally
    Canvas.Restore;
  end;
end;

end.
