unit MVRenderer;

// ホスト出力と編集プレビューが共用する描画処理。背面図形・歌詞・前面図形の順に合成する。
interface

uses System.Skia, MVDocument, MVLayout;

// Canvasの状態を保ち、指定時刻の1フレーズを描く。Time<0は静止編集用の基準状態。
procedure DrawMVDocument(const Canvas: ISkCanvas; const Document: TMVDocument; Layout: TMVLayout;
  Width, Height: Integer; X, Y, Time, Duration, EntranceTime, ExitTime: Double);

implementation

uses System.Types, System.Math, MVAnimation, MVAnimationTypes, MVGlyphEffects,
  MVShapeTypes, MVShapeAnimation, MVShapeRenderer, MVAnimatedBounds, MVAnimationTime,
  MVAnimationGroups, MVAnimationSequence, MVGroupEffects, MVAppearanceTypes, MVAppearanceRenderer,
  MVPositionMotionTypes, MVPositionMotion;

type
  TMVRenderPass = (mrAll, mrLetters, mrBackground, mrForegroundAndLetters);

function EvaluateMVUnitMotion(const Document: TMVDocument; Time, Duration: Double;
  const Schedule, AuxiliarySchedule: TMVAnimationSchedule; SeedIndex, SequenceIndex, UnitCount: Integer): TMVMotion;
var InRank, OutRank: Integer; Offset: TPointF;
begin
  InRank := MVAnimationOrderRank(Document.EntranceOrder, SequenceIndex, UnitCount);
  OutRank := MVAnimationOrderRank(Document.ExitOrder, SequenceIndex, UnitCount);
  Result := EvaluateMVMotion(Document, Time, Duration, Schedule, SeedIndex, InRank, OutRank);
  if Document.PositionMotion.Target = Ord(mptAnimationUnit) then
  begin
    // 既存演出の種には従来の番号を使い、追加位相には空白を除いた番号を使う。
    Offset := EvaluateMVPositionMotion(Document.PositionMotion, Time, Duration,
      AuxiliarySchedule, SequenceIndex, InRank, OutRank);
    Result.X := Result.X + Offset.X;
    Result.Y := Result.Y + Offset.Y;
  end;
end;

procedure DrawMVDocumentFrame(const Canvas: ISkCanvas; const Document: TMVDocument; Layout: TMVLayout;
  Width, Height: Integer; X, Y, Time, Duration, EntranceTime, ExitTime, PresentTime, Opacity: Double;
  Pass: TMVRenderPass);
var
  I, G, UnitCount: Integer;
  Motion, StaticMotion, PresentMotion: TMVMotion;
  Motions: array[0..MV_MAX_UNITS - 1] of TMVMotion; // 同じ文字を図形計測と描画で二重に時間評価しない。
  GroupMotions: array[0..MV_MAX_UNITS - 1] of TMVMotion; // まとまりごとに一度だけ時間評価する。
  Groups: TMVAnimationGroups;
  GroupMode, ExtraPhrase: Boolean;
  PhraseOffset: TPointF;
  ShapeMotion: TMVShapeMotion;
  Schedule, AuxiliarySchedule: TMVAnimationSchedule;
  ShapeBounds, GlyphBounds, LocalBounds: TRectF;
  HasShapeBounds, MeasureBounds, DrawShapes: Boolean;
  Paint: ISkPaint;
  UnitImage: TMVLayoutUnit;
  Appearance: TMVAppearanceFrame;
  AppearanceContext: TMVAppearanceContext;

