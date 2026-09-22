unit MVEditorCanvas;

// 出力座標の文字配置を画面倍率から分離し、共通Skia描画とドラッグ操作を提供する。
interface

uses Winapi.Messages, System.Classes, System.SysUtils, System.Types, System.Skia, Vcl.Controls, MVEditSession, MVLayout,
  MVBackgroundFrame, MVDocument, MVCanvasViewport, MVTransformGeometry, MVSelection;

type
  TMVEditorCanvas = class(TCustomControl)
  private
    FSession: TMVEditSession; // フォーム所有の作業用文書。
    FLayout: TMVLayout; // 編集による更新まで再利用する文字画像。
    FSelection: TMVSelection; // 選択集合とUndoを伴う共通変形。
    FSelectionBounds: TRectF; // 操作開始時のローカル外接枠。
    FMarquee: Boolean; // 空白からの左ドラッグによる範囲選択。
    FRangeStart, FRangeEnd: TPointF; // 範囲選択の出力座標。
    FRangeBefore, FRangeBase: TArray<Integer>; // 取消用の選択とShift追加用の基準。
    FDragging: Boolean; // 現在のマウス操作が配置移動か。
    FStart: TPointF; // ドラッグ開始時の出力座標。
    FOriginal: TMVPlacement; // Escape取消と変形評価の基準。
    FView: TMVViewport; // 保存しない画面倍率と移動量。
    FBuffer: TBytes; // Paint中だけのBGRA画像。
    FBackground: ISkImage; // 合成前の静止背景。
    FHandle: TMVHandle; // 押下時に確定した操作点。
    FPanning: Boolean; // 中ボタンまたはSpaceによる画面移動。
    FPanStart, FPanOrigin: TPointF; // パン開始時の画面座標と原点。
    FSpace: Boolean; // Spaceを保持している間だけ手のひら操作。
    FSelectionChanged: TNotifyEvent; // 選択後に書式UIを同期する。
    function GetSelected: Integer;
    function GetSelectionCount: Integer;
    procedure NotifySelection;
    procedure FinishDrag(Cancel: Boolean);
    procedure SnapPosition(var Item: TMVPlacement);
    procedure ViewTransform;
  protected
    // Skiaの共通描画結果をVCLへ転送する。
    procedure Paint; override;
    // 文字選択と1回のUndo対象となるドラッグを開始する。
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // 操作点に応じた変形またはパンを、開始状態から評価する。
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    // マウス捕捉を終了する。
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // ポインタ位置を固定した画面ズーム。文書の倍率は変更しない。
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    // 矢印で位置調整、Escapeでドラッグ取消、Spaceでパンを行う。
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    // 画面外で捕捉を失った操作を取り消す。
    procedure WndProc(var Message: TMessage); override;
  public
    SnapEnabled: Boolean; // 位置と回転のスナップ。Alt保持中は一時解除。
    OutputWidth, OutputHeight: Integer; // 編集対象シーンの解像度。
    Time, Duration, EntranceTime, ExitTime: Double; // Time=-1なら静止編集。
    // セッションと表示状態を初期化する。
    constructor Create(AOwner: TComponent); override;
    // 背景と文字画像を解放する。セッションは解放しない。
    destructor Destroy; override;
    // 作業用文書を関連付けて最初の組版を行う。
    procedure Attach(Session: TMVEditSession);
    // 入力背景をSkia画像へ複写し、キャンバスを入力寸法に合わせる。空なら無地へ戻す。
    procedure SetBackground(const Frame: TMVBackgroundFrame);
    // 文書変更後に組版を更新する。
    procedure RefreshDocument;
    // 候補の組版成功後だけ文書を置き換え、1操作のUndoを記録する。
    procedure CommitDocument(const Candidate: TMVDocument);
    // 表示だけをフィットまたは100%へ戻す。
    procedure ResetView(ActualSize: Boolean = False);
    // 未確定ドラッグを元に戻し、選択も解除できる。
    procedure CancelInteraction(Deselect: Boolean = False);
    // 自動配置の文字も含め、現在の選択点を画面座標で返す。
    function SelectionHandles: TMVHandlePoints;
    // 保存座標を画面へ変換する。表示検証と補助UIにも使う。
    function DocumentToScreen(const Point: TPointF): TPointF;
    // 選択のコピーを返す。書式・整列コマンドは内部配列を直接変更しない。
    function SelectedIndices: TArray<Integer>;
    // 現在の選択を、登録済みの動作グループ全体へ広げる。文書やUndoは変更しない。
    procedure SelectAnimationGroups;
    property Selected: Integer read GetSelected;
    property SelectionCount: Integer read GetSelectionCount;
    property Layout: TMVLayout read FLayout;
    property OnSelectionChanged: TNotifyEvent read FSelectionChanged write FSelectionChanged;
  end;

