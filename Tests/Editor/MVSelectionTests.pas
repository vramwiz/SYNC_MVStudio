unit MVSelectionTests;

// 複数文字の共通変形、範囲選択、書式バーを実キャンバスと保存データで検証する。
interface

// テスト所有のフォームだけを操作し、ユーザーのAviUtl2には触れない。
procedure RunSelectionTests;

implementation

uses System.SysUtils, System.Types, System.Classes, System.Math, Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.StdCtrls, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage, MVDocument, MVTextUnits, MVDocumentJson, MVEditSession,
  MVLayout, MVSelection, MVTransformGeometry, MVEditorForm, MVEditorCanvas, MVFontToolbar,
  MVPlacementToolbar, MVTestAssert, TextRendererSkiaRuntime, TextRendererSkiaBootstrap;

type
  TCanvasAccess = class(TMVEditorCanvas)
  public
    // マウスの押下・移動・解放を1操作として送る。
    procedure Drag(const A, B: TPointF; Shift: TShiftState = []);
    // EscとCtrl+Aを含むショートカット入力。
    procedure Press(Key: Word; Shift: TShiftState = []);
  end;

procedure TCanvasAccess.Drag(const A, B: TPointF; Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, Round(A.X), Round(A.Y));
  MouseMove(Shift + [ssLeft], Round(B.X), Round(B.Y));
  MouseUp(mbLeft, Shift, Round(B.X), Round(B.Y));
end;

procedure TCanvasAccess.Press(Key: Word; Shift: TShiftState);
begin KeyDown(Key, Shift); end;

procedure CheckAffineSelection;
var D, Saved: TMVDocument; Session: TMVEditSession; Layout: TMVLayout; Selection: TMVSelection;
  Item, Changed: TMVPlacement; R: TRectF; Before, After, Handles: TMVHandlePoints;
  H: TMVHandle; Expected: TPointF; Error: string; I: Integer;
begin
  D := DefaultMVDocument; SetMVText(D, '歌詞');
  D.Units[0].Angle := 37; D.Units[1].Angle := -18;
  Session := TMVEditSession.Create(D); Layout := TMVLayout.Create(D); Selection := TMVSelection.Create;
  try
    Selection.Attach(Session, Layout); Selection.SelectAll;
    Selection.Frame(Item, R); Handles := MVHandles(Item, R, 28);
    Selection.BeginTransform;
    Changed := MVTransform(Item, R, mhE, Handles[mhE], Handles[mhE] + PointF(R.Width * 0.6, 0), False, False);
    Selection.ApplyFrame(Changed);
    for I := 0 to 1 do
    begin
      Item := D.Units[I];
      // 元の文書は自動配置なので、元組版を使って比較する。
      Layout.Free; Layout := TMVLayout.Create(D);
      Item.X := Layout.Units[I].Position.X; Item.Y := Layout.Units[I].Position.Y;
      Before := MVHandles(Item, Layout.Units[I].Bounds, 0);
      After := MVHandles(Session.Document.Units[I], Layout.Units[I].Bounds, 0);
      for H := mhNW to mhW do
      begin
        Expected := PointF(Handles[mhW].X + (Before[H].X - Handles[mhW].X) * 1.6, Before[H].Y);
        Check((After[H] - Expected).Length < 0.002, 'rotated glyph follows exact group nonuniform transform');
      end;
    end;
    Selection.Attach(Session, Layout);
    Selection.Finish(False);
    Check(Abs(Session.Document.Units[0].Shear) > 0.1, 'group stretch retains required shear');
    Check(TryDecodeMVDocument(EncodeMVDocument(Session.Document), Saved, Error), 'group transform can be saved');
    Check(Abs(Saved.Units[0].Shear - Session.Document.Units[0].Shear) < 0.00001, 'shear survives round trip');
    Session.Undo;
    Check(not Session.Document.Units[0].Positioned and not Session.Document.Units[1].Positioned,
      'one group undo restores original automatic positions');
    Session.Redo;
    Check(Session.Document.Units[0].Positioned and Session.Document.Units[1].Positioned, 'group redo restores all letters');
  finally Selection.Free; Layout.Free; Session.Free; end;
end;

procedure CheckEditorSelection;
var D, Saved: TMVDocument; Form: TMVEditorForm; Canvas: TCanvasAccess; Toolbar: TMVFontToolbar;
  I, N: Integer; CanClose: Boolean; A, B, P: TPointF; Handles: TMVHandlePoints;
  Bitmap: TBitmap; PNG: TPngImage; Family: TComboBox; Button: TMVFontButton; SizeEdit: TEdit; MovedX: Single;
