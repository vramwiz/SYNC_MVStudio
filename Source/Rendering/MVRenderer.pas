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
  const Schedule: TMVAnimationSchedule; SeedIndex, SequenceIndex, UnitCount: Integer): TMVMotion;
var InRank, OutRank: Integer;
begin
  InRank := MVAnimationOrderRank(Document.EntranceOrder, SequenceIndex, UnitCount);
  OutRank := MVAnimationOrderRank(Document.ExitOrder, SequenceIndex, UnitCount);
  Result := EvaluateMVMotion(Document, Time, Duration, Schedule, SeedIndex, InRank, OutRank);
end;

procedure PrepareMVGroups(const Document: TMVDocument; Layout: TMVLayout;
  const Appearance: TMVAppearanceFrame; UnitMode: Integer; out Groups: TMVAnimationGroups;
  out Count: Integer);
begin
  Count := Layout.DelayCount;
  if UnitMode = Ord(mauCharacter) then Exit;
  BuildMVAnimationGroups(Document, Layout, UnitMode, Groups);
  ExpandMVAnimationGroupBounds(Document, Layout, Appearance, Groups);
  Count := Groups.Count;
end;

procedure DrawMVDocumentFrame(const Canvas: ISkCanvas; const Document: TMVDocument; Layout: TMVLayout;
  Width, Height: Integer; X, Y, Time, Duration, EntranceTime, ExitTime, PresentTime, Opacity: Double;
  Pass: TMVRenderPass);
var
  I, G, AsyncGroup, UnitCount, InCount, HoldCount, OutCount, AsyncCount: Integer;
  ActiveMode, PresentMode, SeedIndex, PresentCount, PresentIndex: Integer;
  Motion, StaticMotion, PresentMotion: TMVMotion;
  Motions: array[0..MV_MAX_UNITS - 1] of TMVMotion; // 同じ文字を図形計測と描画で二重に時間評価しない。
  GroupMotions: array[0..MV_MAX_UNITS - 1] of TMVMotion; // まとまりごとに一度だけ時間評価する。
  InGroups, HoldGroups, OutGroups, AsyncGroups: TMVAnimationGroups;
  ActiveGroups, PresentGroups: PMVAnimationGroups;
  GroupMode: Boolean;
  Offset: TPointF;
  ShapeMotion: TMVShapeMotion;
  Schedule, ShapeSchedule, AsyncSchedule: TMVAnimationSchedule;
  ShapeBounds, GlyphBounds, LocalBounds: TRectF;
  HasShapeBounds, MeasureBounds, DrawShapes: Boolean;
  Paint: ISkPaint;
  UnitImage: TMVLayoutUnit;
  Appearance: TMVAppearanceFrame;
  AppearanceContext: TMVAppearanceContext;

begin
  if (Layout = nil) or (Length(Layout.Units) <> Length(Document.Units)) or
    (Length(Layout.Units) > MV_MAX_UNITS) then Exit;
  Appearance := EvaluateMVAppearance(Document.Appearance, Time, Duration);
  PrepareMVGroups(Document, Layout, Appearance, Document.EntranceUnit, InGroups, InCount);
  PrepareMVGroups(Document, Layout, Appearance, Document.HoldUnit, HoldGroups, HoldCount);
  PrepareMVGroups(Document, Layout, Appearance, Document.ExitUnit, OutGroups, OutCount);
  PrepareMVGroups(Document, Layout, Appearance, Document.PositionMotion.UnitMode, AsyncGroups, AsyncCount);
  Schedule := MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, InCount, OutCount);
  ShapeSchedule := MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, InCount, OutCount, True);
  AsyncSchedule := MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, AsyncCount, AsyncCount, True);
  ActiveMode := Document.HoldUnit;
  ActiveGroups := @HoldGroups;
  UnitCount := HoldCount;
  if Time < Schedule.EntranceSpan then
  begin
    ActiveMode := Document.EntranceUnit;
    ActiveGroups := @InGroups;
    UnitCount := InCount;
  end
  else if Time >= Duration - Schedule.ExitSpan then
  begin
    ActiveMode := Document.ExitUnit;
    ActiveGroups := @OutGroups;
    UnitCount := OutCount;
  end;
  GroupMode := (Time >= 0) and (ActiveMode <> Ord(mauCharacter));
  if GroupMode then
    for G := 0 to UnitCount - 1 do
      GroupMotions[G] := EvaluateMVUnitMotion(Document, Time, Duration, Schedule, G, G, UnitCount);
  PresentMode := Document.HoldUnit;
  PresentGroups := @HoldGroups;
  PresentCount := HoldCount;
  if PresentTime < Schedule.EntranceSpan then
  begin
    PresentMode := Document.EntranceUnit;
    PresentGroups := @InGroups;
    PresentCount := InCount;
  end
  else if PresentTime >= Duration - Schedule.ExitSpan then
  begin
    PresentMode := Document.ExitUnit;
    PresentGroups := @OutGroups;
    PresentCount := OutCount;
  end;
  ShapeMotion := EvaluateMVShape(Document.Shape, Time, Duration, ShapeSchedule.EntranceSpan, ShapeSchedule.ExitSpan);
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
    if GroupMode then G := ActiveGroups^.UnitGroups[I];
    if Time < 0 then Motions[I] := DefaultMVMotion
    else if G >= 0 then Motions[I] := GroupMotions[G]
    else Motions[I] := EvaluateMVUnitMotion(Document, Time, Duration, Schedule,
      I, UnitImage.DelayIndex, UnitCount);
    if (Time >= 0) and (Document.PositionMotion.Kind <> Ord(mpkNone)) then
    begin
      AsyncGroup := UnitImage.DelayIndex;
      if Document.PositionMotion.UnitMode <> Ord(mauCharacter) then
        AsyncGroup := AsyncGroups.UnitGroups[I];
      if AsyncGroup >= 0 then
      begin
        Offset := EvaluateMVPositionMotion(Document.PositionMotion, Time, Duration,
          AsyncSchedule, AsyncGroup,
          MVAnimationOrderRank(Document.EntranceOrder, AsyncGroup, AsyncCount),
          MVAnimationOrderRank(Document.ExitOrder, AsyncGroup, AsyncCount));
        Motions[I].X := Motions[I].X + Offset.X;
        Motions[I].Y := Motions[I].Y + Offset.Y;
      end;
    end;
    if (Time >= 0) and (Time < PresentTime) then
    begin
      // 過去像だけが退場後に残って文字を再表示しないよう、現在の表示状態も掛ける。
      PresentIndex := UnitImage.DelayIndex;
      SeedIndex := I;
      if PresentMode <> Ord(mauCharacter) then
      begin
        PresentIndex := PresentGroups^.UnitGroups[I];
        SeedIndex := PresentIndex;
      end;
      if PresentIndex < 0 then PresentIndex := 0;
      PresentMotion := EvaluateMVMotion(Document, PresentTime, Duration, Schedule, SeedIndex,
        MVAnimationOrderRank(Document.EntranceOrder, PresentIndex, PresentCount),
        MVAnimationOrderRank(Document.ExitOrder, PresentIndex, PresentCount));
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
        GlyphBounds := MVAnimatedGroupBounds(GlyphBounds, ActiveGroups^.Items[G].Pivot,
          ActiveGroups^.Items[G].TrackingIndex, Motions[I]);
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
      if GroupMode then G := ActiveGroups^.UnitGroups[I];
      if G >= 0 then
        DrawMVGroupedGlyph(Canvas, Document.Units[I], UnitImage, ActiveGroups^.Items[G], Motion, AppearanceContext, Paint)
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
