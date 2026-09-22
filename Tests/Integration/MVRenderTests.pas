unit MVRenderTests;

// SDK画像入出力を模擬し、複数対象・同一対象の並行描画と寿命を検証する。
interface

// 実際のSkia描画を使う。ホストやユーザーのプロジェクトは操作しない。
procedure RunRenderTests;

implementation

uses System.SysUtils, System.Classes, System.Skia, MVTestAssert, MVDocument, MVTextUnits,
  MVStoredDocument, MVFilterSettings, MVFilterContext, MVContextRegistry, AviUtl2FilterTypes,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap;

const FrameWidth = 480; FrameHeight = 270;

type
  TFrame = record
    Source: TArray<TPIXEL_RGBA>; // 読み取り元。描画後も変更されてはならない。
    Output: TArray<TPIXEL_RGBA>; // SetImageDataでホストへ渡された画像の複写。
    SetCalls: Integer; // 元画像保持の経路では0。
  end;

threadvar ActiveFrame: ^TFrame;

procedure GetImage(Buffer: PPIXEL_RGBA); cdecl;
begin
  Move(ActiveFrame^.Source[0], Buffer^, Length(ActiveFrame^.Source) * 4);
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Inc(ActiveFrame^.SetCalls);
  SetLength(ActiveFrame^.Output, Width * Height);
  Move(Buffer^, ActiveFrame^.Output[0], Width * Height * 4);
end;

function FrameFor(const Context: IMVFilterContext; const Settings: TMVSettings; Time: Double): TFrame;
var Obj: TOBJECT_INFO; Video: TFILTER_PROC_VIDEO; I: Integer;
begin
  Result := Default(TFrame);
  SetLength(Result.Source, FrameWidth * FrameHeight);
  for I := 0 to High(Result.Source) do
  begin
    Result.Source[I].R := 10;
    Result.Source[I].G := 20;
    Result.Source[I].B := 30;
    Result.Source[I].A := 100;
  end;
  Obj := Default(TOBJECT_INFO);
  Obj.Width := FrameWidth;
  Obj.Height := FrameHeight;
  Obj.Time := Time;
  Obj.TimeTotal := 3;
  Video := Default(TFILTER_PROC_VIDEO);
  Video.Object_ := @Obj;
  Video.GetImageData := GetImage;
  Video.SetImageData := SetImage;
  ActiveFrame := @Result;
  try Context.Render(@Video, Settings); finally ActiveFrame := nil; end;
end;

function SameFrame(const A, B: TFrame): Boolean;
begin
  Result := (Length(A.Output) = Length(B.Output)) and (A.SetCalls = B.SetCalls);
  if Result and (Length(A.Output) > 0) then
    Result := CompareMem(@A.Output[0], @B.Output[0], Length(A.Output) * 4);
end;

procedure CheckConcurrent(const A, B: IMVFilterContext; const SA, SB: TMVSettings; const FA, FB: TFrame);
var Threads: array[0..3] of TThread; Failures: array[0..3] of string; I: Integer;
  Work: TProc<Integer>;
begin
  Work :=
    procedure(Index: Integer)
    var J: Integer; Frame: TFrame;
    begin
      try
        for J := 1 to 20 do
        begin
          if Odd(Index) then Frame := FrameFor(B, SB, 1) else Frame := FrameFor(A, SA, 1);
          if (Odd(Index) and not SameFrame(Frame, FB)) or (not Odd(Index) and not SameFrame(Frame, FA)) then
            raise Exception.Create('parallel frame differs');
        end;
      except on E: Exception do Failures[Index] := E.Message; end;
    end;
  Threads[0] := TThread.CreateAnonymousThread(procedure begin Work(0); end);
  Threads[1] := TThread.CreateAnonymousThread(procedure begin Work(1); end);
  Threads[2] := TThread.CreateAnonymousThread(procedure begin Work(2); end);
  Threads[3] := TThread.CreateAnonymousThread(procedure begin Work(3); end);
  for I := 0 to 3 do begin Threads[I].FreeOnTerminate := False; Threads[I].Start; end;
  for I := 0 to 3 do begin Threads[I].WaitFor; Threads[I].Free; end;
  Work := nil; // ワーカーとラッパーが共有するクロージャーフレームの参照環を解く。
  for I := 0 to 3 do Check(Failures[I] = '', 'parallel worker ' + IntToStr(I) + ': ' + Failures[I]);
end;

procedure RunRenderTests;
var Registry: TMVContextRegistry; A, B, Lease, Probe: IMVFilterContext; SA, SB, Extended: TMVSettings;
  FA, FB, Repeated, Changed: TFrame; Image: ISkImage; BaseAcquired: Boolean; Key: string;