implementation

uses Winapi.Windows, System.Math, System.UITypes, MVCanvasPainter, MVGrouping;

constructor TMVEditorCanvas.Create(AOwner: TComponent);
begin
  inherited;
  TabStop := True;
  // VCLの自動捕捉はMouseUpより先に解除され、正常終了もWM_CAPTURECHANGEDで取消になる。
  // 捕捉はMouseDownとFinishDragで管理し、選択・変形の確定後に解除する。
  ControlStyle := (ControlStyle + [csOpaque]) - [csCaptureMouse];
  FSelection := TMVSelection.Create;
  SnapEnabled := True;
  Time := -1;
  Duration := 5;
  OutputWidth := 1920;
  OutputHeight := 1080;
end;

destructor TMVEditorCanvas.Destroy;
begin
  if FSelection <> nil then CancelInteraction;
  FBackground := nil;
  FSelection.Free;
  FLayout.Free;
  inherited;
end;

procedure TMVEditorCanvas.SetBackground(const Frame: TMVBackgroundFrame);
begin
  FBackground := nil;
  if Frame.IsValid then
  begin
    FBackground := TSkImage.MakeRasterCopy(TSkImageInfo.Create(Frame.Width, Frame.Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul), @Frame.Pixels[0], Frame.Width * 4);
    OutputWidth := Frame.Width;
    OutputHeight := Frame.Height;
  end;
  Invalidate;
end;

procedure TMVEditorCanvas.Attach(Session: TMVEditSession);
begin
  FSession := Session;
  RefreshDocument;
end;

procedure TMVEditorCanvas.RefreshDocument;
var NewLayout: TMVLayout;
begin
  NewLayout := TMVLayout.Create(FSession.Document);
  FLayout.Free;
  FLayout := NewLayout;
  FSelection.Attach(FSession, FLayout);
  Invalidate;
end;

procedure TMVEditorCanvas.ViewTransform;
begin
  FView.Update(ClientWidth, ClientHeight, OutputWidth, OutputHeight);
end;

function TMVEditorCanvas.GetSelected: Integer;
begin Result := FSelection.First; end;

function TMVEditorCanvas.GetSelectionCount: Integer;
begin Result := FSelection.Count; end;

function TMVEditorCanvas.SelectedIndices: TArray<Integer>;
begin Result := FSelection.Snapshot; end;

procedure TMVEditorCanvas.SelectAnimationGroups;
begin
  CancelInteraction;
  FSelection.Restore(ExpandMVAnimationGroups(FSession.Document, SelectedIndices));
  FSelection.Attach(FSession, FLayout);
  NotifySelection;
  Invalidate;
end;

procedure TMVEditorCanvas.NotifySelection;
begin
  if Assigned(FSelectionChanged) then FSelectionChanged(Self);
end;

procedure TMVEditorCanvas.CommitDocument(const Candidate: TMVDocument);
var NewLayout: TMVLayout; Prepared: TMVDocument;
begin
  Prepared := CloneMVDocument(Candidate);
  NewLayout := TMVLayout.Create(Prepared);
  try
    FSession.BeginChange;
    FSession.Document := Prepared;
    FLayout.Free;
    FLayout := NewLayout;
    NewLayout := nil;
    FSelection.Attach(FSession, FLayout);
    Invalidate;
  finally NewLayout.Free; end;
end;

function TMVEditorCanvas.DocumentToScreen(const Point: TPointF): TPointF;
begin
  ViewTransform;
  Result := FView.ToScreen(Point, OutputWidth, OutputHeight);
end;

function TMVEditorCanvas.SelectionHandles: TMVHandlePoints;
var H: TMVHandle; Item: TMVPlacement; Bounds: TRectF;
begin
  Result := Default(TMVHandlePoints);
  if Selected < 0 then Exit;
  ViewTransform;
  FSelection.Frame(Item, Bounds);
  Result := MVHandles(Item, Bounds, 28 * CurrentPPI / 96 / FView.Zoom);
  for H := mhNW to mhRotate do Result[H] := FView.ToScreen(Result[H], OutputWidth, OutputHeight);
end;

procedure TMVEditorCanvas.ResetView(ActualSize: Boolean);
begin
  FView.Manual := False;
  ViewTransform;
  if ActualSize then FView.ZoomAt(PointF(ClientWidth / 2, ClientHeight / 2), 1 / FView.Zoom);
  Invalidate;
