unit MVCoreTests;

// 日本語・絵文字の配置単位、保存、Undo、時間境界の独立した期待値を検証する。
interface

// SkiaやAviUtl2を起動せずにモデルと演出を検証する。
procedure RunCoreTests;

implementation

uses System.SysUtils, System.Math, MVTestAssert, MVDocument, MVTextUnits,
  MVDocumentJson, MVAnimation, MVEditSession;

procedure TestTextAndStorage;
var D, CopyD, Restored: TMVDocument; Encoded, Error, Before: string; Rejected: Boolean;
begin
  D := DefaultMVDocument;
  SetMVText(D, 'か' + #$3099 + '👩‍💻🇯🇵' + #13#10 + '歌');
  Check(Length(D.Units) = 5, 'combining + ZWJ + flag + LF + Japanese = 5 units');
  Check(D.Units[0].Text = 'か' + #$3099, 'combining dakuten stays attached');
  Check(D.Units[3].Text = #10, 'CRLF normalized to one LF');
  D.Units[0].X := 123;
  D.Units[0].Positioned := True;
  D.Units[4].Angle := 25;
  CopyD := CloneMVDocument(D);
  CopyD.Units[0].X := 999;
  Check(D.Units[0].X = 123, 'clone owns its placement array');
  Encoded := EncodeMVDocument(D);
  if not TryDecodeMVDocument(Encoded, Restored, Error) then raise Exception.Create(Error + sLineBreak + Encoded);
  Check(True, 'JSON round trip succeeds');
  Check(EncodeMVDocument(Restored) = Encoded, 'all document values round trip');
  Check((Restored.Units[4].Angle = 25) and not Restored.Units[4].Positioned,
    'automatic position preserves individual rotation');
  Before := EncodeMVDocument(Restored);
  Check(not TryDecodeMVDocument('{broken', Restored, Error), 'broken JSON rejected');
  Check((Error <> '') and (EncodeMVDocument(Restored) = Before), 'failed decode leaves prior document intact');
  Check(not TryDecodeMVDocument(StringReplace(Encoded, '"version":3', '"version":99', []),
    Restored, Error), 'future version rejected');
  SetMVText(D, 'か' + #$3099 + '追加👩‍💻🇯🇵' + #10 + '歌');
  Check((D.Units[0].X = 123) and (D.Units[High(D.Units)].Angle = 25),
    'text insertion preserves matching prefix and suffix placement');
  Before := D.Text;
  Rejected := False;
  try SetMVText(D, #$D800); except on E: EArgumentException do Rejected := True; end;
  Check(Rejected and (D.Text = Before), 'invalid surrogate rejected without losing document');
  Rejected := False;
  try SetMVText(D, StringOfChar('x', 513)); except on E: EArgumentException do Rejected := True; end;
  Check(Rejected and (D.Text = Before), 'placement limit enforced before mutation');
  D.Style.FontSize := NaN;
  Rejected := False;
  try EncodeMVDocument(D); except on E: EArgumentException do Rejected := True; end;
  Check(Rejected, 'nonfinite values cannot be saved');
end;

procedure TestEditing;
var D: TMVDocument; A, B: TMVEditSession;
begin
  D := DefaultMVDocument;
  SetMVText(D, '二つの歌詞');
  A := TMVEditSession.Create(D);
  B := TMVEditSession.Create(D);
  try
    A.BeginChange;
    A.Document.Units[0].X := 70;
    Check(B.Document.Units[0].X = 0, 'two editor sessions remain independent');
    A.Undo;
    Check(A.Document.Units[0].X = 0, 'Undo restores original coordinates');
    A.Redo;
    Check(A.Document.Units[0].X = 70, 'Redo restores moved coordinates');
    A.Undo;
    A.BeginChange;
    A.Document.Units[0].X := -50;
    A.Redo;
    Check(A.Document.Units[0].X = -50, 'new edit discards redo branch');
  finally B.Free; A.Free; end;
end;

procedure TestAnimation;
var D: TMVDocument; M, Again: TMVMotion; I: Integer;
begin
  D := DefaultMVDocument;
  D.Entrance := 1;
  D.ExitEffect := 1;
  M := EvaluateMVMotion(D, 0, 1, 1, 1, 0, 1);
  Check(M.Opacity = 0, 'fade starts invisible');
  M := EvaluateMVMotion(D, 0.25, 1, 1, 1, 0, 1);
  Check(Abs(M.Opacity - 0.5) < 0.00001, 'overlong entrance + exit fit duration proportionally');
  M := EvaluateMVMotion(D, 0.5, 1, 1, 1, 0, 1);
  Check(M.Opacity = 1, 'zero hold interval still reaches full opacity');
  M := EvaluateMVMotion(D, 1, 1, 1, 1, 0, 1);
  Check(M.Opacity = 0, 'end boundary excluded');
  M := EvaluateMVMotion(D, 0, 1, 0, 0, 0, 1);
  Check(M.Opacity = 1, 'zero durations switch immediately');
  D.Stagger := True;
  M := EvaluateMVMotion(D, 0.2, 4, 1, 1, 0, 3);
  Check(Abs(M.Opacity - 0.5) < 0.00001, 'first staggered character uses same animation span');
  M := EvaluateMVMotion(D, 0.2, 4, 1, 1, 2, 3);
  Check(M.Opacity = 0, 'last staggered character waits');
  M := EvaluateMVMotion(D, 1, 4, 1, 1, 2, 3);
  Check(M.Opacity = 1, 'all characters finish within entrance interval');
  D.Stagger := False;
  D.ExitEffect := 6;
  M := EvaluateMVMotion(D, 0.5, 4, 1, 1, 2, 3);
  Check(Abs(M.Opacity - 0.5) < 0.00001, 'typewriter exit does not stagger independent fade entrance');
  D.Hold := 3;
  M := EvaluateMVMotion(D, 0.7, 4, 1, 1, 1, 3);
  for I := 20 downto 0 do EvaluateMVMotion(D, I / 10, 4, 1, 1, 1, 3);
  Again := EvaluateMVMotion(D, 0.7, 4, 1, 1, 1, 3);
  Check((M.Y = Again.Y) and (M.Opacity = Again.Opacity), 'reverse seeking does not change evaluation');
end;

procedure RunCoreTests;
begin
  TestTextAndStorage;
  TestEditing;
  TestAnimation;
  Writeln('Core: OK');
end;

end.