begin
  D := DefaultMVDocument; SetMVText(D, '歌詞集');
  for I := 0 to 2 do begin D.Units[I].X := -200 + I * 200; D.Units[I].Positioned := True; end;
  Form := TMVEditorForm.CreateEditor(D, 800, 400, 5, 0.3, 0.3,
    function(const Document: TMVDocument): string
    begin Saved := CloneMVDocument(Document); Result := ''; end);
  try
    Canvas := nil; Toolbar := nil;
    for I := 0 to Form.ComponentCount - 1 do
    begin
      if Form.Components[I] is TMVEditorCanvas then Canvas := TCanvasAccess(Form.Components[I]);
      if Form.Components[I] is TMVFontToolbar then Toolbar := TMVFontToolbar(Form.Components[I]);
    end;
    Check((Canvas <> nil) and (Toolbar <> nil), 'editor owns canvas and inline font toolbar');
    Form.Position := poDesigned; Form.Left := -30000; Form.Top := -30000; Form.ShowInTaskBar := False;
    Form.Show; Form.Update; Canvas.SnapEnabled := False;
    A := Canvas.DocumentToScreen(PointF(-270, -80)); B := Canvas.DocumentToScreen(PointF(70, 80));
    Canvas.Drag(A, B);
    Check(Canvas.SelectionCount = 2, 'left drag selects only letters intersecting marquee');
    P := Canvas.DocumentToScreen(PointF(-200, 0));
    Canvas.Drag(P, P + PointF(40, -20));
    Form.OnCloseQuery(Form, CanClose);
    MovedX := Saved.Units[0].X;
    Check((MovedX > -200) and (Abs((Saved.Units[1].X - Saved.Units[0].X) - 200) < 0.001),
      'selected letters move together and preserve separation');
    Check(Saved.Units[2].X = 200, 'unselected letter stays unchanged');
    Handles := Canvas.SelectionHandles;
    Canvas.Drag(Handles[mhSE], Handles[mhSE] + (Handles[mhSE] - Handles[mhNW]) * 0.25);
    Form.OnCloseQuery(Form, CanClose);
    Check((Saved.Units[0].ScaleX > 1.2) and (Saved.Units[1].ScaleX > 1.2) and (Saved.Units[2].ScaleX = 1),
      'common corner scales selected letters only');
    Bitmap := TBitmap.Create; PNG := TPngImage.Create;
    try
      Bitmap.SetSize(Form.ClientWidth, Form.ClientHeight);
      Form.PaintTo(Bitmap.Canvas, 0, 0); PNG.Assign(Bitmap);
      PNG.SaveToFile(ExtractFilePath(ParamStr(0)) + 'editor-group-preview.png');
    finally PNG.Free; Bitmap.Free; end;
    for I := 0 to Form.ComponentCount - 1 do
      if (Form.Components[I] is TMVPlacementButton) and (TControl(Form.Components[I]).Tag = Ord(mpcUndo)) then
        TMVPlacementButton(Form.Components[I]).Click;
    Form.OnCloseQuery(Form, CanClose);
    Check((Saved.Units[0].ScaleX = 1) and (Saved.Units[0].X = MovedX), 'one undo reverts only last group operation');
    Canvas.Press(VK_ESCAPE); Check(Canvas.SelectionCount = 0, 'Escape clears group selection');
    Canvas.Press(Ord('A'), [ssCtrl]); Check(Canvas.SelectionCount = 3, 'Ctrl+A selects all visible letters');
    P := Canvas.DocumentToScreen(PointF(200, 0)); Canvas.Drag(P, P, [ssShift]);
    Check(Canvas.SelectionCount = 2, 'Shift click removes a letter from selection');
    Canvas.CancelInteraction(True);
    Family := nil; SizeEdit := nil; N := 0;
    for I := 0 to Toolbar.ComponentCount - 1 do
    begin
      if Toolbar.Components[I] is TComboBox then Family := TComboBox(Toolbar.Components[I]);
      if (Toolbar.Components[I] is TEdit) and (SizeEdit = nil) then SizeEdit := TEdit(Toolbar.Components[I]);
      if Toolbar.Components[I] is TMVFontButton then
      begin
        Button := TMVFontButton(Toolbar.Components[I]); Inc(N);
        if Button.Tag <= Ord(mfaShadow) then
        begin
          Button.Perform(WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(10, 10));
          Button.Perform(WM_LBUTTONUP, 0, MakeLParam(10, 10));
        end;
      end;
    end;
    Check((N = 6) and (Family <> nil) and (Family.Style = csDropDownList), 'font combo and six decoration buttons present');
    Check(Family.Items.Count > 1, 'font combo contains installed families');
    Family.ItemIndex := Family.Items.IndexOf('Arial');
    Check(Family.ItemIndex >= 0, 'test font installed');
    Family.OnChange(Family);
    SizeEdit.Text := '128'; Toolbar.CommitPending;
    Form.OnCloseQuery(Form, CanClose);
    Check((Saved.Style.FontName = 'Arial') and (Saved.Style.FontSize = 128), 'inline font and size reach saved document');
    Check(Saved.Style.Bold and Saved.Style.Italic and Saved.Style.Shadow and (Saved.Style.OutlineWidth = 0),
      'decoration icons independently toggle style');
    Check((Saved.Text = D.Text) and (Saved.Hold = D.Hold), 'font toolbar preserves lyrics and animation');
    for I := 0 to Form.ComponentCount - 1 do
      if (Form.Components[I] is TMVPlacementButton) and (TControl(Form.Components[I]).Tag = Ord(mpcUndo)) then
        TMVPlacementButton(Form.Components[I]).Click;
    Form.OnCloseQuery(Form, CanClose);
    Check((Saved.Style.FontSize = 100) and (SizeEdit.Text = '100') and (Family.Text = 'Arial'),
      'font undo restores document and inline controls together');
    SizeEdit.Text := '0';
    try Toolbar.CommitPending; Check(False, 'invalid font size must fail');
    except on E: EArgumentException do Check(True, 'invalid font size rejected before mutation'); end;
    Toolbar.RefreshStyle;
  finally Form.Free; end;
end;

procedure RunSelectionTests;
begin
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  try CheckAffineSelection; CheckEditorSelection;
  finally TTextRendererSkiaRuntime.Release; end;
  Writeln('Group selection, affine transforms and font toolbar: OK');
end;

end.