end;
procedure TMVEditorCanvas.Paint;
var HandleSize: Single;
begin
  if (ClientWidth <= 0) or (ClientHeight <= 0) or (FLayout = nil) then Exit;
  ViewTransform;
  HandleSize := 0;
  if (Selected >= 0) and (Time < 0) then HandleSize := 8 * CurrentPPI / 96;
  PaintMVEditorCanvas(Canvas.Handle, TSize.Create(ClientWidth, ClientHeight),
    TSize.Create(OutputWidth, OutputHeight), FSession.Document, FLayout, FBackground, FView,
    SelectionHandles, FSelection.Snapshot, HandleSize, FMarquee, DocumentToScreen(FRangeStart),
    DocumentToScreen(FRangeEnd), FBuffer);
end;
procedure TMVEditorCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var I, Hit: Integer; P: TPointF; Item: TMVPlacement; Bounds: TRectF;
begin
  inherited;
  if (FLayout = nil) or (Time >= 0) then Exit;
  SetFocus;
  ViewTransform;
  if (Button = mbMiddle) or ((Button = mbLeft) and FSpace) then
  begin
    FinishDrag(False); FPanning := True;
    FPanStart := PointF(X, Y); FPanOrigin := FView.Origin;
    MouseCapture := True; Cursor := crHandPoint; Exit;
  end;
  if Button <> mbLeft then Exit;
  FHandle := mhNone;
  if Selected >= 0 then
    FHandle := MVHitHandle(SelectionHandles, PointF(X, Y), 7 * CurrentPPI / 96);
  P := FView.ToDocument(PointF(X, Y), OutputWidth, OutputHeight);
  if FHandle = mhNone then
  begin
    Hit := -1;
    for I := High(FLayout.Units) downto 0 do
    begin
      if FLayout.Units[I].Image = nil then Continue;
      Item := FSession.Document.Units[I];
      Item.X := FLayout.Units[I].Position.X; Item.Y := FLayout.Units[I].Position.Y;
      if MVHitBody(Item, FLayout.Units[I].HitBounds, P) then begin Hit := I; Break; end;
    end;
    if (Hit < 0) and (SelectionCount > 1) and not (ssShift in Shift) then
    begin
      FSelection.Frame(Item, Bounds);
      if MVHitBody(Item, Bounds, P) then FHandle := mhMove;
    end;
    if (Hit < 0) and (FHandle = mhNone) then
    begin
      FRangeBefore := FSelection.Snapshot;
      FRangeBase := nil;
      if ssShift in Shift then FRangeBase := FSelection.Snapshot;
      FSelection.Restore(FRangeBase);
      FRangeStart := P; FRangeEnd := P; FMarquee := True;
      MouseCapture := True; Invalidate; Exit;
    end;
    if Hit >= 0 then
    begin
      if ssShift in Shift then FSelection.Select(Hit, True)
      else if not FSelection.Contains(Hit) then FSelection.Select(Hit);
      if not FSelection.Contains(Hit) then begin Invalidate; Exit; end;
    end;
    FHandle := mhMove;
  end;
  if Selected >= 0 then
  begin
    FStart := P;
    FSelection.Frame(FOriginal, FSelectionBounds);
    FSelection.BeginTransform;
    FDragging := False; MouseCapture := True;
  end;
  Invalidate;
end;
procedure TMVEditorCanvas.SnapPosition(var Item: TMVPlacement);
var I: Integer; BestX, BestY, DX, DY, Limit: Single; Target: TPointF;
begin
  Limit := 6 * CurrentPPI / 96 / FView.Zoom;
  BestX := Limit;
  BestY := Limit;
  DX := 0;
  DY := 0;
  for I := -1 to High(FLayout.Units) do
  begin
    if FSelection.Contains(I) then Continue;
    if I < 0 then Target := PointF(0, 0)
    else
    begin
      if FLayout.Units[I].Image = nil then Continue;
      Target := FLayout.Units[I].Position;
    end;
    if Abs(Target.X - Item.X) < BestX then
    begin BestX := Abs(Target.X - Item.X); DX := Target.X - Item.X; end;
    if Abs(Target.Y - Item.Y) < BestY then
    begin BestY := Abs(Target.Y - Item.Y); DY := Target.Y - Item.Y; end;
  end;
  Item.X := Item.X + DX;
  Item.Y := Item.Y + DY;
end;