begin
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  BaseAcquired := True;
  Registry := TMVContextRegistry.Create;
  try
    A := Registry.Acquire(101);
    B := Registry.Acquire(102);
    Check(A <> B, 'different effects have independent contexts');
    Probe := Registry.Acquire(101);
    Check(A = Probe, 'same effect reuses context');
    Probe := nil;
    SA := Default(TMVSettings);
    SA.Document := DefaultMVDocument;
    SetMVText(SA.Document, '響く歌');
    SA.Document.Style.Color := $FFFF4040;
    SA.Document.Style.OutlineWidth := 0;
    SA.X := -70;
    SB := SA;
    SB.Document := CloneMVDocument(SA.Document);
    SB.Document.Style.Color := $FF4080FF;
    SB.X := 70;
    FA := FrameFor(A, SA, 1);
    FB := FrameFor(B, SB, 1);
    Check((FA.SetCalls = 1) and (FB.SetCalls = 1), 'both objects produce images');
    Check(not SameFrame(FA, FB), 'different colors and positions yield different images');
    Check(CompareMem(@FA.Source[0], @FA.Output[0], 4), 'untouched corner retains source RGBA');
    Check(not CompareMem(@FA.Source[0], @FA.Output[0], Length(FA.Source) * 4), 'lyrics actually change pixels');
    Repeated := FrameFor(A, SA, 1);
    Check(SameFrame(FA, Repeated), 'interleaving another object does not contaminate first');
    CheckConcurrent(A, B, SA, SB, FA, FB);
    Key := MVSettingsKey(SA);
    SA.Document.Hold := 1;
    Check(MVSettingsKey(SA) = Key, 'animation-only change does not invalidate glyph cache');
    Changed := FrameFor(A, SA, 0.5);
    Check(not SameFrame(FA, Changed), 'animation update applies even with reused glyph cache');
    SA.Document.Hold := 0;
    Repeated := FrameFor(A, SA, 1);
    Check(SameFrame(FA, Repeated), 'return to static display restores original frame');
    Extended := SA;
    Extended.Extended := True;
    Extended.Document := CloneMVDocument(SA.Document);
    Extended.Document.Units[0].X := -150;
    Extended.Document.Units[0].Y := -60;
    Extended.Document.Units[0].Positioned := True;
    Extended.Data := EncodeMVStoredDocument(Extended.Document);
    Changed := FrameFor(A, Extended, 1);
    Check(not SameFrame(FA, Changed), 'extended saved character position is rendered');
    Extended.Document.Text := '';
    Repeated := FrameFor(A, Extended, 1);
    Check(Repeated.SetCalls = 0, 'clearing host lyric hides saved extended text without reopening editor');
    Extended.Document.Text := '新しい歌';
    Repeated := FrameFor(A, Extended, 1);
    Check((Repeated.SetCalls = 1) and not SameFrame(Changed, Repeated),
      'host lyric update invalidates extended glyph cache');
    Changed := Repeated;
    Extended.Document.Style.Color := $FF00FF00;
    Repeated := FrameFor(A, Extended, 1);
    Check(not SameFrame(Changed, Repeated), 'host decoration applies in extended mode');
    Key := MVSettingsKey(Extended);
    Extended.Document.Hold := 1;
    Changed := FrameFor(A, Extended, 0.5);
    Check((MVSettingsKey(Extended) = Key) and not SameFrame(Changed, Repeated),
      'host animation applies in extended mode with reused glyph cache');
    Extended.Document.EditorSettings := True;
    Extended.Document.Units[0].ScaleX := 2;
    Extended.Document.Units[0].ScaleY := 0.5;
    SetMVText(Extended.Document, Extended.Document.Text);
    Extended.Data := EncodeMVStoredDocument(Extended.Document);
    Changed := FrameFor(A, Extended, 0.5);
    Extended.Document.Style.FontSize := 20;
    Repeated := FrameFor(A, Extended, 0.5);
    Check(SameFrame(Changed, Repeated), 'editor-owned font ignores legacy host override');
    Extended.Document.Hold := 4;
    Repeated := FrameFor(A, Extended, 0.5);
    Check(not SameFrame(Changed, Repeated), 'host animation changes editor-owned document with reused cache');
    Extended.Data := '{invalid';
    Changed := FrameFor(A, Extended, 1);
    Check(Changed.SetCalls = 0, 'invalid extended document leaves host image untouched');
    Repeated := FrameFor(A, SA, 1);
    Check(SameFrame(FA, Repeated), 'valid standard settings recover after invalid extended settings');
    Image := TSkImage.MakeRasterCopy(TSkImageInfo.Create(FrameWidth, FrameHeight,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul), @FA.Output[0], FrameWidth * 4);
    Image.EncodeToFile(ExtractFilePath(ParamStr(0)) + 'render-standard.png');
    Image := nil;
    Lease := A;
    Registry.Remove(101);
    Probe := Registry.Acquire(101);
    Check(Lease <> Probe, 'destroyed effect registration does not reuse retired context');
    Probe := nil;
    FreeAndNil(Registry);
    A := nil;
    B := nil;
    TTextRendererSkiaRuntime.Release;
    BaseAcquired := False;
    Check(TTextRendererSkiaRuntime.IsAcquired, 'active lease keeps Skia alive after registry shutdown');
    Repeated := FrameFor(Lease, SA, 1);
    Check(SameFrame(FA, Repeated), 'active lease still renders after registry shutdown');
    Lease := nil;
    Check(not TTextRendererSkiaRuntime.IsAcquired, 'final lease releases Skia');
  finally
    Image := nil;
    Probe := nil;
    Lease := nil;
    A := nil;
    B := nil;
    Registry.Free;
    if BaseAcquired then TTextRendererSkiaRuntime.Release;
  end;
  Writeln('Render and concurrent contexts: OK');
end;

end.