begin
  if (Layout = nil) or (Length(Layout.Units) <> Length(Document.Units)) or
    (Length(Layout.Units) > MV_MAX_UNITS) then Exit;
  GroupMode := (Time >= 0) and (Document.AnimationUnit <> Ord(mauCharacter));
  ExtraPhrase := (Time >= 0) and (Document.PositionMotion.Kind <> Ord(mpkNone)) and
    (Document.PositionMotion.Target = Ord(mptPhrase));
  Appearance := EvaluateMVAppearance(Document.Appearance, Time, Duration);
  UnitCount := Layout.DelayCount;
  if GroupMode then
  begin
    // 所属を組版から分離し、ホストの単位切替では文字画像を作り直さない。
    BuildMVAnimationGroups(Document, Layout, Groups);
    ExpandMVAnimationGroupBounds(Document, Layout, Appearance, Groups);
    UnitCount := Groups.Count;
  end;
  Schedule := MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, UnitCount);
  // 図形と追加移動は、基本演出が「なし」でもホストの登場/退場時間を使える。
  AuxiliarySchedule := MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, UnitCount, True);
  PhraseOffset := PointF(0, 0);
  if ExtraPhrase then
    PhraseOffset := EvaluateMVPositionMotion(Document.PositionMotion, Time, Duration, AuxiliarySchedule, 0, 0, 0);
  if GroupMode then
    for G := 0 to Groups.Count - 1 do
      GroupMotions[G] := EvaluateMVUnitMotion(Document, Time, Duration, Schedule, AuxiliarySchedule, G, G, UnitCount);
  ShapeMotion := EvaluateMVShape(Document.Shape, Time, Duration, AuxiliarySchedule.EntranceSpan, AuxiliarySchedule.ExitSpan);
  DrawShapes := Pass <> mrLetters;
  MeasureBounds := (DrawShapes and (Document.Shape.EffectID <> MV_SHAPE_NONE) and
    (Document.Shape.Opacity > 0) and (ShapeMotion.Visibility > 0)) or
    (Appearance.SweepVisible and (Pass <> mrBackground));
  HasShapeBounds := False;
  ShapeBounds := TRectF.Empty;
  for I := 0 to High(Layout.Units) do
  begin
    UnitImage := Layout.Units[I];
    if UnitImage.Image = nil then Continue;
    G := -1;
    if GroupMode then G := Groups.UnitGroups[I];
    if Time < 0 then Motions[I] := DefaultMVMotion
    else if G >= 0 then Motions[I] := GroupMotions[G]
    else Motions[I] := EvaluateMVUnitMotion(Document, Time, Duration, Schedule, AuxiliarySchedule,
      I, UnitImage.DelayIndex, UnitCount);
    if ExtraPhrase then
    begin
      Motions[I].X := Motions[I].X + PhraseOffset.X;
      Motions[I].Y := Motions[I].Y + PhraseOffset.Y;
    end;
    if (Time >= 0) and (Time < PresentTime) then
    begin
      // 過去像だけが退場後に残って文字を再表示しないよう、現在の表示状態も掛ける。
      if G >= 0 then
        PresentMotion := EvaluateMVMotion(Document, PresentTime, Duration, Schedule, G,
          MVAnimationOrderRank(Document.EntranceOrder, G, UnitCount),
          MVAnimationOrderRank(Document.ExitOrder, G, UnitCount))
      else
        PresentMotion := EvaluateMVMotion(Document, PresentTime, Duration, Schedule, I,
          MVAnimationOrderRank(Document.EntranceOrder, UnitImage.DelayIndex, UnitCount),
          MVAnimationOrderRank(Document.ExitOrder, UnitImage.DelayIndex, UnitCount));
      Motions[I].Opacity := Motions[I].Opacity * PresentMotion.Opacity;
      if (PresentMotion.Scale <= 0) or (PresentMotion.ScaleX <= 0.0001) or (PresentMotion.ScaleY <= 0.0001) or
        (PresentMotion.ClipRight <= PresentMotion.ClipLeft) or
        (PresentMotion.ClipBottom <= PresentMotion.ClipTop) or
        ((PresentMotion.Mask <> mamNone) and (PresentMotion.MaskVisibility <= 0)) then Motions[I].Opacity := 0;
    end;
    Motions[I].Opacity := Motions[I].Opacity * UnitImage.Opacity * Opacity;
    if MeasureBounds then
    begin
      LocalBounds := MVAppearanceBounds(UnitImage, Appearance);
      if G >= 0 then
      begin
        StaticMotion := DefaultMVMotion;
        StaticMotion.BlurSigma := Motions[I].BlurSigma;
        GlyphBounds := MVAnimatedGlyphBounds(Document.Units[I], LocalBounds, UnitImage.Position, 0, StaticMotion);
        GlyphBounds := MVAnimatedGroupBounds(GlyphBounds, Groups.Items[G].Pivot,
          Groups.Items[G].TrackingIndex, Motions[I]);
      end
      else
        GlyphBounds := MVAnimatedGlyphBounds(Document.Units[I], LocalBounds,
          UnitImage.Position, UnitImage.TrackingIndex, Motions[I]);
      if not HasShapeBounds then ShapeBounds := GlyphBounds
      else
      begin
        ShapeBounds.Left := Min(ShapeBounds.Left, GlyphBounds.Left);
        ShapeBounds.Top := Min(ShapeBounds.Top, GlyphBounds.Top);
        ShapeBounds.Right := Max(ShapeBounds.Right, GlyphBounds.Right);
        ShapeBounds.Bottom := Max(ShapeBounds.Bottom, GlyphBounds.Bottom);
      end;
      HasShapeBounds := True;
    end;
  end;
  if HasShapeBounds then
  begin
    ShapeBounds.Offset(Width / 2 + X, Height / 2 + Y);
    if (Pass in [mrAll, mrBackground]) and not Document.Shape.Foreground then
      DrawMVShape(Canvas, ShapeBounds, Document.Shape, ShapeMotion);
  end;
  if Pass = mrBackground then Exit;
  AppearanceContext := CreateMVAppearanceContext(Canvas, ShapeBounds, Appearance);
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  for I := 0 to High(Layout.Units) do
  begin
    UnitImage := Layout.Units[I];
    if UnitImage.Image = nil then Continue;
    Motion := Motions[I];
    if (Motion.Opacity <= 0) or (Motion.Scale <= 0) or (Motion.ScaleX <= 0.0001) or (Motion.ScaleY <= 0.0001) then Continue;
    Canvas.Save;
    try
      Canvas.Translate(Width / 2 + X, Height / 2 + Y);
      G := -1;
      if GroupMode then G := Groups.UnitGroups[I];
      if G >= 0 then
        DrawMVGroupedGlyph(Canvas, Document.Units[I], UnitImage, Groups.Items[G], Motion, AppearanceContext, Paint)
      else
      begin
        Canvas.Translate(UnitImage.Position.X + Motion.X + Motion.Tracking * UnitImage.TrackingIndex,
          UnitImage.Position.Y + Motion.Y);
        Canvas.Rotate(Document.Units[I].Angle + Motion.Angle);
        Canvas.Skew(Document.Units[I].Shear, 0);
        Canvas.Scale(Document.Units[I].Scale * Document.Units[I].ScaleX * Motion.Scale * Motion.ScaleX,
          Document.Units[I].Scale * Document.Units[I].ScaleY * Motion.Scale * Motion.ScaleY);
        DrawMVStyledGlyph(Canvas, UnitImage, Motion, AppearanceContext, Paint);
      end;
    finally
      Canvas.Restore;
    end;
  end;
  if DrawShapes and HasShapeBounds and Document.Shape.Foreground then
    DrawMVShape(Canvas, ShapeBounds, Document.Shape, ShapeMotion);
