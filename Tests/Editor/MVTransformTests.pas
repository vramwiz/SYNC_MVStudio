unit MVTransformTests;

// 回転済み文字の全ハンドル、角度スナップ、縦横倍率の保存互換性を検証する。
interface

// 数学上の固定点と保存復元をGUIから独立して確認する。
procedure RunTransformTests;

implementation

uses System.Types, System.SysUtils, System.JSON, System.Math, System.Generics.Collections, MVDocument, MVTextUnits,
  MVDocumentJson, MVPlacementDocument, MVTransformGeometry, MVTestAssert;

procedure CheckHandles(Angle: Single; Shear: Single = 0);
const Opposite: array[mhNW..mhW] of TMVHandle = (mhSE, mhS, mhSW, mhW, mhNW, mhN, mhNE, mhE);
var D: TMVDocument; Original, Changed: TMVPlacement; R: TRectF;
  A, B: TMVHandlePoints; H: TMVHandle; Move: TPointF; RatioX, RatioY: Single;
begin
  D := DefaultMVDocument;
  SetMVText(D, '歌');
  Original := D.Units[0];
  Original.X := 80;
  Original.Y := -40;
  Original.Angle := Angle;
  Original.Shear := Shear;
  Original.ScaleX := 1.4;
  Original.ScaleY := 0.8;
  R := RectF(-35, -50, 45, 55);
  A := MVHandles(Original, R, 28);
  for H := mhNW to mhW do
  begin
    Move := (A[H] - A[Opposite[H]]) * 0.3;
    Changed := MVTransform(Original, R, H, A[H], A[H] + Move, False, False);
    B := MVHandles(Changed, R, 28);
    Check((A[Opposite[H]] - B[Opposite[H]]).Length < 0.001, 'opposite handle remains fixed after rotated scale');
    RatioX := Changed.ScaleX / Original.ScaleX;
    RatioY := Changed.ScaleY / Original.ScaleY;
    if H in [mhNW, mhNE, mhSE, mhSW] then
      Check((Abs(RatioX - 1.3) < 0.001) and (Abs(RatioY - 1.3) < 0.001), 'corner preserves existing aspect ratio')
    else if H in [mhW, mhE] then
      Check((Abs(RatioX - 1.3) < 0.001) and (RatioY = 1), 'side changes width only')
    else
      Check((RatioX = 1) and (Abs(RatioY - 1.3) < 0.001), 'top or bottom changes height only');
  end;
  Original.Angle := 0;
  Changed := MVTransform(Original, R, mhRotate, PointF(80, -140),
    PointF(80, -40) + MVRotate(PointF(0, -100), 28), True, False);
  Check(Changed.Angle = 30, 'nearby angle snaps to 15 degree increment');
  Changed := MVTransform(Original, R, mhRotate, PointF(80, -140),
    PointF(80, -40) + MVRotate(PointF(0, -100), 22), False, True);
  Check(Changed.Angle = 15, 'Shift constrains angle even outside magnetic threshold');
  Changed := MVTransform(Original, R, mhRotate, PointF(80, -140),
    PointF(80, -40) + MVRotate(PointF(0, -100), 28), False, False);
  Check(Abs(Changed.Angle - 28) < 0.001, 'rotation can bypass snapping');
end;

procedure CheckStorage;
var D, Restored, Host: TMVDocument; Data, Error: string; Root, Placement: TJSONObject;
begin
  D := DefaultMVDocument;
  Check(D.Style.FontSize = 100, 'new documents start at 100 output pixels');
  SetMVText(D, '文字');
  D.Units[0].ScaleX := 2;
  D.Units[0].ScaleY := 0.6;
  D.EditorSettings := True;
  D.Style.FontSize := 130;
  D.Hold := 3;
  Data := EncodeMVDocument(D);
  Check(TryDecodeMVDocument(Data, Restored, Error), 'current document version decodes');
  Check((Restored.Units[0].ScaleX = 2) and (Abs(Restored.Units[0].ScaleY - 0.6) < 0.001),
    'independent stretch survives save and reload');
  Host := DefaultMVDocument;
  Host.Text := '文字追加';
  ApplyMVHostDocument(Restored, Host);
  Check((Restored.Text = Host.Text) and (Restored.Style.FontSize = 130) and (Restored.Hold = Host.Hold),
    'editor style survives while host animation refreshes');
  Root := TJSONObject.ParseJSONValue(Data) as TJSONObject;
  try
    Root.RemovePair('version').Free;
    Root.AddPair('version', TJSONNumber.Create(2));
    Check(TryDecodeMVDocument(Root.ToJSON, Restored, Error) and (Restored.Units[0].Shear = 0),
      'legacy version 2 defaults missing shear to zero');
    Root.RemovePair('version').Free;
    Root.AddPair('version', TJSONNumber.Create(1));
    Root.RemovePair('editorSettings').Free;
    Placement := Root.GetValue<TJSONArray>('placements').Items[0] as TJSONObject;
    Placement.RemovePair('scaleX').Free;
    Placement.RemovePair('scaleY').Free;
    Check(TryDecodeMVDocument(Root.ToJSON, Restored, Error), 'legacy version 1 remains readable');
    Check((Restored.Units[0].ScaleX = 1) and (Restored.Units[0].ScaleY = 1) and not Restored.EditorSettings,
      'legacy stretch defaults to one and preserves host settings ownership');
  finally Root.Free; end;
end;

procedure RunTransformTests;
begin
  CheckHandles(0);
  CheckHandles(37);
  CheckHandles(37, 0.45);
  CheckStorage;
  Writeln('Handles, snapping and legacy storage: OK');
end;

end.
