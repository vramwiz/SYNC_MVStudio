unit MVAnimationGroups;

// 配置から動作単位を組み立てる。文字画像の再生成やフレームごとの配列確保は行わない。
interface

uses System.Types, MVDocument, MVLayout, MVAppearanceTypes;

type
  TMVAnimationGroup = record
    Bounds: TRectF; // 個別の回転・拡縮を反映した静止時の描画範囲。
    Pivot: TPointF; // まとまり全体の回転・拡縮中心。
    TrackingIndex: Single; // まとまり間の字間演出に使う中央からの順序。
    HasBounds: Boolean; // 画像を持たない文字だけの単位を識別する。
  end;

  TMVAnimationGroups = record
    Count: Integer; // 空白・空行を除く動作単位数。
    UnitGroups: array[0..MV_MAX_UNITS - 1] of Integer; // 各文字の動作単位。対象外は-1。
    Items: array[0..MV_MAX_UNITS - 1] of TMVAnimationGroup; // 最初の出現順に並ぶ動作単位。
  end;

// 行・登録グループ・フレーズの所属と基準矩形を求める。未登録文字はそれぞれ独立させる。
procedure BuildMVAnimationGroups(const Document: TMVDocument; Layout: TMVLayout; out Groups: TMVAnimationGroups);
// 動作中心を動かさず、時間装飾の最大範囲をクリップ矩形だけへ追加する。
procedure ExpandMVAnimationGroupBounds(const Document: TMVDocument; Layout: TMVLayout;
  const Frame: TMVAppearanceFrame; var Groups: TMVAnimationGroups);

implementation

uses System.Math, MVAnimationSequence, MVAnimationTypes, MVAnimatedBounds, MVAppearanceRenderer;

procedure ExpandMVAnimationGroupBounds(const Document: TMVDocument; Layout: TMVLayout;
  const Frame: TMVAppearanceFrame; var Groups: TMVAnimationGroups);
var I, G: Integer; B: TRectF;
begin
  if not Frame.Active or ((Frame.GlowMix <= 0) and (Frame.ChromaticMargin <= 0)) then Exit;
  for I := 0 to High(Document.Units) do
  begin
    G := Groups.UnitGroups[I];
    if (G < 0) or (Layout.Units[I].Image = nil) then Continue;
    B := MVAnimatedGlyphBounds(Document.Units[I], MVAppearanceBounds(Layout.Units[I], Frame),
      Layout.Units[I].Position, 0, DefaultMVMotion);
    Groups.Items[G].Bounds.Left := Min(Groups.Items[G].Bounds.Left, B.Left);
    Groups.Items[G].Bounds.Top := Min(Groups.Items[G].Bounds.Top, B.Top);
    Groups.Items[G].Bounds.Right := Max(Groups.Items[G].Bounds.Right, B.Right);
    Groups.Items[G].Bounds.Bottom := Max(Groups.Items[G].Bounds.Bottom, B.Bottom);
  end;
end;

procedure BuildMVAnimationGroups(const Document: TMVDocument; Layout: TMVLayout; out Groups: TMVAnimationGroups);
var
  Registered: array[0..MV_MAX_UNITS] of Integer;
  I, G, ID, LineGroup: Integer;
  B: TRectF;
begin
  Groups := Default(TMVAnimationGroups);
  FillChar(Groups.UnitGroups, SizeOf(Groups.UnitGroups), $FF);
  FillChar(Registered, SizeOf(Registered), $FF);
  LineGroup := -1;
  for I := 0 to High(Document.Units) do
  begin
    if Document.Units[I].Text = #10 then LineGroup := -1;
    if Layout.Units[I].DelayIndex < 0 then Continue;
    G := -1;
    ID := Document.Units[I].AnimationGroup;
    case TMVAnimationUnit(Document.AnimationUnit) of
      mauLine: G := LineGroup;
      mauGroup: if ID > 0 then G := Registered[ID];
      mauPhrase: if Groups.Count > 0 then G := 0;
    end;
    if G < 0 then
    begin
      G := Groups.Count;
      Inc(Groups.Count);
    end;
    Groups.UnitGroups[I] := G;
    LineGroup := G;
    if ID > 0 then Registered[ID] := G;
  end;
  for I := 0 to High(Document.Units) do
  begin
    G := Groups.UnitGroups[I];
    if (G < 0) or (Layout.Units[I].Image = nil) then Continue;
    B := MVAnimatedGlyphBounds(Document.Units[I], Layout.Units[I].Bounds,
      Layout.Units[I].Position, 0, DefaultMVMotion);
    if not Groups.Items[G].HasBounds then Groups.Items[G].Bounds := B
    else
    begin
      Groups.Items[G].Bounds.Left := Min(Groups.Items[G].Bounds.Left, B.Left);
      Groups.Items[G].Bounds.Top := Min(Groups.Items[G].Bounds.Top, B.Top);
      Groups.Items[G].Bounds.Right := Max(Groups.Items[G].Bounds.Right, B.Right);
      Groups.Items[G].Bounds.Bottom := Max(Groups.Items[G].Bounds.Bottom, B.Bottom);
    end;
    Groups.Items[G].HasBounds := True;
  end;
  for G := 0 to Groups.Count - 1 do
  begin
    Groups.Items[G].Pivot := Groups.Items[G].Bounds.CenterPoint;
    Groups.Items[G].TrackingIndex := G - (Groups.Count - 1) / 2;
  end;
end;

end.
