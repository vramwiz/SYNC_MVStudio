unit MVSelection;

// 複数文字の選択と共通変形を管理し、ドラッグ全体を1回のUndoへまとめる。
interface

uses System.Types, MVDocument, MVEditSession, MVLayout, MVTransformGeometry;

type
  TMVSelection = class
  private
    FSession: TMVEditSession; // 所有しない作業文書。
    FLayout: TMVLayout; // 再組版の都度Attachで更新する。
    FIndices: TArray<Integer>; // 表示可能な文字の選択集合。
    FBefore, FResolved: TArray<TMVPlacement>; // 自動配置フラグを保つ原本と操作基準。
    FBase, FCurrent: TMVPlacement; // 単一文字または共通枠の変形。
    FBounds: TRectF; // 操作開始時の共通枠ローカル寸法。
    FActive, FChanged: Boolean; // 捕捉中か、配置を書き換えたか。
    procedure UpdatePositions;
    function Placement(Index: Integer): TMVPlacement;
  public
    // 再組版後の参照を差し替え、範囲外の選択を取り除く。
    procedure Attach(Session: TMVEditSession; Layout: TMVLayout);
    // 選択集合の照会。Firstは未選択なら-1を返す。
    function Contains(Index: Integer): Boolean;
    function Count: Integer;
    function First: Integer;
    // Index=-1は解除。Toggle=Trueは既存の集合へ追加・除外する。
    procedure Select(Index: Integer; Toggle: Boolean = False);
    // 全ての描画可能文字を選択する。改行は対象にしない。
    procedure SelectAll;
    // 保存した集合を基準に、矩形と交差する文字を追加する。
    procedure SelectRange(const Bounds: TRectF; const Base: TArray<Integer>);
    // 選択集合の独立した複写。範囲選択の取消に利用する。
    function Snapshot: TArray<Integer>;
    procedure Restore(const Indices: TArray<Integer>);
    // 単一文字の回転枠、複数文字の共通外接枠を返す。
    procedure Frame(out Item: TMVPlacement; out Bounds: TRectF);
    // 変形前の自動配置も含めて退避する。
    procedure BeginTransform;
    // 共通枠の差分を各文字へ適用する。保存限界を超える操作は反映しない。
    procedure ApplyFrame(const Item: TMVPlacement);
    // 確定は1操作、取消はUndoを追加せず元へ戻す。
    procedure Finish(Cancel: Boolean);
    // キーボードの位置調整を選択全体へ適用する。
    procedure Nudge(DX, DY: Single);
  end;

implementation

uses System.Math, System.SysUtils;

function TMVSelection.Contains(Index: Integer): Boolean;
var I: Integer;
begin
  for I in FIndices do if I = Index then Exit(True);
  Result := False;
end;

function TMVSelection.Count: Integer;
begin Result := Length(FIndices); end;

function TMVSelection.First: Integer;
begin if Count = 0 then Result := -1 else Result := FIndices[0]; end;

procedure TMVSelection.Attach(Session: TMVEditSession; Layout: TMVLayout);
var Old: TArray<Integer>; I: Integer;
begin
  FSession := Session; FLayout := Layout;
  Old := FIndices; FIndices := nil;
  for I in Old do
    if (I >= 0) and (I < Length(Layout.Units)) and (Layout.Units[I].Image <> nil) then
      FIndices := FIndices + [I];
end;

procedure TMVSelection.Select(Index: Integer; Toggle: Boolean);
var Old: TArray<Integer>; I: Integer;
begin
  if not Toggle then FIndices := nil;
  if Index < 0 then Exit;
  if Contains(Index) then
  begin
    Old := FIndices; FIndices := nil;
    for I in Old do if I <> Index then FIndices := FIndices + [I];
  end
  else FIndices := FIndices + [Index];
end;

procedure TMVSelection.SelectAll;
var I: Integer;
begin
  FIndices := nil;
  for I := 0 to High(FLayout.Units) do
    if FLayout.Units[I].Image <> nil then FIndices := FIndices + [I];
end;

function TMVSelection.Snapshot: TArray<Integer>;
begin Result := Copy(FIndices); end;

procedure TMVSelection.Restore(const Indices: TArray<Integer>);
begin FIndices := Copy(Indices); end;

function TMVSelection.Placement(Index: Integer): TMVPlacement;
begin
  Result := FSession.Document.Units[Index];
  Result.X := FLayout.Units[Index].Position.X; Result.Y := FLayout.Units[Index].Position.Y;
end;

function WorldBounds(const Item: TMVPlacement; const Bounds: TRectF): TRectF;
var Points: TMVHandlePoints; H: TMVHandle;
begin
  Points := MVHandles(Item, Bounds, 0);
  Result := TRectF.Create(Points[mhNW]);
  for H := mhN to mhW do
  begin
    Result.Left := Min(Result.Left, Points[H].X); Result.Right := Max(Result.Right, Points[H].X);
    Result.Top := Min(Result.Top, Points[H].Y); Result.Bottom := Max(Result.Bottom, Points[H].Y);
  end;
