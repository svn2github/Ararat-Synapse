{==============================================================================|
| Project : Delphree - Synapse                                   | 002.001.000 |
|==============================================================================|
| Content: SNTP client                                                         |
|==============================================================================|
| The contents of this file are subject to the Mozilla Public License Ver. 1.1 |
| (the "License"); you may not use this file except in compliance with the     |
| License. You may obtain a copy of the License at http://www.mozilla.org/MPL/ |
|                                                                              |
| Software distributed under the License is distributed on an "AS IS" basis,   |
| WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for |
| the specific language governing rights and limitations under the License.    |
|==============================================================================|
| The Original Code is Synapse Delphi Library.                                 |
|==============================================================================|
| The Initial Developer of the Original Code is Lukas Gebauer (Czech Republic).|
| Portions created by Lukas Gebauer are Copyright (c)2000,2001.                |
| All Rights Reserved.                                                         |
|==============================================================================|
| Contributor(s):                                                              |
|   Patrick Chevalley                                                          |
|==============================================================================|
| History: see HISTORY.HTM from distribution package                           |
|          (Found at URL: http://www.ararat.cz/synapse/)                       |
|==============================================================================}

{$Q-}
{$WEAKPACKAGEUNIT ON}

unit SNTPsend;

interface

uses
  SysUtils,
  synsock, blcksock, SynaUtil;

const
  cNtpProtocol = 'ntp';

type
  PNtp = ^TNtp;
  TNtp = packed record
    mode: Byte;
    stratum: Byte;
    poll: Byte;
    Precision: Byte;
    RootDelay: Longint;
    RootDisperson: Longint;
    RefID: Longint;
    Ref1: Longint;
    Ref2: Longint;
    Org1: Longint;
    Org2: Longint;
    Rcv1: Longint;
    Rcv2: Longint;
    Xmit1: Longint;
    Xmit2: Longint;
  end;

  TSNTPSend = class(TObject)
  private
    FNTPReply: TNtp;
    FNTPTime: TDateTime;
    FNTPOffset: double;
    FNTPDelay: double;
    FMaxSyncDiff: double;
    FSyncTime: Boolean;
    FSntpHost: string;
    FTimeout: Integer;
    FSock: TUDPBlockSocket;
    FBuffer: string;
    FLi, FVn, Fmode : byte;
  public
    constructor Create;
    destructor Destroy; override;
    function DecodeTs(Nsec, Nfrac: Longint): TDateTime;
    procedure EncodeTs(dt: TDateTime; var Nsec, Nfrac: Longint);
    function GetSNTP: Boolean;
    function GetNTP: Boolean;
    function GetBroadcastNTP: Boolean;
  published
    property NTPReply: TNtp read FNTPReply;
    property NTPTime: TDateTime read FNTPTime;
    property NTPOffset: Double read FNTPOffset;
    property NTPDelay: Double read FNTPDelay;
    property MaxSyncDiff: double read FMaxSyncDiff write FMaxSyncDiff;
    property SyncTime: Boolean read FSyncTime write FSyncTime;
    property SntpHost: string read FSntpHost write FSntpHost;
    property Timeout: Integer read FTimeout write FTimeout;
    property Sock: TUDPBlockSocket read FSock;
  end;

implementation

constructor TSNTPSend.Create;
begin
  inherited Create;
  FSock := TUDPBlockSocket.Create;
  FSock.CreateSocket;
  FTimeout := 5000;
  FSntpHost := cLocalhost;
  FMaxSyncDiff := 3600;
  FSyncTime := False;
end;

destructor TSNTPSend.Destroy;
begin
  FSock.Free;
  inherited Destroy;
end;

function TSNTPSend.DecodeTs(Nsec, Nfrac: Longint): TDateTime;
const
  maxi = 4294967295.0;
var
  d, d1: Double;
begin
  Nsec := synsock.htonl(Nsec);
  Nfrac := synsock.htonl(Nfrac);
  d := Nsec;
  if d < 0 then
    d := maxi + d + 1;
  d1 := Nfrac;
  if d1 < 0 then
    d1 := maxi + d1 + 1;
  d1 := d1 / maxi;
  d1 := Trunc(d1 * 10000) / 10000;
  Result := (d + d1) / 86400;
  Result := Result + 2;
end;

procedure TSNTPSend.EncodeTs(dt: TDateTime; var Nsec, Nfrac: Longint);
const
  maxi = 4294967295.0;
  maxilongint = 2147483647;
var
  d, d1: Double;
begin
  d  := (dt - 2) * 86400;
  d1 := frac(d);
  d  := trunc(d);
  if d>maxilongint then
     d := d - maxi - 1;
  d1 := Trunc(d1 * 10000) / 10000;
  d1 := d1 * maxi;
  if d1>maxilongint then
     d1 := d1 - maxi - 1;
  Nsec:=trunc(d);
  Nfrac:=trunc(d1);
  Nsec := synsock.htonl(Nsec);
  Nfrac := synsock.htonl(Nfrac);
end;

function TSNTPSend.GetBroadcastNTP: Boolean;
var
  NtpPtr: PNtp;
  x: Integer;
begin
  Result := False;
  FSock.Bind('0.0.0.0', cNtpProtocol);
  FBuffer := FSock.RecvPacket(FTimeout);
  if FSock.LastError = 0 then
  begin
    x := Length(FBuffer);
    if (SntpHost = '0.0.0.0') or (FSock.GetRemoteSinIP = SntpHost) then
      if x >= SizeOf(NTPReply) then
      begin
        NtpPtr := Pointer(FBuffer);
        FNTPReply := NtpPtr^;
        FNTPTime := DecodeTs(NTPReply.Xmit1, NTPReply.Xmit2);
        if FSyncTime and ((abs(FNTPTime - GetUTTime) * 86400) <= FMaxSyncDiff) then
          SetUTTime(FNTPTime);
        Result := True;
      end;
  end;
end;

function TSNTPSend.GetSNTP: Boolean;
var
  q: TNtp;
  NtpPtr: PNtp;
  x: Integer;
begin
  Result := False;
  FSock.Connect(sntphost, cNtpProtocol);
  FillChar(q, SizeOf(q), 0);
  q.mode := $1B;
  FSock.SendBuffer(@q, SizeOf(q));
  FBuffer := FSock.RecvPacket(FTimeout);
  if FSock.LastError = 0 then
  begin
    x := Length(FBuffer);
    if x >= SizeOf(NTPReply) then
    begin
      NtpPtr := Pointer(FBuffer);
      FNTPReply := NtpPtr^;
      FNTPTime := DecodeTs(NTPReply.Xmit1, NTPReply.Xmit2);
      if FSyncTime and ((abs(FNTPTime - GetUTTime) * 86400) <= FMaxSyncDiff) then
        SetUTTime(FNTPTime);
      Result := True;
    end;
  end;
end;

function TSNTPSend.GetNTP: Boolean;
var
  q: TNtp;
  NtpPtr: PNtp;
  x: Integer;
  t1, t2, t3, t4 : TDateTime;
begin
  Result := False;
  FSock.Connect(sntphost, cNtpProtocol);
  FillChar(q, SizeOf(q), 0);
  q.mode := $1B;
  t1 := GetUTTime;
  EncodeTs(t1,q.org1,q.org2);
  FSock.SendBuffer(@q, SizeOf(q));
  FBuffer := FSock.RecvPacket(FTimeout);
  if FSock.LastError = 0 then
  begin
    x := Length(FBuffer);
    t4 := GetUTTime;
    if x >= SizeOf(NTPReply) then
    begin
      NtpPtr := Pointer(FBuffer);
      FNTPReply := NtpPtr^;
      FLi := (NTPReply.mode and $C0) shr 6;
      FVn := (NTPReply.mode and $38) shr 3;
      Fmode := NTPReply.mode and $07;
      if (Fli < 3) and (Fmode = 4) and
         (NTPReply.stratum >= 1) and (NTPReply.stratum <= 15) and
         (NTPReply.Rcv1 <> 0) and (NTPReply.Xmit1 <> 0)
         then begin
           t2 := DecodeTs(NTPReply.Rcv1, NTPReply.Rcv2);
           t3 := DecodeTs(NTPReply.Xmit1, NTPReply.Xmit2);
           FNTPDelay := (T4 - T1) - (T2 - T3);
           FNTPTime := t3 + FNTPDelay / 2;
           FNTPOffset := (((T2 - T1) + (T3 - T4)) / 2) * 86400;
           FNTPDelay := FNTPDelay * 86400;
           if FSyncTime and ((abs(FNTPTime - t1) * 86400) <= FMaxSyncDiff) then
             SetUTTime(FNTPTime);
           Result := True;
           end
         else result:=false;
    end;
  end;
end;

end.