procedure TMVEditorCanvas.MouseMove(Shift: TShiftState; X, Y: Integer);
var P: TPointF; Item: TMVPlacement; H: TMVHandle;
begin
  inherited;
  if FPanning then
  begin
    FView.Origin := FPanOrigin + PointF(X, Y) - FPanStart;
    FView.Manual := True;
    Invalidate;
    Exit;
  end;
  if FMarquee then
  begin
    FRangeEnd := FView.ToDocument(PointF(X, Y), OutputWidth, OutputHeight);
    FSelection.SelectRange(RectF(Min(FRangeStart.X, FRangeEnd.X), Min(FRangeStart.Y, FRangeEnd.Y),
      Max(FRangeStart.X, FRangeEnd.X), Max(FRangeStart.Y, FRangeEnd.Y)), FRangeBase);
    Invalidate; Exit;
  end;
  if not MouseCapture or (Selected < 0) then
  begin
    H := mhNone;
    if Selected >= 0 then H := MVHitHandle(SelectionHandles, PointF(X, Y), 7 * CurrentPPI / 96);
    case H of
      mhNW, mhSE: Cursor := crSizeNWSE;
      mhNE, mhSW: Cursor := crSizeNESW;
      mhN, mhS: Cursor := crSizeNS;
      mhW, mhE: Cursor := crSizeWE;
      mhRotate: Cursor := crCross;
    else Cursor := crDefault; end;
    Exit;
  end;
  P := FView.ToDocument(PointF(X, Y), OutputWidth, OutputHeight);
  if not FDragging and ((P - FStart).Length < 2 / FView.Zoom) then Exit;
  FDragging := True;
  Item := MVTransform(FOriginal, FSelectionBounds, FHandle, FStart, P,
    SnapEnabled and not (ssAlt in Shift), ssShift in Shift);
  if (FHandle = mhMove) and SnapEnabled and not (ssAlt in Shift) then SnapPosition(Item);
  FSelection.ApplyFrame(Item);
  Invalidate;
end;

procedure TMVEditorCanvas.FinishDrag(Cancel: Boolean);
begin
  FSelection.Finish(Cancel);
  if FMarquee and Cancel then FSelection.Restore(FRangeBefore);
  FMarquee := False; FRangeBefore := nil; FRangeBase := nil;
  FDragging := False; FPanning := False; FHandle := mhNone;
  MouseCapture := False; Cursor := crDefault; Invalidate;
end;
procedure TMVEditorCanvas.CancelInteraction(Deselect: Boolean);
begin
  FinishDrag(True);
  if Deselect then FSelection.Select(-1);
  Invalidate;
end;

procedure TMVEditorCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if ((Button = mbMiddle) and FPanning) or (Button = mbLeft) then FinishDrag(False);
  NotifySelection;
  inherited;
end;

function TMVEditorCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var P: TPoint;
begin
  Result := True;
  if MouseCapture then Exit;
  ViewTransform;
  P := ScreenToClient(MousePos);
  FView.ZoomAt(PointF(P.X, P.Y), Power(1.15, WheelDelta / 120));
  Invalidate;
end;

procedure TMVEditorCanvas.KeyDown(var Key: Word; Shift: TShiftState);
var Step, DX, DY: Integer;
begin
  inherited;
  if Key = VK_SPACE then begin FSpace := True; Key := 0; Exit; end;
  if Key = VK_ESCAPE then begin CancelInteraction(not MouseCapture); NotifySelection; Key := 0; Exit; end;
  if (Key = Ord('A')) and (ssCtrl in Shift) then
  begin CancelInteraction; FSelection.SelectAll; NotifySelection; Key := 0; Invalidate; Exit; end;
  if (Selected < 0) or MouseCapture or not (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN]) then Exit;
  Step := 1; if ssShift in Shift then Step := 10;
  DX := 0; DY := 0;
  case Key of
    VK_LEFT: DX := -Step;
    VK_RIGHT: DX := Step;
    VK_UP: DY := -Step;
    VK_DOWN: DY := Step;
  end;
  FSelection.Nudge(DX, DY); Key := 0; Invalidate;
end;
procedure TMVEditorCanvas.KeyUp(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if Key = VK_SPACE then FSpace := False;
end;

procedure TMVEditorCanvas.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_GETDLGCODE then
  begin
    inherited;
    Message.Result := Message.Result or DLGC_WANTARROWS or DLGC_WANTCHARS;
    Exit;
  end;
  if (Message.Msg = WM_CAPTURECHANGED) and ((FHandle <> mhNone) or FPanning or FMarquee) then FinishDrag(True);
  if Message.Msg = WM_KILLFOCUS then FSpace := False;
  inherited;
end;

end.
