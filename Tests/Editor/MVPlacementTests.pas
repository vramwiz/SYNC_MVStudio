unit MVPlacementTests;

// ホスト歌詞との配置照合、アイコン選択、実キャンバスのドラッグとUndoを検証する。
interface

// ユーザーの画面を操作せず、テスト所有のフォームだけで配置操作を行う。
procedure RunPlacementTests;

implementation

uses System.SysUtils, System.Classes, System.Math, System.Types, Winapi.Windows, Vcl.Forms, Vcl.Controls, MVDocument, MVTextUnits,
  MVPlacementDocument, MVTransformGeometry, MVEditorForm, MVEditorCanvas, MVPlacementToolbar, MVHostText, MVTestAssert,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap;

type
  TCanvasAccess = class(TMVEditorCanvas)
  public
    procedure Drag(X, Y, DX, DY: Integer; Shift: TShiftState = []);
    procedure Nudge(Key: Word; Shift: TShiftState);
    procedure Wheel(const P: TPoint; Delta: Integer);
    procedure Pan(DX, DY: Integer);
    procedure AbortDrag(X, Y: Integer);
  end;

procedure TCanvasAccess.Drag(X, Y, DX, DY: Integer; Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, X, Y);
  MouseMove(Shift + [ssLeft], X + DX, Y + DY);
  MouseUp(mbLeft, Shift, X + DX, Y + DY);
end;

