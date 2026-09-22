unit MVFilterContext;

// 1エフェクトの設定キャッシュと描画領域を所有し、同一対象への並行評価を直列化する。
interface

uses System.SysUtils, System.SyncObjs, System.Skia, AviUtl2FilterTypes, MVDocument, MVLayout, MVFilterSettings,
  MVBackgroundFrame;

type
  IMVFilterContext = interface
    ['{5F24857A-B2CC-46D7-A5E4-31D2F90845B1}']
    // 呼出中の参照で寿命を確保し、入力画像を保持したまま歌詞を合成する。
    procedure Render(Video: PFILTER_PROC_VIDEO; const Settings: TMVSettings);
    // 最後に取得した歌詞合成前の画像を、呼出元だけが所有する配列へ複写する。
    function CopyBackground(out Frame: TMVBackgroundFrame): Boolean;
    // ID取得APIがない旧本体向けに、最後に描画した配置区間を照合する。
    function MatchesLocation(const Location: TOBJECT_LAYER_FRAME): Boolean;
    // 取得直前にも配置区間を照合し、描画更新との競合で別対象の画像を返さない。
    function CopyBackgroundAt(const Location: TOBJECT_LAYER_FRAME; out Frame: TMVBackgroundFrame): Boolean;
  end;

  TMVFilterContext = class(TInterfacedObject, IMVFilterContext)
  private
    FLock: TCriticalSection; // 同じ対象のキャッシュ・作業画像を保護する。
    FKey: string; // 最後に組版した設定。
    FDocument: TMVDocument; // FLock内でのみ変更する確定設定。
    FLayout: TMVLayout; // 設定変更時に作る文字画像。
    FPixels: TArray<TPIXEL_RGBA>; // この対象だけが再利用する入出力領域。
    FBackground: TMVBackgroundFrame; // 歌詞合成前の入力画像。描画用領域と共有しない。
    FLocation: TOBJECT_LAYER_FRAME; // この画像を取得したオブジェクトの配置区間。
    FRuntimeAcquired: Boolean; // 描画中にレジストリが終了してもSkiaの寿命を維持する。
  public
    // 空の対象を作成する。描画資源は最初の映像評価まで遅延する。
    constructor Create;
    // 取得済み描画資源を解放する。
    destructor Destroy; override;
    // 設定変更時だけ解析・組版し、失敗時はホスト画像を書き換えない。
    procedure Render(Video: PFILTER_PROC_VIDEO; const Settings: TMVSettings);
    // 内部ロック中に背景を深く複写する。未取得時は空画像とFalseを返す。
    function CopyBackground(out Frame: TMVBackgroundFrame): Boolean;
    // 描画履歴が存在し、配置区間が一致する場合だけTrueを返す。
    function MatchesLocation(const Location: TOBJECT_LAYER_FRAME): Boolean;
    // 配置照合と画像複写を同じロック区間で行う。
    function CopyBackgroundAt(const Location: TOBJECT_LAYER_FRAME; out Frame: TMVBackgroundFrame): Boolean;
  end;

implementation

uses System.Math, MVTextUnits, MVStoredDocument, MVPlacementDocument, MVRenderer,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap;

constructor TMVFilterContext.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  FRuntimeAcquired := True;
end;

destructor TMVFilterContext.Destroy;
begin
  FLayout.Free;
  if FRuntimeAcquired then TTextRendererSkiaRuntime.Release;
  FLock.Free;
  inherited;
end;

procedure TMVFilterContext.Render(Video: PFILTER_PROC_VIDEO; const Settings: TMVSettings);
var
  Candidate: TMVDocument;
  NewLayout: TMVLayout;
  Key, Error: string;
  Width, Height: Integer;
  X, Y: Double;
  Surface: ISkSurface;
