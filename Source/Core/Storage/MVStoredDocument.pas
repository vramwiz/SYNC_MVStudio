unit MVStoredDocument;

// JSON文書を改行・エスケープに依存しない単行データへ包み、ホスト項目へ安全に渡す。
interface

uses MVDocument;

// UTF-8 JSONをMV1:付きBase64へ変換する。ホスト項目の保存上限超過は例外にする。
function EncodeMVStoredDocument(const Document: TMVDocument): string;
// 保存形式を検証して復元する。失敗時はDocumentを変更せず、Errorへ理由を返す。
function TryDecodeMVStoredDocument(const Data: string; var Document: TMVDocument; out Error: string): Boolean;

implementation

uses System.SysUtils, System.NetEncoding, MVDocumentJson;

function EncodeMVStoredDocument(const Document: TMVDocument): string;
begin
  Result := 'MV1:' + TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(EncodeMVDocument(Document)));
  Result := StringReplace(StringReplace(Result, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
  if Length(Result) > MV_MAX_DATA_LENGTH then
    raise EArgumentException.Create('拡張データが保存上限を超えています。文字数を減らしてください。');
end;

function TryDecodeMVStoredDocument(const Data: string; var Document: TMVDocument; out Error: string): Boolean;
var Payload: string; I: Integer;
begin
  Result := False;
  Error := '';
  try
    if not Data.StartsWith('MV1:') or (Length(Data) > MV_MAX_DATA_LENGTH) then
      raise EArgumentException.Create('未対応または上限を超えた拡張データです。');
    Payload := Copy(Data, 5, MaxInt);
    if (Payload = '') or (Length(Payload) mod 4 <> 0) then
      raise EArgumentException.Create('拡張データの長さが不正です。');
    for I := 1 to Length(Payload) do
      if not CharInSet(Payload[I], ['A'..'Z', 'a'..'z', '0'..'9', '+', '/', '=']) then
        raise EArgumentException.Create('拡張データの文字が不正です。');
    Result := TryDecodeMVDocument(TEncoding.UTF8.GetString(TNetEncoding.Base64.DecodeStringToBytes(Payload)),
      Document, Error);
  except
    on E: Exception do Error := E.Message;
  end;
end;

end.