procedure TCanvasAccess.Nudge(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TCanvasAccess.Wheel(const P: TPoint; Delta: Integer);
begin
  DoMouseWheel([], Delta, ClientToScreen(P));
end;

procedure TCanvasAccess.Pan(DX, DY: Integer);
begin
  MouseDown(mbMiddle, [], 100, 100);
  MouseMove([ssMiddle], 100 + DX, 100 + DY);
  MouseUp(mbMiddle, [], 100 + DX, 100 + DY);
end;

procedure TCanvasAccess.AbortDrag(X, Y: Integer);
var Key: Word;
begin
  MouseDown(mbLeft, [], X, Y);
  MouseMove([ssLeft], X + 40, Y);
  Key := VK_ESCAPE;
  KeyDown(Key, []);
end;
procedure CheckHostMerge;
var Stored, Host, ResultDoc: TMVDocument;
begin
  Stored := DefaultMVDocument;
  SetMVText(Stored, '朝の歌');
  Stored.Units[0].X := -123;
  Stored.Units[0].Positioned := True;
  Stored.Units[2].Angle := 30;
  Host := DefaultMVDocument;
  Host.Text := '朝からの歌';
  Host.Style.FontSize := 90;
  Host.Hold := 3;
  ResultDoc := Stored;
  ApplyMVHostDocument(ResultDoc, Host);
  Check((ResultDoc.Text = Host.Text) and (Length(ResultDoc.Units) = 5), 'host lyric replaces stored phrase');
  Check((ResultDoc.Units[0].X = -123) and (ResultDoc.Units[4].Angle = 30),
    'unchanged prefix and suffix retain placement after insertion');
  Check(not ResultDoc.Units[1].Positioned and (ResultDoc.Units[1].Scale = 1),
    'inserted character starts at automatic position');
  Check((ResultDoc.Style.FontSize = 90) and (ResultDoc.Hold = 3), 'host style and motion are authoritative');
  ResultDoc.Units[0].X := 500;
  Check(Stored.Units[0].X = -123, 'host merge does not mutate stored placement array');
  Host.Text := '歌';
  ApplyMVHostDocument(ResultDoc, Host);
  Check((Length(ResultDoc.Units) = 1) and (ResultDoc.Units[0].Angle = 30), 'deletion retains matching suffix');
  Host.Text := '';
  ApplyMVHostDocument(ResultDoc, Host);
  Check((ResultDoc.Text = '') and (Length(ResultDoc.Units) = 0), 'empty host lyric removes all placements');
end;

procedure ClickTool(Form: TMVEditorForm; Command: TMVPlacementCommand);
var I: Integer; Button: TMVPlacementButton;
begin
  for I := 0 to Form.ComponentCount - 1 do
    if Form.Components[I] is TMVPlacementButton then
    begin
      Button := TMVPlacementButton(Form.Components[I]);
      if Button.Tag = Ord(Command) then
      begin
        Button.Click;
        Exit;
      end;
    end;
  raise Exception.Create('placement icon missing');
end;

procedure CheckPlacementInteraction;
var D, Saved: TMVDocument; Form: TMVEditorForm; Canvas: TMVEditorCanvas;
  I, X, Y: Integer; CanClose: Boolean; Zoom: Double; Handles, Before: TMVHandlePoints; P, Q: TPointF;
begin
  D := DefaultMVDocument;
  SetMVText(D, '歌');
  Form := TMVEditorForm.CreateEditor(D, 960, 540, 5, 0.3, 0.3,
    function(const Document: TMVDocument): string
    begin
      Saved := CloneMVDocument(Document);
      Result := '';
    end);
  try
    Form.Position := poDesigned;
    Form.SetBounds(-30000, -30000, 1100, 760);
    Form.ShowInTaskBar := False;
    Form.Show;
    Canvas := nil;
    for I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TMVEditorCanvas then Canvas := TMVEditorCanvas(Form.Components[I]);
    Check(Canvas <> nil, 'placement canvas exists');
    X := Canvas.ClientWidth div 2;
    Y := Canvas.ClientHeight div 2;
    Zoom := Min((Canvas.ClientWidth - 24) / 960, (Canvas.ClientHeight - 24) / 540);
    Canvas.SnapEnabled := False;
    TCanvasAccess(Canvas).Drag(X, Y, 40, -20);
    Form.OnCloseQuery(Form, CanClose);
    Check(CanClose and Saved.Units[0].Positioned and (Abs(Saved.Units[0].X - 40 / Zoom) < 0.01),
      'move icon drags in output pixel coordinates');
    ClickTool(Form, mpcUndo);
    Form.OnCloseQuery(Form, CanClose);
    Check(not Saved.Units[0].Positioned, 'one undo reverses complete drag');
    ClickTool(Form, mpcRedo);
    Form.OnCloseQuery(Form, CanClose);
    Check(Saved.Units[0].Positioned, 'redo restores drag');
    ClickTool(Form, mpcReset);
    TCanvasAccess(Canvas).Drag(X, Y, 0, 0);
    Handles := Canvas.SelectionHandles;
    Before := Handles;
    TCanvasAccess(Canvas).Drag(Round(Handles[mhSE].X), Round(Handles[mhSE].Y), 40, 40);
    Form.OnCloseQuery(Form, CanClose);
    Check((Saved.Units[0].ScaleX > 1) and (Saved.Units[0].ScaleX = Saved.Units[0].ScaleY),
      'corner handle scales proportionally');
    Handles := Canvas.SelectionHandles;
    Check((Handles[mhNW] - Before[mhNW]).Length < 0.1, 'corner drag fixes opposite corner');
    TCanvasAccess(Canvas).Drag(Round(Handles[mhE].X), Round(Handles[mhE].Y), 30, 0);
    Form.OnCloseQuery(Form, CanClose);
    Check(Saved.Units[0].ScaleX > Saved.Units[0].ScaleY, 'side handle stretches horizontally');
    Handles := Canvas.SelectionHandles;
    P := Canvas.DocumentToScreen(PointF(Saved.Units[0].X, Saved.Units[0].Y));
    Q := P + MVRotate(Handles[mhRotate] - P, 30);
    TCanvasAccess(Canvas).Drag(Round(Handles[mhRotate].X), Round(Handles[mhRotate].Y),
      Round(Q.X - Handles[mhRotate].X), Round(Q.Y - Handles[mhRotate].Y));
    Form.OnCloseQuery(Form, CanClose);
    Check(Abs(Saved.Units[0].Angle - 30) < 1, 'upper handle rotates around character center');
    P := Canvas.DocumentToScreen(PointF(0, 0));
    TCanvasAccess(Canvas).Wheel(Point(Round(P.X), Round(P.Y)), 120);
    Q := Canvas.DocumentToScreen(PointF(0, 0));
    Check((P - Q).Length < 1, 'wheel keeps document point under mouse');
    TCanvasAccess(Canvas).Pan(35, -20);
    Q := Canvas.DocumentToScreen(PointF(0, 0));
    Check((Q - P - PointF(35, -20)).Length < 1, 'middle drag pans canvas');
    Form.OnCloseQuery(Form, CanClose);
    Check(Abs(Saved.Units[0].Angle - 30) < 1, 'view navigation leaves character transform unchanged');
    Canvas.ResetView;
    ClickTool(Form, mpcReset);
    Form.OnCloseQuery(Form, CanClose);
    Check((Saved.Units[0].ScaleX = 1) and (Saved.Units[0].ScaleY = 1) and (Saved.Units[0].Angle = 0) and not Saved.Units[0].Positioned,
      'reset restores automatic placement and transform');
    TCanvasAccess(Canvas).AbortDrag(X, Y);
    Form.OnCloseQuery(Form, CanClose);
    Check(not Saved.Units[0].Positioned, 'Escape cancels an active transform');
    Canvas.SnapEnabled := True;
    TCanvasAccess(Canvas).Drag(X, Y, 4, 0);
    Form.OnCloseQuery(Form, CanClose);
    Check(Abs(Saved.Units[0].X) < 0.001, 'move snaps to scene center');
    TCanvasAccess(Canvas).Drag(X, Y, 4, 0, [ssAlt]);
    Form.OnCloseQuery(Form, CanClose);
    Check(Saved.Units[0].X > 2, 'Alt temporarily bypasses position snap');
    ClickTool(Form, mpcReset);
    TCanvasAccess(Canvas).Nudge(VK_RIGHT, [ssShift]);
    Form.OnCloseQuery(Form, CanClose);
    Check(Saved.Units[0].X = 10, 'Shift arrow nudges by ten output pixels');
    Check(Saved.EditorSettings, 'editor saves shared settings ownership');
    Check((Saved.Text = D.Text) and (Saved.Style.FontSize = D.Style.FontSize),
      'placement tools preserve host lyric and shared style');
  finally Form.Free; end;
end;

procedure RunPlacementTests;
begin
  Check(DecodeMVHostText('歌\n詞\\n') = '歌' + #10 + '詞\n', 'host alias distinguishes newline and literal slash n');
  Check(DecodeMVHostText('末尾\') = '末尾\', 'host alias preserves trailing slash');
  Check(DecodeMVHostText('未知\x') = '未知\x', 'host alias preserves unknown escape');
  CheckHostMerge;
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  try CheckPlacementInteraction; finally TTextRendererSkiaRuntime.Release; end;
  Writeln('Host lyrics and placement icons: OK');
end;

end.