begin
  if (Video = nil) or (Video^.Object_ = nil) or not Assigned(Video^.SetImageData) then Exit;
  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  // GetImageDataは対象画像サイズの領域へ書くため、推測したシーン寸法では呼ばない。
  FLock.Acquire;
  try
    FBackground.Width := 0;
    FBackground.Height := 0;
    if (Width <= 0) or (Height <= 0) or (Int64(Width) * Height > 16777216) then Exit;
    if Video^.Object_^.Time < 0 then Exit;
    // 空歌詞や不正設定でも入力背景は取得する。文字を合成した出力で上書きしない。
    if Assigned(Video^.GetImageData) then
    begin
      SetLength(FBackground.Pixels, Width * Height * 4);
      Video^.GetImageData(PPIXEL_RGBA(@FBackground.Pixels[0]));
      FBackground.Width := Width;
      FBackground.Height := Height;
      FLocation.Layer := Video^.Object_^.Layer;
      FLocation.StartFrame := Video^.Object_^.FrameS;
      FLocation.EndFrame := Video^.Object_^.FrameE;
    end;
    Key := MVSettingsKey(Settings);
    if (FLayout = nil) or (Key <> FKey) then
    begin
      if Settings.Extended and (Settings.Data <> '') then
      begin
        if not TryDecodeMVStoredDocument(Settings.Data, Candidate, Error) then Exit;
        ApplyMVHostDocument(Candidate, Settings.Document);
      end
      else
      begin
        Candidate := Settings.Document;
        SetMVText(Candidate, Candidate.Text);
        ValidateMVDocument(Candidate);
      end;
      NewLayout := TMVLayout.Create(Candidate);
      FLayout.Free;
      FLayout := NewLayout;
      FDocument := Candidate;
      FKey := Key;
    end;
    // 演出は保存書式の管理元に関係なく、毎フレームのホスト値を使う。
    // 演出パラメータの補間では文字画像を再生成しない。
    ApplyMVHostAnimation(FDocument, Settings.Document);
    if FDocument.Text = '' then Exit;
    if Length(FPixels) <> Width * Height then SetLength(FPixels, Width * Height);
    if FBackground.IsValid then Move(FBackground.Pixels[0], FPixels[0], Length(FBackground.Pixels))
    else FillChar(FPixels[0], Length(FPixels) * SizeOf(TPIXEL_RGBA), 0);
    Surface := TSkSurface.MakeRasterDirect(TSkImageInfo.Create(Width, Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul), @FPixels[0], Width * 4);
    if Surface = nil then Exit;
    X := Settings.X;
    Y := Settings.Y;
    if Settings.Extended and (Settings.Data <> '') then
    begin
      X := 0;
      Y := 0;
    end;
    if IsNan(X) or IsInfinite(X) or IsNan(Y) or IsInfinite(Y) then Exit;
    DrawMVDocument(Surface.Canvas, FDocument, FLayout, Width, Height, X, Y,
      Video^.Object_^.Time, Video^.Object_^.TimeTotal, Settings.EntranceTime, Settings.ExitTime);
    Surface := nil;
    Video^.SetImageData(@FPixels[0], Width, Height);
  finally
    FLock.Release;
  end;
end;

function TMVFilterContext.CopyBackground(out Frame: TMVBackgroundFrame): Boolean;
begin
  Frame := Default(TMVBackgroundFrame);
  FLock.Acquire;
  try
    Result := FBackground.IsValid;
    if Result then
    begin
      Frame.Width := FBackground.Width;
      Frame.Height := FBackground.Height;
      Frame.Pixels := Copy(FBackground.Pixels);
    end;
  finally FLock.Release; end;
end;

function TMVFilterContext.MatchesLocation(const Location: TOBJECT_LAYER_FRAME): Boolean;
begin
  FLock.Acquire;
  try
    Result := FBackground.IsValid and (FLocation.Layer = Location.Layer) and
      (FLocation.StartFrame = Location.StartFrame) and (FLocation.EndFrame = Location.EndFrame);
  finally FLock.Release; end;
end;

function TMVFilterContext.CopyBackgroundAt(const Location: TOBJECT_LAYER_FRAME;
  out Frame: TMVBackgroundFrame): Boolean;
begin
  Frame := Default(TMVBackgroundFrame);
  FLock.Acquire;
  try
    Result := MatchesLocation(Location) and CopyBackground(Frame);
  finally FLock.Release; end;
end;

end.