end;

procedure DrawMVDocument(const Canvas: ISkCanvas; const Document: TMVDocument; Layout: TMVLayout;
  Width, Height: Integer; X, Y, Time, Duration, EntranceTime, ExitTime: Double);
var I: Integer; SampleTime, Opacity: Double; Echoes: Boolean;
begin
  if IsNan(Time) or IsInfinite(Time) or IsNan(Duration) or IsInfinite(Duration) then Exit;
  if (Time >= 0) and ((Duration <= 0) or (Time >= Duration)) then Exit;
  Echoes := (Time >= 0) and (Document.Appearance.EchoCount > 0) and
    (Document.Appearance.EchoOpacity > 0);
  if not Echoes then
  begin
    DrawMVDocumentFrame(Canvas, Document, Layout, Width, Height, X, Y, Time, Duration,
      EntranceTime, ExitTime, Time, 1, mrAll);
    Exit;
  end;
  if (Document.Shape.EffectID <> MV_SHAPE_NONE) and not Document.Shape.Foreground then
    DrawMVDocumentFrame(Canvas, Document, Layout, Width, Height, X, Y, Time, Duration,
      EntranceTime, ExitTime, Time, 1, mrBackground);
  // 古い像から描き、最後に現在の文字を置く。画像や過去フレームを蓄積しない。
  for I := Document.Appearance.EchoCount downto 1 do
  begin
    SampleTime := Time - I * Document.Appearance.EchoInterval;
    if SampleTime < 0 then Continue;
    Opacity := Document.Appearance.EchoOpacity;
    if I > 1 then Opacity := Opacity * Power(Document.Appearance.EchoDecay, I - 1);
    if Opacity <= 0 then Continue;
    DrawMVDocumentFrame(Canvas, Document, Layout, Width, Height, X, Y, SampleTime, Duration,
      EntranceTime, ExitTime, Time, Opacity, mrLetters);
  end;
  DrawMVDocumentFrame(Canvas, Document, Layout, Width, Height, X, Y, Time, Duration,
    EntranceTime, ExitTime, Time, 1, mrForegroundAndLetters);
end;

end.
