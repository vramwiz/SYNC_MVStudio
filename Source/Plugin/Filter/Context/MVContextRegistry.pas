unit MVContextRegistry;

// SDKのエフェクト寿命と参照カウントを結び付け、描画中の対象を破棄しない。
interface

uses System.SyncObjs, System.Generics.Collections, MVFilterContext, MVBackgroundFrame, AviUtl2FilterTypes;

type
  TMVContextRegistry = class
  private
    FLock: TCriticalSection; // 辞書の取得・生成・削除を保護する。
    FItems: TDictionary<Int64, IMVFilterContext>; // ホスト起動内で一意なエフェクトIDをキーにする。
  public
    // 空の登録表を作成する。
    constructor Create;
    // 登録参照を解放する。描画側の取得参照は独立して生存できる。
    destructor Destroy; override;
    // 対象専用の参照を返す。未登録時だけ遅延生成する。
    function Acquire(EffectID: Int64): IMVFilterContext;
    // SDKの破棄通知で登録参照を解放する。呼出中の参照は破棄しない。
    procedure Remove(EffectID: Int64);
    // IDを優先し、旧本体では配置区間が一意に一致する場合だけ背景を複写する。
    function CopyBackground(EffectID: Int64; const Location: TOBJECT_LAYER_FRAME;
      out Frame: TMVBackgroundFrame): Boolean;
  end;

implementation

constructor TMVContextRegistry.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FItems := TDictionary<Int64, IMVFilterContext>.Create;
end;

destructor TMVContextRegistry.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited;
end;

function TMVContextRegistry.Acquire(EffectID: Int64): IMVFilterContext;
begin
  FLock.Acquire;
  try
    if not FItems.TryGetValue(EffectID, Result) then
    begin
      Result := TMVFilterContext.Create;
      FItems.Add(EffectID, Result);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TMVContextRegistry.Remove(EffectID: Int64);
begin
  FLock.Acquire;
  try
    FItems.Remove(EffectID);
  finally
    FLock.Release;
  end;
end;

function TMVContextRegistry.CopyBackground(EffectID: Int64; const Location: TOBJECT_LAYER_FRAME;
  out Frame: TMVBackgroundFrame): Boolean;
var Context, Match: IMVFilterContext;
begin
  Result := False;
  Frame := Default(TMVBackgroundFrame);
  FLock.Acquire;
  try
    if EffectID <> 0 then
    begin
      if not FItems.TryGetValue(EffectID, Match) then Exit;
    end
    else
      for Context in FItems.Values do
        if Context.MatchesLocation(Location) then
        begin
          // 別シーンや複製等で一致が曖昧なら他オブジェクトの画像を流用しない。
          if Match <> nil then Exit;
          Match := Context;
        end;
    if Match <> nil then
      if EffectID <> 0 then Result := Match.CopyBackground(Frame)
      else Result := Match.CopyBackgroundAt(Location, Frame);
  finally FLock.Release; end;
end;

end.
