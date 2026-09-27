unit MVEditorCanvas;

// 配置・範囲選択・装飾ドラッグの入力状態と捕捉を管理し、操作中の補助表示を描画する。
// 文書、組版、表示座標、連続書式編集の共通管理はMVEditorCanvasViewへ委ねる。
interface

uses Winapi.Messages, System.Classes, System.SysUtils, System.Types, Vcl.Controls,
  MVDocument, MVTransformGeometry, MVDecorationHandles, MVEditorCanvasView;

type
  TMVEditorCanvas = class(TMVEditorCanvasView)
  private
    FSelectionBounds: TRectF; // 操作開始時のローカル外接枠。
    FMarquee: Boolean; // 空白からの左ドラッグによる範囲選択。
    FRangeStart, FRangeEnd: TPointF; // 範囲選択の出力座標。
    FRangeBefore, FRangeBase: TArray<Integer>; // 取消用の選択とShift追加用の基準。
    FDragging: Boolean; // 現在のマウス操作が配置移動か。
    FStart: TPointF; // ドラッグ開始時の出力座標。
    FOriginal: TMVPlacement; // Escape取消と変形評価の基準。
    FHandle: TMVHandle; // 押下時に確定した操作点。
    FPanning: Boolean; // 中ボタンまたはSpaceによる画面移動。
    FPanStart, FPanOrigin: TPointF; // パン開始時の画面座標と原点。
    FSpace: Boolean; // Spaceを保持している間だけ手のひら操作。
    FDecoration: TMVDecorationHandle; // 操作中の装飾アイコン。
    FDecorationStart: TPointF; // 装飾ドラッグの画面上の開始点。
    FDecorationPoints: TMVDecorationPoints; // ドラッグ中は位置を固定して追いかけ操作を防ぐ。
    // 装飾ドラッグ中は開始時の画面座標を返し、アイコンの追いかけ操作を防ぐ。
    function DecorationPoints: TMVDecorationPoints;
    // 変形・装飾・範囲選択を確定または取消してから、マウス捕捉を解除する。
    procedure FinishDrag(Cancel: Boolean);
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
    // Spaceの解放を反映し、次の左クリックを通常操作へ戻す。
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    // 画面外で捕捉を失った操作を取り消す。
    procedure WndProc(var Message: TMessage); override;
  public
    SnapEnabled: Boolean; // 位置と回転のスナップ。Alt保持中は一時解除。
    // 手動捕捉による入力操作を初期化する。AOwnerへ通常のVCL所有権を渡す。
    constructor Create(AOwner: TComponent); override;
    // 未確定操作を取り消してから、基底クラスが組版と背景を解放する。
    destructor Destroy; override;
    // 未確定ドラッグを元に戻し、指定時は選択も解除する。
    procedure CancelInteraction(Deselect: Boolean = False); override;
  end;

implementation

uses Winapi.Windows, System.Math, System.UITypes, MVCanvasPainter, MVCanvasTargets;

constructor TMVEditorCanvas.Create(AOwner: TComponent);
begin
  inherited;
  TabStop := True;
  // VCLの自動捕捉はMouseUpより先に解除され、正常終了もWM_CAPTURECHANGEDで取消になる。
  // 捕捉はMouseDownとFinishDragで管理し、選択・変形の確定後に解除する。
  ControlStyle := (ControlStyle + [csOpaque]) - [csCaptureMouse];
  ShowHint := True;
  SnapEnabled := True;
end;

destructor TMVEditorCanvas.Destroy;
begin
  if FSelection <> nil then CancelInteraction;
  inherited;
end;

function TMVEditorCanvas.DecorationPoints: TMVDecorationPoints;
begin
  if FDecoration <> mdhNone then Exit(FDecorationPoints);
  Result := MVDecorationPoints(SelectionHandles, ClientWidth, ClientHeight, CurrentPPI / 96);
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
    DocumentToScreen(FRangeEnd), DecorationPoints, FDecoration, FBuffer);
end;

procedure TMVEditorCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var Hit: Integer; P: TPointF; Item: TMVPlacement; Bounds: TRectF; Decoration: TMVDecorationHandle;
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
  if Selected >= 0 then
  begin
    FDecorationPoints := DecorationPoints;
    Decoration := MVHitDecoration(FDecorationPoints, PointF(X, Y), 12 * CurrentPPI / 96);
    if Decoration <> mdhNone then
    begin
      BeginStyleEdit;
      FDecoration := Decoration;
      FDecorationStart := PointF(X, Y);
      MouseCapture := True;
      Invalidate;
      Exit;
    end;
  end;
  FHandle := mhNone;
  if Selected >= 0 then
    FHandle := MVHitHandle(SelectionHandles, PointF(X, Y), 7 * CurrentPPI / 96);
  P := FView.ToDocument(PointF(X, Y), OutputWidth, OutputHeight);
  if FHandle = mhNone then
  begin
    Hit := HitMVCanvasUnit(FSession.Document, FLayout, P);
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

procedure TMVEditorCanvas.MouseMove(Shift: TShiftState; X, Y: Integer);
var P: TPointF; Item: TMVPlacement; H: TMVHandle; D: TMVDecorationHandle;
begin
  inherited;
  if FDecoration <> mdhNone then
  begin
    P := (PointF(X, Y) - FDecorationStart) * (1 / FView.Zoom);
    if ssShift in Shift then P := P * 0.1;
    try
      FStyleGesture.Preview(MVDragDecoration(FStyleGesture.Before, FStyleIndices, FDecoration, P), FLayout);
      FSelection.Attach(FSession, FLayout);
      Invalidate;
    except
      on E: Exception do Hint := E.Message; // 上限に達した場合は直前の有効なプレビューを維持する。
    end;
    Exit;
  end;
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
    D := mdhNone;
    if Selected >= 0 then D := MVHitDecoration(DecorationPoints, PointF(X, Y), 12 * CurrentPPI / 96);
    Hint := MVDecorationHint(D);
    if D <> mdhNone then
    begin
      if D = mdhShadowPosition then Cursor := crSizeAll else Cursor := crSizeWE;
      Exit;
    end;
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
  if (FHandle = mhMove) and SnapEnabled and not (ssAlt in Shift) then
    SnapMVCanvasPosition(Item, FLayout, FSelection, FView.Zoom, CurrentPPI);
  FSelection.ApplyFrame(Item);
  Invalidate;
end;

procedure TMVEditorCanvas.FinishDrag(Cancel: Boolean);
begin
  FDecoration := mdhNone;
  FinishStyleEdit(Cancel);
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
  if (Message.Msg = WM_CAPTURECHANGED) and
    ((FHandle <> mhNone) or FPanning or FMarquee or (FDecoration <> mdhNone)) then FinishDrag(True);
  if Message.Msg = WM_KILLFOCUS then FSpace := False;
  inherited;
end;

end.
