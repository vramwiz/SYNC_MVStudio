unit MVPluginEditorTests;

// 実DLLの編集ボタンからモーダル画面を開き、ホストAPI経由の確定まで検証する。
interface

uses AviUtl2FilterTypes;

// 初期化済みプラグインのcallback2を呼ぶ。テスト自身の画面だけを閉じる。
procedure RunPluginEditorTest(Editor: PFILTER_ITEM_BUTTON; Target: NativeUInt; BackgroundRed: Byte);

implementation

uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Math, Vcl.Graphics, MVTestAssert,
  MVDocument, MVStoredDocument, MVTextUnits;

var
  SavedData, ReturnedValue: UTF8String;
  ModeValue: string;
  Ticks, EditorWindows, ErrorWindows: Integer;
  TargetObject: NativeUInt;
  ExpectedEffect: string;
  WrongTarget: Boolean;
  ExpectedRed: Byte;
  BackgroundSeen: Boolean;
  HostLyric: string;

function ReadValue(Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR): PAnsiChar; cdecl;
begin
  WrongTarget := WrongTarget or (NativeUInt(Obj) <> TargetObject) or (string(Effect) <> ExpectedEffect);
  if string(Item) = '編集モード' then ReturnedValue := UTF8String(ModeValue)
  else if string(Item) = '歌詞' then ReturnedValue := UTF8String(
    StringReplace(StringReplace(HostLyric, '\', '\\', [rfReplaceAll]), #10, '\n', [rfReplaceAll]))
  else ReturnedValue := SavedData;
  Result := PAnsiChar(ReturnedValue);
end;

function WriteValue(Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR; Value: PAnsiChar): Boolean; cdecl;
begin
  WrongTarget := WrongTarget or (NativeUInt(Obj) <> TargetObject) or (string(Effect) <> ExpectedEffect);
  if string(Item) = '編集モード' then
  begin
    Result := string(UTF8String(Value)) = '拡張';
    if Result then ModeValue := string(UTF8String(Value));
    Exit;
  end;
  SavedData := UTF8String(Value);
  Result := True;
end;

function GetFocus: OBJECT_HANDLE; cdecl;
begin
  Result := Pointer(TargetObject);
end;

function CountEffects(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Integer; cdecl;
begin
  Result := 1;
end;

function GetLocation(Obj: OBJECT_HANDLE): TOBJECT_LAYER_FRAME; cdecl;
begin
  if NativeUInt(Obj) = 1234 then Result.Layer := 2 else Result.Layer := 3;
  Result.StartFrame := 0;
  Result.EndFrame := 149;
end;

function FindEffect(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Pointer; cdecl;
begin
  if NativeUInt(Obj) = 1234 then Result := Pointer(20) else Result := Pointer(21);
end;

function GetEffectID(Effect: Pointer): Int64; cdecl;
begin
  Result := NativeInt(Effect);
end;

function InspectCanvas(Window: HWND; Param: LPARAM): BOOL; stdcall;
var Name: array[0..255] of Char; Bounds: TRect; Bitmap: Vcl.Graphics.TBitmap; Offset: Integer;
begin
  Result := True;
  GetClassName(Window, Name, Length(Name));
  if string(Name) <> 'TMVEditorCanvas' then Exit;
  GetClientRect(Window, Bounds);
  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Bitmap.SetSize(Bounds.Right, Bounds.Bottom);
    SendMessage(Window, WM_PRINT, Bitmap.Canvas.Handle, PRF_CLIENT or PRF_ERASEBKGND);
    Offset := Round(Min(Bounds.Right - 24, Bounds.Bottom - 24) * 0.45);
    BackgroundSeen := Bitmap.Canvas.Pixels[Bounds.Right div 2 + Offset, Bounds.Bottom div 2 - Offset] =
      TColor(RGB(ExpectedRed, 100, 160));
  finally Bitmap.Free; end;
end;

function CloseTestWindow(Window: HWND; Param: LPARAM): BOOL; stdcall;
var Name: array[0..255] of Char;
begin
  Result := True;
  GetClassName(Window, Name, Length(Name));
  if string(Name) = 'TMVEditorForm' then
  begin
    Inc(EditorWindows);
    SetWindowPos(Window, 0, -30000, -30000, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
    if Ticks >= 3 then
    begin
      EnumChildWindows(Window, @InspectCanvas, 0);
      PostMessage(Window, WM_CLOSE, 0, 0);
    end;
  end
  else if (string(Name) = '#32770') or (string(Name) = 'TMessageForm') then
  begin
    Inc(ErrorWindows);
    PostMessage(Window, WM_CLOSE, 0, 0);
  end;
end;

procedure CloseTimer(Window: HWND; Msg: UINT; TimerID: UINT_PTR; Time: DWORD); stdcall;
begin
  Inc(Ticks);
  EnumThreadWindows(GetCurrentThreadID, @CloseTestWindow, 0);
  if Ticks > 50 then PostQuitMessage(1);
end;

procedure RunPluginEditorTest(Editor: PFILTER_ITEM_BUTTON; Target: NativeUInt; BackgroundRed: Byte);
var Edit: TEDIT_SECTION; Info: array[0..19] of Integer; Timer: UINT_PTR;
  Document: TMVDocument; Error: string;
begin
  Edit := Default(TEDIT_SECTION);
  FillChar(Info, SizeOf(Info), 0);
  Info[0] := 1920;
  Info[1] := 1080;
  Info[2] := 30;
  Info[3] := 1;
  Edit.Info := @Info;
  Edit.GetObjectItemValue := ReadValue;
  Edit.SetObjectItemValue := WriteValue;
  Edit.GetObjectLayerFrame := GetLocation;
  Edit.GetFocusObject := GetFocus;
  Edit.CountObjectEffect := CountEffects;
  Edit.FindEffect := FindEffect;
  Edit.GetEffectID := GetEffectID;
  TargetObject := Target;
  WrongTarget := False;
  ExpectedRed := BackgroundRed;
  BackgroundSeen := False;
  if Target = 1234 then HostLyric := '朝' else HostLyric := '夜' + #10 + '歌\n';
  // 保存済み文書とホスト歌詞が違っても、対象APIの最新歌詞へ更新する。
  Document := DefaultMVDocument;
  SetMVText(Document, '旧');
  SavedData := UTF8String(EncodeMVStoredDocument(Document));
  ModeValue := '標準';
  Ticks := 0;
  EditorWindows := 0;
  ErrorWindows := 0;
  Timer := SetTimer(0, 0, 100, @CloseTimer);
  try
    if Assigned(Editor^.Callback2) then
    begin
      ExpectedEffect := 'MVスタジオ:1';
      Editor^.Callback2(@Edit, Pointer(Target), PChar(ExpectedEffect), '拡張編集');
    end
    else
    begin
      ExpectedEffect := 'MVスタジオ';
      Check(Assigned(Editor^.Callback), 'legacy host has a non-nil callback');
      Editor^.Callback(@Edit);
    end;
  finally KillTimer(0, Timer); end;
  Check(EditorWindows > 0, 'actual DLL opens extended editor');
  Check(ErrorWindows = 0, 'actual DLL editor reports no errors');
  Check((ModeValue = '拡張') and (Copy(string(SavedData), 1, 4) = 'MV1:'), 'actual DLL editor saves on close');
  Check(not WrongTarget, 'actual DLL editor saves to requested object and effect');
  Check(BackgroundSeen, 'actual DLL editor displays captured background for requested object');
  Check(TryDecodeMVStoredDocument(string(SavedData), Document, Error) and (Document.Text = HostLyric),
    'actual DLL placement editor reads lyric from exact host object');
end;

end.
