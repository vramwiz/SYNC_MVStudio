unit MVStyleGesture;

// 書式の連続編集をプレビューし、取消時は開始時の組版資源へ確実に戻す。
interface

uses MVDocument, MVEditSession, MVLayout, MVStyleTypes;

type
  TMVStyleGesture = class
  private
    FSession: TMVEditSession; // 所有しない作業文書。
    FBefore: TMVDocument; // 変更前の独立した文書。
    FOriginalLayout: TMVLayout; // 編集中は退避し、確定時だけ解放する。
    FActive: Boolean; // 退避資源を保持しているか。
  public
    // 呼出元は終了または破棄前にFinishを呼び、組版の所有権を返す。
    procedure BeginEdit(Session: TMVEditSession; Layout: TMVLayout);
    // 組版成功後だけ反映し、失敗時は直前のプレビューを維持する。
    procedure Preview(const Candidate: TMVDocument; var Layout: TMVLayout);
    // Cancelなら開始状態へ戻す。変更がある確定だけを1回のUndoへ記録する。
    procedure Finish(Cancel: Boolean; var Layout: TMVLayout);
    property Active: Boolean read FActive;
    property Before: TMVDocument read FBefore;
  end;

// 選択範囲の書式を合成する。未選択なら共通書式だけに適用する。
function MVDocumentWithStyle(const Source: TMVDocument; const Indices: TArray<Integer>;
  const Style: TMVStyle; Fields: TMVStyleFields): TMVDocument;

implementation

function MVDocumentWithStyle(const Source: TMVDocument; const Indices: TArray<Integer>;
  const Style: TMVStyle; Fields: TMVStyleFields): TMVDocument;
var I: Integer;
begin
  Result := CloneMVDocument(Source);
  if Length(Indices) = 0 then ApplyMVStyleFields(Result.Style, Style, Fields)
  else
    for I in Indices do
    begin
      ApplyMVStyleFields(Result.Units[I].Style, Style, Fields);
      Result.Units[I].StyleFields := Result.Units[I].StyleFields + Fields;
    end;
end;

function SameStyles(const A, B: TMVDocument): Boolean;
var I: Integer;
begin
  if MVStyleDifferences(A.Style, B.Style) <> [] then Exit(False);
  if Length(A.Units) <> Length(B.Units) then Exit(False);
  for I := 0 to High(A.Units) do
    if (A.Units[I].StyleFields <> B.Units[I].StyleFields) or
      ((MVStyleDifferences(A.Units[I].Style, B.Units[I].Style) *
        (A.Units[I].StyleFields + B.Units[I].StyleFields)) <> []) then Exit(False);
  Result := True;
end;

procedure TMVStyleGesture.BeginEdit(Session: TMVEditSession; Layout: TMVLayout);
begin
  FBefore := CloneMVDocument(Session.Document);
  FSession := Session;
  FOriginalLayout := Layout;
  FActive := True;
end;

procedure TMVStyleGesture.Preview(const Candidate: TMVDocument; var Layout: TMVLayout);
var Prepared: TMVDocument; NewLayout: TMVLayout; I: Integer;
begin
  if not FActive or SameStyles(FSession.Document, Candidate) then Exit;
  Prepared := CloneMVDocument(Candidate);
  NewLayout := TMVLayout.Create(Prepared);
  try
    // 縁幅による字送りの再計算で文字が逃げないよう、変化した自動配置は開始位置へ固定する。
    for I := 0 to High(Prepared.Units) do
      if not Prepared.Units[I].Positioned and
        (NewLayout.Units[I].Position <> FOriginalLayout.Units[I].Position) then
      begin
        Prepared.Units[I].X := FOriginalLayout.Units[I].Position.X;
        Prepared.Units[I].Y := FOriginalLayout.Units[I].Position.Y;
        Prepared.Units[I].Positioned := True;
        NewLayout.Units[I].Position := FOriginalLayout.Units[I].Position;
      end;
    ValidateMVDocument(Prepared);
  except
    NewLayout.Free;
    raise;
  end;
  if Layout <> FOriginalLayout then Layout.Free;
  Layout := NewLayout;
  FSession.Document := Prepared;
end;

procedure TMVStyleGesture.Finish(Cancel: Boolean; var Layout: TMVLayout);
begin
  if not FActive then Exit;
  if not Cancel and not SameStyles(FBefore, FSession.Document) then FSession.RecordChange(FBefore);
  FActive := False;
  if Cancel then
  begin
    if Layout <> FOriginalLayout then Layout.Free;
    Layout := FOriginalLayout;
    FSession.Document := FBefore;
  end
  else if Layout <> FOriginalLayout then FOriginalLayout.Free;
  FOriginalLayout := nil;
  FBefore := Default(TMVDocument);
end;

end.
