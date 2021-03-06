{---------------------------------------------------------------------}
{                                                                     }
{ Firebird database server profiler tool (FBProfiler)                 }
{                                                                     }
{ Copyright (c) 2013-2015 Bel Air Informatique (www.belair-info.fr)   }
{ Copyright (c) 2013-2015 Serguei Tarassov (www.arbinada.com)         }
{                                                                     }
{ FBProfiler uses IBX For Lazarus components (Firebird Express)       }
{ FBProfiler was firstly released for public domain                   }
{ on October 31 of 2015 (Halloween) so any donations are welcome.     }
{                                                                     }
{ The contents of this file are subject to the InterBase              }
{ Public License Version 1.0 (the "License"); you may not             }
{ use this file except in compliance with the License. You            }
{ may obtain a copy of the License at                                 }
{ http://www.firebirdsql.org/en/interbase-public-license/             }
{ Software distributed under the License is distributed on            }
{ an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either              }
{ express or implied. See the License for the specific language       }
{ governing rights and limitations under the License.                 }
{                                                                     }
{---------------------------------------------------------------------}

unit TraceFiles;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TraceControl;

const
  TraceConfExt: string = '.trc';
  TracePackExt: string = '.trz';

type

  { TTraceConfFile }

  TTraceConfFile = class
  public
    class function GetDlgFilter: string;
    class procedure Load(const FileName: string; Config: TTraceConfig);
    class procedure Save(const FileName: string; const Config: TTraceConfig);
  end;

  { TTraceFile }

  TTraceFile = class
  public
    class function GetDlgFilter: string;
    class function MakePackName(const SourceFile: string): string;
    class function Restore(const PackFileName: string): string;
    class procedure Save(const SourcePath, SourceFile, TargetDir, PackageName: string);
  end;

implementation

uses
  XMlPropStorage,
  Zipper;

const
  TraceConf_RootNodePath = 'FBProfiler/TraceConf';

{ TTraceConfFile }

class function TTraceConfFile.GetDlgFilter: string;
begin
  Result := Format('Trace configuration file (*%0:s)|*%0:s', [TraceConfExt]);
end;

class procedure TTraceConfFile.Load(const FileName: string; Config: TTraceConfig);
var
  i: integer;
  Storage: TXMLPropStorage;
begin
  Storage := TXMLPropStorage.Create(nil);
  try
    Storage.FileName := FileName;
    Storage.RootNodePath := TraceConf_RootNodePath;
    Config.HostName := Storage.ReadString('HostName', Config.HostName);
    Config.Port := Storage.ReadInteger('Port', Config.Port);
    Config.Version := Storage.ReadInteger('Version', Config.Version);
    Config.UserName := Storage.ReadString('UserName', Config.UserName);
    Config.DatabaseFilter := Storage.ReadString('DatabaseFilter', Config.DatabaseFilter);
    for i := 0 to Config.Params.Count - 1 do
      Config.Params[i].Value :=
        Storage.ReadString(Config.Params[i].Name, Config.Params[i].Value);
  finally
    Storage.FreeStorage;
  end;
end;

class procedure TTraceConfFile.Save(const FileName: string;
  const Config: TTraceConfig);
var
  i: integer;
  Storage: TXMLPropStorage;
begin
  Storage := TXMLPropStorage.Create(nil);
  try
    Storage.FileName := FileName;
    Storage.RootNodePath := TraceConf_RootNodePath;
    Storage.WriteString('HostName', Config.HostName);
    Storage.WriteInteger('Port', Config.Port);
    Storage.WriteInteger('Version', Config.Version);
    Storage.WriteString('UserName', Config.UserName);
    Storage.WriteString('DatabaseFilter', Config.DatabaseFilter);
    for i := 0 to Config.Params.Count - 1 do
      Storage.WriteString(Config.Params[i].Name, Config.Params[i].Value);
    Storage.Save;
  finally
    Storage.FreeStorage;
  end;
end;

{ TTraceFile }

class function TTraceFile.GetDlgFilter: string;
begin
  Result := Format('Trace files package (*%0:s)|*%0:s', [TracePackExt]);
end;

class function TTraceFile.MakePackName(const SourceFile: string): string;
begin
  Result := Format('%s_%s%s',
    [ChangeFileExt(SourceFile, ''),
    FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now),
    TracePackExt]);
end;

class function TTraceFile.Restore(const PackFileName: string): string;
var
  UnZip: TUnZipper;
  i: integer;
begin
  Assert(SysUtils.FileExists(PackFileName),
    Format('Trace pack file not found: %s', [PackFileName]));
  Result := '';
  UnZip := TUnZipper.Create;
  try
    UnZip.FileName := PackFileName;
    UnZip.OutputPath := ExtractFileDir(PackFileName);
    UnZip.Examine;
    for i := 0 to UnZip.Entries.Count - 1 do
    begin
      if ExtractFileExt(UnZip.Entries[i].ArchiveFileName) = '.dbf' then
      begin
        Result := IncludeTrailingPathDelimiter(UnZip.OutputPath) +
          UnZip.Entries[i].ArchiveFileName;
        break;
      end;
    end;
    Assert(Trim(Result) <> '', Format('No data file was found in package: %s', [PackFileName]));
    UnZip.UnZipAllFiles;
  finally
    UnZip.Free;
  end;
end;

class procedure TTraceFile.Save(const SourcePath, SourceFile, TargetDir,
  PackageName: string);

  procedure AddFileToZip(Z: TZipper; const APath, AFileName: string);
  var
    FileName: string;
  begin
    FileName := IncludeTrailingPathDelimiter(APath) + AFileName;
    if SysUtils.FileExists(FileName) then
      Z.Entries.AddFileEntry(FileName, AFileName)
    else
      raise Exception.CreateFmt('Trace file not exists: %s', [FileName]);
  end;

var
  PackageFileName: string;
  Zip: TZipper;
begin
  if not DirectoryExists(TargetDir) then
    raise Exception.CreateFmt('Directory not exist: %s', [TargetDir]);
  if Pos(PathDelim, PackageName) <> 0 then
    raise Exception.Create('Package name contains invalid characters');
  PackageFileName := IncludeTrailingPathDelimiter(TargetDir) + PackageName;
  if ExtractFileExt(PackageFileName) <> TracePackExt then
    PackageFileName := PackageFileName + TracePackExt;
  if SysUtils.FileExists(PackageFileName) then
    SysUtils.DeleteFile(PackageFileName);
  if SysUtils.FileExists(PackageFileName) then
    raise Exception.CreateFmt('Cannot delete existing file %s', [PackageFileName]);
  Zip := TZipper.Create;
  try
    Zip.FileName := PackageFileName;
    AddFileToZip(Zip, SourcePath, SourceFile);
    AddFileToZip(Zip, SourcePath, ChangeFileExt(SourceFile, '.fpt'));
    Zip.ZipAllFiles;
  finally
    Zip.Free;
  end;
end;

end.
