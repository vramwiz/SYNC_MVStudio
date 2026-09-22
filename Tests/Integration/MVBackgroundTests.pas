unit MVBackgroundTests;

// 合成前背景の独立性、取得対象の照合、空歌詞・失敗時の取得を検証する。
interface

// 実Skiaと模擬SDK入力を使い、対象間の画像混入と参照共有を検証する。
procedure RunBackgroundTests;

implementation

uses System.SysUtils, MVTestAssert, AviUtl2FilterTypes, MVFilterContext, MVContextRegistry,
  MVBackgroundFrame, MVDocument, MVTextUnits, MVFilterSettings, MVEditorBackground,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap;

var SourcePixels: TBytes; Writes, NewApiCalls: Integer;

procedure ReadImage(Buffer: PPIXEL_RGBA); cdecl;
begin
  Move(SourcePixels[0], Buffer^, Length(SourcePixels));
end;

procedure WriteImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Inc(Writes);
end;

procedure Capture(const Context: IMVFilterContext; Layer: Integer; Red: Byte;
  const Settings: TMVSettings; HasInput: Boolean = True; Width: Integer = 128);
var Obj: TOBJECT_INFO; Video: TFILTER_PROC_VIDEO; I: Integer;
begin
  SetLength(SourcePixels, 128 * 72 * 4);
  for I := 0 to 128 * 72 - 1 do
  begin
    SourcePixels[I * 4] := Red;
    SourcePixels[I * 4 + 1] := 80;
    SourcePixels[I * 4 + 2] := 160;
    SourcePixels[I * 4 + 3] := 255;
  end;
  Obj := Default(TOBJECT_INFO);
  Obj.Width := Width;
  Obj.Height := 72;
  Obj.Layer := Layer;
  Obj.FrameS := 10;
  Obj.FrameE := 99;
  Obj.Time := 1;
  Obj.TimeTotal := 3;
  Video := Default(TFILTER_PROC_VIDEO);
  Video.Object_ := @Obj;
  if HasInput then Video.GetImageData := ReadImage;
  Video.SetImageData := WriteImage;
  Context.Render(@Video, Settings);
end;

function FindEffect(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Pointer; cdecl;
begin
  Inc(NewApiCalls);
  Result := Pointer(102);
end;

function GetEffectID(Effect: Pointer): Int64; cdecl;
begin
  Inc(NewApiCalls);
  Result := NativeInt(Effect);
end;

function GetLocation(Obj: OBJECT_HANDLE): TOBJECT_LAYER_FRAME; cdecl;
begin
  Result.Layer := 2;
  Result.StartFrame := 10;
  Result.EndFrame := 99;
end;

function CountEffects(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Integer; cdecl;
begin
  Result := 1;
end;

procedure TestIdentity;
var Edit: TEDIT_SECTION; ID: Int64; Location: TOBJECT_LAYER_FRAME;
begin
  Edit := Default(TEDIT_SECTION);
  Check(NativeUInt(@@Edit.FindEffect) - NativeUInt(@Edit) = 50 * 8, 'SDK find_effect offset');
  Check(NativeUInt(@@Edit.GetEffectID) - NativeUInt(@Edit) = 82 * 8, 'SDK get_effect_id offset');
  Edit.FindEffect := FindEffect;
  Edit.GetEffectID := GetEffectID;
  Edit.GetObjectLayerFrame := GetLocation;
  Edit.CountObjectEffect := CountEffects;
  NewApiCalls := 0;
  Check(ResolveMVBackgroundTarget(@Edit, Pointer(1), 'MVスタジオ', 2010301, ID, Location), 'legacy background target');
  Check((ID = 0) and (Location.Layer = 2) and (NewApiCalls = 0), 'legacy never calls new SDK fields');
  Check(ResolveMVBackgroundTarget(@Edit, Pointer(1), 'MVスタジオ:1', 2011000, ID, Location), 'modern background target');
  Check((ID = 102) and (NewApiCalls = 2), 'modern target uses exact effect ID');
end;

procedure RunBackgroundTests;
var Registry: TMVContextRegistry; A, B: IMVFilterContext; Frame, Held: TMVBackgroundFrame;
  Settings: TMVSettings; Location: TOBJECT_LAYER_FRAME;
begin
  TestIdentity;
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  Registry := TMVContextRegistry.Create;
  try
    A := Registry.Acquire(101);
    B := Registry.Acquire(102);
    Settings := Default(TMVSettings);
    Settings.Document := DefaultMVDocument;
    Location := GetLocation(nil);
    Check(not A.CopyBackground(Frame), 'unrendered context has no background');
    Writes := 0;
    Capture(A, 1, 40, Settings);
    Check((Writes = 0) and A.CopyBackground(Frame), 'empty lyrics capture background without changing output');
    Check(Frame.IsValid and (Frame.Width = 128) and (Frame.Height = 72), 'captured dimensions retained');
    Held := Frame;
    Frame.Pixels[0] := 99;
    Check(A.CopyBackground(Frame) and (Frame.Pixels[0] = 40), 'editor snapshot does not share render buffer');
    SetMVText(Settings.Document, '歌');
    Capture(A, 1, 50, Settings);
    Check((Writes = 1) and A.CopyBackground(Frame), 'background also captured while rendering lyrics');
    Check(CompareMem(@Frame.Pixels[0], @SourcePixels[0], Length(SourcePixels)), 'captured image excludes own lyrics');
    Check(Held.Pixels[4] = 40, 'later capture cannot change opened editor snapshot');
    Capture(B, 2, 180, Settings);
    Check(Registry.CopyBackground(102, Location, Frame) and (Frame.Pixels[0] = 180), 'ID lookup returns second background');
    Location.Layer := 1;
    Check(Registry.CopyBackground(0, Location, Frame) and (Frame.Pixels[0] = 50), 'legacy lookup returns first background');
    Check(not Registry.CopyBackground(999, Location, Frame), 'missing ID cannot fall back to unrelated background');
    Capture(A, 2, 60, Settings);
    Location.Layer := 2;
    Check(not Registry.CopyBackground(0, Location, Frame), 'ambiguous legacy location is rejected');
    Check(Registry.CopyBackground(101, Location, Frame) and (Frame.Pixels[0] = 60), 'exact ID disambiguates same location');
    Settings.Extended := True;
    Settings.Data := 'broken';
    Capture(A, 1, 70, Settings);
    Check(A.CopyBackground(Frame) and (Frame.Pixels[0] = 70), 'invalid lyric data still refreshes background');
    Capture(A, 1, 80, Settings, False);
    Check(not A.CopyBackground(Frame), 'missing input invalidates stale background');
    Capture(A, 1, 90, Settings);
    Capture(A, 1, 90, Settings, True, 0);
    Check(not A.CopyBackground(Frame), 'invalid dimensions invalidate stale background');
    Registry.Remove(102);
    Check(not Registry.CopyBackground(102, Location, Frame), 'deleted target cannot return cached background');
  finally
    Registry.Free;
    A := nil;
    B := nil;
    TTextRendererSkiaRuntime.Release;
  end;
  Writeln('Background ownership and target lookup: OK');
end;

end.
