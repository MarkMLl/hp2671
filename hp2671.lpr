(* Lazarus+FPC 2.1.0+3.0.4 on Linux Lazarus+FPC 2.1.0+3.0.4 on Linux Lazarus+FP *)

program hp2671;

(* Assuming the presence of a Fenrir HP-IB interface which offers a subset of   *)
(* the Prologix commands, listen for HP2671 printer commands and data and       *)
(* generate text or .bmp output.                                MarkMLl.        *)

{$mode objfpc}{$H+}

uses
{$ifdef LCL }
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, hp2671Code,
  { you can add units after this }
{$endif LCL }
  ConsoleApp, LocateCdcAcmPort;

var
  Hp2671Port: string= '';
  scanPorts: boolean= false;
  i: integer;

{$R *.res}

begin
  for i := 1 to ParamCount() do
    if Pos('-ports', LowerCase(ParamStr(i))) <> 0 then
      scanPorts := true;
  for i := 1 to ParamCount() do
    if LowerCase(ParamStr(i)) = '--version' then begin
      DoVersion('Hp2671');
      Halt(0)
    end;
  Hp2671Port := FindFenrirPort(scanPorts);   (* Builds cached ports list        *)
  for i := 1 to ParamCount() do
    if LowerCase(ParamStr(i)) = '--help' then begin
      DoHelp(Hp2671Port, scanPorts);
      Halt(0)
    end;
{$ifdef LCL }
  if ParamCount() > 0 then  (* If GUI is available, activated by no parameter   *)
{$endif LCL }
    Halt(RunConsoleApp(Hp2671Port));

(* The objective here is to minimise the amount of manually-inserted text so as *)
(* to give the IDE the best chance of managing form names etc. automatically. I *)
(* try, I don't always succeed...                                               *)

// TODO : everything GUI-oriented including background thread etc.

{$ifdef LCL }
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(THp2671Form, Hp2671Form);
  Hp2671Form.DefaultPort := Hp2671Port;
  Application.Run;
{$endif LCL }
end.