end;

procedure TMVSelection.SelectRange(const Bounds: TRectF; const Base: TArray<Integer>);
var I: Integer;
begin
  FIndices := Copy(Base);
  for I := 0 to High(FLayout.Units) do
    if (FLayout.Units[I].Image <> nil) and not Contains(I) and
      Bounds.IntersectsWith(WorldBounds(Placement(I), FLayout.Units[I].HitBounds)) then FIndices := FIndices + [I];
end;

procedure TMVSelection.Frame(out Item: TMVPlacement; out Bounds: TRectF);
var I: Integer; R: TRectF;
begin
  Item := Default(TMVPlacement); Bounds := TRectF.Empty;
  if Count = 0 then Exit;
  if FActive then begin Item := FCurrent; Bounds := FBounds; Exit; end;
  Item := Placement(First); Bounds := FLayout.Units[First].HitBounds;
  if Count = 1 then Exit;
  R := WorldBounds(Item, Bounds);
  for I in FIndices do R := TRectF.Union(R, WorldBounds(Placement(I), FLayout.Units[I].HitBounds));
  Item := Default(TMVPlacement);
  Item.X := R.CenterPoint.X; Item.Y := R.CenterPoint.Y;
  Item.Scale := 1; Item.ScaleX := 1; Item.ScaleY := 1;
  Bounds := R; Bounds.Offset(-Item.X, -Item.Y);
end;

procedure TMVSelection.BeginTransform;
var I: Integer;
begin
  Frame(FBase, FBounds); FCurrent := FBase;
  FBefore := Copy(FSession.Document.Units); FResolved := Copy(FBefore);
  for I in FIndices do FResolved[I] := Placement(I);
  FActive := True; FChanged := False;
end;

procedure TMVSelection.UpdatePositions;
var I: Integer;
begin
  for I in FIndices do
    if FSession.Document.Units[I].Positioned then
      FLayout.Units[I].Position := PointF(FSession.Document.Units[I].X, FSession.Document.Units[I].Y)
    else FLayout.Units[I].Position := PointF(FResolved[I].X, FResolved[I].Y);
end;

procedure TMVSelection.ApplyFrame(const Item: TMVPlacement);
var Candidate: TMVDocument; P, U, V: TPointF; A: TMVPlacement; I: Integer; SX, SY, LengthU: Double;
begin
  if not FActive or (Count = 0) then Exit;
  Candidate := CloneMVDocument(FSession.Document);
  if Count = 1 then Candidate.Units[First] := Item
  else
  begin
    SX := Item.ScaleX; SY := Item.ScaleY;
    for I in FIndices do
    begin
      A := FResolved[I];
      P := PointF((A.X - FBase.X) * SX, (A.Y - FBase.Y) * SY);
      P := MVRotate(P, Item.Angle) + PointF(Item.X, Item.Y);
      // 回転済み文字も同じアフィン変換に従う。QR分解で回転・倍率・せん断へ戻す。
      U := MVRotate(PointF(A.ScaleX, 0), A.Angle);
      V := MVRotate(PointF(A.Shear * A.ScaleY, A.ScaleY), A.Angle);
      U := PointF(U.X * SX, U.Y * SY); V := PointF(V.X * SX, V.Y * SY);
      LengthU := U.Length;
      A.ScaleX := LengthU; A.ScaleY := (U.X * V.Y - U.Y * V.X) / LengthU;
      A.Shear := (U.X * V.X + U.Y * V.Y) / (LengthU * A.ScaleY);
      A.Angle := RadToDeg(ArcTan2(U.Y, U.X)) + Item.Angle;
      A.X := P.X; A.Y := P.Y; A.Positioned := True;
      Candidate.Units[I] := A;
    end;
  end;
  try ValidateMVDocument(Candidate);
  except on E: EArgumentException do Exit; end;
  FSession.Document.Units := Candidate.Units;
  FCurrent := Item; FChanged := True;
  UpdatePositions;
end;

procedure TMVSelection.Finish(Cancel: Boolean);
var Current: TArray<TMVPlacement>;
begin
  if not FActive then Exit;
  if FChanged then
  begin
    Current := FSession.Document.Units;
    FSession.Document.Units := Copy(FBefore);
    if not Cancel then begin FSession.BeginChange; FSession.Document.Units := Current; end;
    UpdatePositions;
  end;
  FActive := False; FChanged := False;
  FBefore := nil; FResolved := nil;
end;

procedure TMVSelection.Nudge(DX, DY: Single);
var Item: TMVPlacement; Bounds: TRectF;
begin
  if Count = 0 then Exit;
  BeginTransform;
  Frame(Item, Bounds); Item.X := Item.X + DX; Item.Y := Item.Y + DY; Item.Positioned := True;
  ApplyFrame(Item); Finish(False);
end;

end.
