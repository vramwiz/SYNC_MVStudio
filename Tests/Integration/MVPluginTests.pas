unit MVPluginTests;

// 配備済みDLLを動的ロードし、公開ABI・登録項目・遅延初期化の実体を検証する。
interface

// DLLロードと終了を二巡する。ホストの編集データは使わない。
procedure RunPluginTests;

implementation

uses Winapi.Windows, System.SysUtils, AviUtl2FilterTypes, MVTestAssert, MVPluginEditorTests;

type
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;

var Pixels: array[0..128 * 128 - 1] of TPIXEL_RGBA; SetCalls: Integer; BackgroundRed: Byte;

procedure Input(Buffer: PPIXEL_RGBA); cdecl;
var I: Integer;
begin
  for I := 0 to High(Pixels) do
  begin
    Buffer^.R := BackgroundRed;
    Buffer^.G := 100;
    Buffer^.B := 160;
    Buffer^.A := 255;
    Inc(Buffer);
  end;
end;

procedure Output(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  if (Width = 128) and (Height = 128) then
  begin
    Inc(SetCalls);
    Move(Buffer^, Pixels[0], SizeOf(Pixels));
  end;
end;

procedure RunPluginTests;
var Module: HMODULE; Init: TInitialize; Uninit: TUninitialize; GetTable: TGetTable;
  Table: PFILTER_PLUGIN_TABLE; Items: PPointer; Header: PFILTER_ITEM_STRING;
  TextItem: PFILTER_ITEM_STRING; Editor: PFILTER_ITEM_BUTTON;
  Obj: TOBJECT_INFO; Video: TFILTER_PROC_VIDEO; I, Cycle: Integer; Seen: Boolean; TextValue: string;
  Version: Cardinal; HiddenCount: Integer; Rule: PFILTER_ITEM_HIDE_RULE;
begin
  Check(SizeOf(TFILTER_PLUGIN_TABLE) = 72, 'SDK Win64 filter table layout');
  Check(SizeOf(TFILTER_ITEM_BUTTON) = 32, 'SDK Win64 button callback2 layout');
  Check(SizeOf(Boolean) = 1, 'SDK C bool is one byte');
  Check(GetModuleHandle('sk4d.dll') = 0, 'Skia not loaded before DLL load');
  Module := LoadLibrary('C:\ProgramData\aviutl2\Plugin\SYNC_MVStudio\SYNC_MVStudio_Filter.auf2');
  Check(Module <> 0, 'deployed plugin loads');
  try
    Check(GetModuleHandle('sk4d.dll') = 0, 'DLL load does not initialize Skia');
    @Init := GetProcAddress(Module, 'InitializePlugin');
    @Uninit := GetProcAddress(Module, 'UninitializePlugin');
    @GetTable := GetProcAddress(Module, 'GetFilterPluginTable');
    Check(Assigned(Init) and Assigned(Uninit) and Assigned(GetTable), 'all three SDK exports exist');
    Table := GetTable;
    Check((Table <> nil) and (string(Table^.Name) = 'MVスタジオ'), 'Japanese table name is intact');
    Check((Table^.Flag and FILTER_FLAG_USERDATA) <> 0, 'SDK lifetime notifications enabled');
    Check(Assigned(Table^.Func_Create) and Assigned(Table^.Func_Destroy), 'both lifetime callbacks registered');
    HiddenCount := 0;
    Check(SizeOf(TFILTER_ITEM_HIDE_RULE) = 32, 'SDK hide rule ABI size');
    TextItem := nil;
    Editor := nil;
    Items := PPointer(Table^.Items);
    I := 0;
    while (Items^ <> nil) and (I < 100) do
    begin
      Header := PFILTER_ITEM_STRING(Items^);
      if string(Header^.ItemType) = 'hiderule' then
      begin
        Rule := PFILTER_ITEM_HIDE_RULE(Items^);
        Check((string(Rule^.ConditionName) = '編集モード') and (Rule^.ConditionOperator = 0) and
          (Rule^.ConditionValue = 1), 'legacy style is hidden only in extended mode');
        Inc(HiddenCount);
      end;
      if string(Header^.Name) = '歌詞' then TextItem := Header;
      if string(Header^.Name) = '拡張編集' then Editor := PFILTER_ITEM_BUTTON(Items^);
      Inc(Items);
      Inc(I);
    end;
    Check(HiddenCount = 12, 'all legacy font and coordinate controls have hide rules');
    Check((I > 20) and (I < 100), 'setting array has a nil terminator');
    Check((TextItem <> nil) and (string(TextItem^.ItemType) = 'text'), 'multiline lyric setting');
    Check((Editor <> nil) and Assigned(Editor^.Callback), 'default table is safe for legacy host');
    Obj := Default(TOBJECT_INFO);
    Obj.ID := 10;
    Obj.EffectID := 20;
    Obj.Width := 128;
    Obj.Height := 128;
    Obj.TimeTotal := 2;
    Obj.Time := 1;
    Obj.Layer := 2;
    Obj.FrameS := 0;
    Obj.FrameE := 149;
    Video := Default(TFILTER_PROC_VIDEO);
    Video.Object_ := @Obj;
    Video.GetImageData := Input;
    Video.SetImageData := Output;
    TextValue := '歌';
    TextItem^.Value := PChar(TextValue);
    for Cycle := 1 to 2 do
    begin
      if Cycle = 1 then Version := 2010301 else Version := 2011000;
      Check(Init(Version) = 1, 'InitializePlugin cycle ' + IntToStr(Cycle));
      try
        if Cycle = 1 then
          Check(Assigned(Editor^.Callback) and not Assigned(Editor^.Callback2), '2.1.3a uses legacy button ABI')
        else
          Check(not Assigned(Editor^.Callback) and Assigned(Editor^.Callback2), '2.1.10 uses targeted button ABI');
        Table^.Func_Create(20);
        Obj.EffectID := 20;
        Obj.Layer := 2;
        BackgroundRed := 40;
        SetCalls := 0;
        Check(Table^.Func_Proc_Video(@Video) = 1, 'SDK callback reports success');
        Check(SetCalls = 1, 'actual DLL renders lyric into output');
        Seen := False;
        for I := 0 to High(Pixels) do
          Seen := Seen or (Pixels[I].R <> BackgroundRed) or (Pixels[I].G <> 100) or (Pixels[I].B <> 160);
        Check(Seen, 'actual DLL produces visible text pixels');
        Table^.Func_Create(21);
        Obj.EffectID := 21;
        Obj.Layer := 3;
        BackgroundRed := 120;
        Check(Table^.Func_Proc_Video(@Video) = 1, 'second SDK object renders');
        RunPluginEditorTest(Editor, 1234, 40);
        RunPluginEditorTest(Editor, 5678, 120);
        Table^.Func_Destroy(20, nil);
        Table^.Func_Destroy(21, nil);
      finally Uninit; end;
      Check(GetModuleHandle('sk4d.dll') = 0, 'UninitializePlugin releases Skia');
    end;
    TextItem^.Value := nil;
  finally FreeLibrary(Module); end;
  Writeln('Deployed plugin ABI and lifecycle: OK');
end;

end.
