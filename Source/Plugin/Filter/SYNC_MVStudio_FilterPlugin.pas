unit SYNC_MVStudio_FilterPlugin;

// MVスタジオのSDK境界。設定・描画・編集は専用ユニットへ委譲する。
interface
uses
  AviUtl2FilterTypes, MVBackgroundFrame;

// DLLロード完了後にSkiaを取得する。
procedure InitializeMVStudioFilter(Version: Cardinal);
// ホストの終了通知でSkiaの参照を解放する。
procedure FinalizeMVStudioFilter;
// MVスタジオのフィルターテーブルを返す。
function GetMVStudioFilterTable: PFILTER_PLUGIN_TABLE;
// 編集対象の合成前画像を独立した配列へ複写する。未取得・対象不明時はFalse。
function CopyMVStudioBackground(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect: string;
  out Frame: TMVBackgroundFrame): Boolean;

implementation
uses
  PluginFilterTable,
  System.SysUtils,
  System.SyncObjs,
  MVFilterSettings,
  MVFilterContext,
  MVContextRegistry,
  MVEditorHost,
  MVEditorLegacy,
  MVEditorBackground,
  TextRendererSkiaBootstrap,
  TextRendererSkiaRuntime;

var
  Registry: TMVContextRegistry; // SDK生成・破棄通知に結び付く対象別コンテキスト。
  LifecycleLock: TCriticalSection; // 初期化・終了と取得の競合を防ぐ。
  HostVersion: Cardinal; // 旧SDKの編集構造体末尾を読み越さないための本体版。

function CreateEffect(EffectID: Int64): Pointer; cdecl;
begin
  // 文書やSkia資源は最初の描画で生成するため、ここではユーザーデータ不要。
  Result := nil;
end;

procedure DestroyEffect(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    LifecycleLock.Acquire;
    try
      if Registry <> nil then Registry.Remove(EffectID);
    finally LifecycleLock.Release; end;
  except
    // SDKの終了・Undo解放経路へDelphi例外を返さない。
  end;
end;

function MVStudioProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Context: IMVFilterContext;
  Settings: TMVSettings;
begin
  Result := 1;
  try
    if (Video = nil) or (Video^.Object_ = nil) then Exit;
    LifecycleLock.Acquire;
    try
      if Registry = nil then Exit;
      Settings := ReadMVSettings;
      Context := Registry.Acquire(Video^.Object_^.EffectID);
    finally LifecycleLock.Release; end;
    Context.Render(Video, Settings);
  except
    // 不正設定・描画失敗ではSetImageDataを呼ばず入力画像を維持する。
  end;
end;

procedure InitializeMVStudioFilter(Version: Cardinal);
begin
  LifecycleLock.Acquire;
  try
    if Registry <> nil then Exit;
    ConfigureMVEditorCallback(Version);
    HostVersion := Version;
    TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
    try Registry := TMVContextRegistry.Create;
    except
      TTextRendererSkiaRuntime.Release;
      raise;
    end;
  finally LifecycleLock.Release; end;
end;

procedure FinalizeMVStudioFilter;
begin
  LifecycleLock.Acquire;
  try
    if Registry = nil then Exit;
    FreeAndNil(Registry);
    TTextRendererSkiaRuntime.Release;
  finally LifecycleLock.Release; end;
end;

function GetMVStudioFilterTable: PFILTER_PLUGIN_TABLE;
begin
  Result := GetPluginTable;
end;

function CopyMVStudioBackground(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect: string;
  out Frame: TMVBackgroundFrame): Boolean;
var EffectID: Int64; Location: TOBJECT_LAYER_FRAME;
begin
  Result := False;
  Frame := Default(TMVBackgroundFrame);
  if not ResolveMVBackgroundTarget(Edit, Obj, Effect, HostVersion, EffectID, Location) then Exit;
  LifecycleLock.Acquire;
  try
    if Registry <> nil then Result := Registry.CopyBackground(EffectID, Location, Frame);
  finally LifecycleLock.Release; end;
end;

initialization
  LifecycleLock := TCriticalSection.Create;
  SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
    'MVスタジオ', 'SYNC', '今どきのMV制作を支援するMVスタジオ',
    MVStudioProcVideo, nil);
  GetPluginTable^.Func_Create := CreateEffect;
  GetPluginTable^.Func_Destroy := DestroyEffect;
  RegisterMVSettings(OpenMVLegacyEditor, OpenMVEditor);
finalization
  LifecycleLock.Free;
end.
