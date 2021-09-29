(* Lazarus+FPC 2.1.0+3.0.4 on Linux Lazarus+FPC 2.1.0+3.0.4 on Linux Lazarus+FP *)

unit ConsoleApp;

(* This is the greater part of a console program which accepts data from an HP  *)
(* instrument and emulates a printer to a sufficient extent that it can output  *)
(* a screendump in text or graphics format as appropriate.      MarkMLl.        *)

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

(* GNU-mandated support for --version and --help.
*)
procedure DoVersion(const projName: string);

(* GNU-mandated support for --version and --help.
*)
procedure DoHelp(const portName: string; portScan: boolean= false);

(* Main function, return 0 if no error.
*)
function RunConsoleApp(portName: string): integer;


implementation

uses
  StrUtils, LocateCdcAcmPort, IniFilesAbout, Serial, BaseUnix, Termio;

const
  graphicsTimeout= 5000;
  textTimeout= 1000;
  defaultWidth= 576;                    (* 576 for HP1630, must be multiple of 32 *)

var
  debugLevel: integer= 0;
{$ifdef ENDIAN_LITTLE }                 (* Probably other things to fix as well *)
  background: longword= $00ffffff;
{$else                }
  background: longword= $ffffff00;
{$endif ENDIAN_LITTLE }
  foreground: longword= $00000000;
  outline: boolean= false;


(* GNU-mandated support for --version and --help.
*)
procedure DoVersion(const projName: string);

begin
  WriteLn();
  WriteLn(projName + ' ' + AboutText());
  WriteLn()
end { DoVersion } ;


(* GNU-mandated support for --version and --help.
*)
procedure DoHelp(const portName: string; portScan: boolean= false);

begin
  WriteLn();
  WriteLn('Usage: hp2671 [OPTIONS]... [DEVICE]');
  WriteLn();
  WriteLn('Accept HP-IB printer output, emulating an HP2671G.');
  WriteLn();
  WriteLn('DEVICE is the name of a serial device such as /dev/ttyACM0.');
  WriteLn();
  WriteLn('If there is no explicit option or device an interactive GUI screen will');
  WriteLn('be presented. Supported options are as below:');
  WriteLn();
  WriteLn('  --version      Version information.');
  WriteLn();
  WriteLn('  --help         This help text, also reports default device.');
  WriteLn();
  WriteLn('  --portScan     Extends --help output with device list (might be slow).');
  WriteLn();
  WriteLn('  -g --green     Graphical capture is green-on-black.');
  WriteLn();
  WriteLn('  -o --outline   Single-pixel outline around graphical capture.');
  WriteLn();
{$ifdef LCL }
  WriteLn('  -              Dummy option, ignored.');
{$else      }
  WriteLn('  - --           Dummy options, ignored.');
{$endif LCL }
  WriteLn();
  WriteLn('Exit status:');
  WriteLn();
  WriteLn(' 0  Normal termination');
  WriteLn(' 1  Cannot parse device identifier');
  WriteLn(' 2  Named device cannot be opened');
  WriteLn(' 3  Named device is unresponsive');
  WriteLn(' 4  Data access error');
  WriteLn(' 5  Data format error');
  WriteLn(' 9  Bad command-line parameters');
  WriteLn();
  if portScan then
    DumpCachedPorts;
  WriteLn('Default port: ', portName);
  WriteLn()
end { DoHelp } ;


(* Receive text, mostly ASCII with the possibility of minor enhancements and
  character graphics. Save the result as a .txt file and return the name and
  size.
*)
function processText(handle: TSerialHandle; const alreadyReceived: string): string;

var
  txtFile: text;
  i, lineCount: integer;
  received: byte;
  seenFF: boolean;


  (* Parse an individual character. The output is buffered line-by-line so that
    if the start of enhanced text is encountered we can convert an immediately-
    preceding space into an underscore. Assume that the FF at the end of a page
    has been preceded by CRLF.
  *)
  procedure oneChar(b: byte);

  type
    TescState= (escNone, escSeen, esc_amp, esc_d);

  const
    line: string= '';
    escState: TescState= escNone;
    enhance: boolean= false;

  var
    info: Stat;

  begin
    case b of
      $00..
      $0b:      ;
      $0c:      begin
                  seenFF := true;
                  enhance := false;
                  if debugLevel > 3 then
                    WriteLn(stdErr, '# Terminating on FF');
                  Flush(txtFile);
                  if FPFStat(txtFile, info) then
                    result += ', ' + IntToStr(info.st_size) + ' bytes (' + IntToStr(lineCount) + ' lines)'
                  else
                    result += ', ' + IntToStr(lineCount) + ' lines'
                end;
      $0d:      begin
                  WriteLn(txtFile, TrimRight(line));
                  lineCount += 1;
                  line := '';
                  enhance := false;
                  if debugLevel = 9 then
                    WriteLn(stdErr, '# Got CR, cancel enhancement')
                end;
      $0e..
      $1a:      ;
      $1b:      escState := escSeen;
      $1c..
      $1f:      ;
      Ord(' '): begin
                  if enhance then
                    line += '_'
                  else
                    line += ' ';
                  if debugLevel = 9 then
                    Write(stdErr, ' ')
                end;
      Ord('&'): case escState of
                  escSeen: escState := esc_amp;
                  escNone: line += '&'
                otherwise
                  escState := escNone
                end;
      Ord('d'): case escState of
                  esc_amp: escState := esc_d;
                  escNone: line += 'd'
                otherwise
                  escState := escNone
                end;
      Ord('D'): case escState of
                  esc_d:   begin
                             enhance := true;
                             escState := escNone;
                             if debugLevel = 9 then
                               WriteLn(stdErr, '# <esc>&dD Enhancement on')
                           end;
                  escNone: line += 'D'
                otherwise
                  escState := escNone
                end;
      Ord('@'): case escState of
                  esc_d:   begin
                             enhance := false;
                             escState := escNone;
                             if debugLevel = 9 then
                               WriteLn(stdErr, '# <esc>&d@ Enhancement off')
                           end;
                  escNone: line += 'D'
                otherwise
                  escState := escNone
                end;

// None of these characters (i.e. u, ^ etc.) can be entered from the instrument
// front panel, but they could appear on the screen as the result of an HP-IB
// command or execution of an inverse assembler etc.

//      $25:      line += '';             (* N/A as don't care, shown as %        *)
//      $5e:      line += '↑';            (* Up-arrow shown as ^                  *)
//      $75:      line += 'µ';            (* Micro shown as u                     *)
//      $76:      line += '↓';            (* Down-arrow shown as v                *)
//      $7c:      line += '↕'             (* Up/down arrow shown as |             *)
    otherwise
      line += Chr(b);
      if debugLevel = 9 then
        Write(stdErr, Chr(b))
    end
  end { oneChar } ;


begin
  result := AnsiReplaceStr(IsoNow() + '.txt', ' ', '_');
  AssignFile(txtFile, result);
{$I- }
  Rewrite(txtFile);
  if IoResult <> 0 then
    exit('');
{$I+ }
  try
    for i := 1 to Length(alreadyReceived) do
      oneChar(byte(alreadyReceived[i]));
    seenFF := false;
    lineCount := 0;

(* Output is mostly ASCII with the portential for a small amount of UTF-8. A    *)
(* byte-order mark is not applicable to this combination.                       *)

    repeat
      if seenFF or (SerReadTimeout(handle, received, 1, textTimeout) <> 1) then
        break;
      oneChar(received)
    until false;
  finally
    Close(txtFile)
  end
end { processText } ;


(* The compiler doen't like this being on the stack, I think it's got alignment *)
(* issues.                                                                      *)

type
  TBmpHeader= packed record
                       sig: array[0..1] of char;
                       filesize: longword;
                       reserved: array[0..1] of word;
                       offset: longword;
                       DIBHdrSize: longword;
                       width: longword;
                       height: longint;
                       planes: word;
                       bpp: word;
                       compression: longword;
                       imageSize: longword;
                       xPpm: longword;
                       yPpm: longword;
                       colours: longword;
                       important: longword;
                       colourMap: array[0..1] of longword
                     end;

var
  bmpHeader: TBmpHeader;


(* Receive bitmapped graphics. Save the result as a .bmp file and return the
  name and size.
*)
function processGraphics(handle: TSerialHandle; const alreadyReceived: string): string;

(* Specimen monochrome data from https://itnext.io/bits-to-bitmaps-a-simple-walkthrough-of-bmp-image-format-765dc6857393?gi=101270a2f1c

0000 42 4D              Signature
0002 00 00 00 00        Filesize
0006 00 00              Reserved
0008 00 00              Reserved
000a 3E 00 00 00        PixelArray offset

000e 28 00 00 00        DIB header size
0012 05 00 00 00        Image width
0016 05 00 00 00        Image height (+ve, so bottom-to-top)
001a 01 00              Image planes
001c 01 00              Image bits-per-pixel
001e 00 00 00 00        Compression
0022 00 00 00 00        Image size
0026 00 00 00 00        X pixels per meter
002a 00 00 00 00        Y pixels per meter
002e 00 00 00 00        Colours in colour table
0032 00 00 00 00        Important colour count

0036 FF FF FF 00        Colour definition 0
003a 00 00 00 00        Colour definition 1

003e 20 00 00 00        Bottom row of 5
0042 20 00 00 00
0046 20 00 00 00
004a F8 00 00 00        Black row, MSB is left, 5 pixels per row
004e 20 00 00 00        Top row of 5
                                                                                *)
(* This is about the simplest definition I've found. It might be possible to    *)
(* omit the DIB, but that would be undesirable since there would be no way to   *)
(* specify that the data was presented top-line-first.                          *)

var
  bmpFile: file;
  rowsWritten: integer= 0;
  colsWritten: integer= 0;
  colsPerRow: integer = 0;
  topMarginWidth: integer= -1;
  topMarginHeight: integer= 8;
  printerbuffer: string;
  number, padding, paddingL, paddingR, i, j: integer;
  letter: char;
  b: byte;


  (* Read a number comprising a sequence of ASCII digits using -1 as the default
    if there isn't one, followed by a single letter.
  *)
  function getNumberAndLetter(handle: TSerialHandle; out number: integer; out letter: char): boolean;

    var
      digits: string= '';


    function readOneChar(handle: TSerialHandle): char;

      var
        b: byte;

    begin
      result := #$00;
      if SerReadTimeout(handle, b, graphicsTimeout) <> 1 then (* Formfeed at end of page   *)
        b := $0c;
      result := Chr(b)
    end { readOneChar } ;


  begin
    number := -1;
    letter := #$00;
    result := false;
    letter := readOneChar(handle);      (* Might be formfeed representing end of job *)
    while letter in ['0'..'9'] do begin
      digits += letter;
      letter := readOneChar(handle)
    end;
    if digits <> '' then
      number := StrToInt(digits);
    result := letter > #$00
  end { getNumberAndLetter } ;


begin
  result := '';
  Assert(SizeOf(TBmpHeader) = $003e, 'Header size wrong, got ' + IntToStr(SizeOf(TBmpHeader)) + ' should be 62');
  FillByte(bmpHeader, SizeOf(bmpHeader), 0);
  with bmpHeader do begin
    sig[0] := ' ';
    sig[1] := ' ';
    offset := SizeOf(TBmpHeader);
    DIBHdrSize := $0028;
    planes := 1;
    bpp := 1;
    colourMap[0] := background;
    colourMap[1] := foreground
  end;

(* Create the file and write the header to reserve space. It will be rewritten  *)
(* when the file is closed.                                                     *)

  result := AnsiReplaceStr(IsoNow() + '.bmp', ' ', '_');
  AssignFile(bmpFile, result);
{$I- }
  Rewrite(bmpFile, 1);
  if IoResult <> 0 then
    exit('');
{$I+ }
  try
    BlockWrite(bmpFile, bmpHeader, SizeOf(bmpHeader));
    printerBuffer := alreadyReceived;

(* Expect a block of graphical data to loop either like this (from the 1630G):

1B 2A 62 37 32 57 00 00 - 00 00 00 00 00 00 00 00    .*b72W..  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00

  Or like this (from the 54501A:

1B 26 6C 36 36 50 1B 2A - 72 36 34 30 53 1B 2A 72    .&l66P.*  r640S.*r
41 1B 2A 62 37 34 57 08 - 00 00 00 00 00 00 00 00    A.*b74W.  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00 00 00 00 00 00 00 00 - 00 00 00 00 00 00 00 00    ........  ........
00
                                                                                *)
(* <esc>*rA and <esc>*rB enable/disable graphics mode, since we know that we    *)
(* expecting graphics we can ignore them. <esc>&l-P probably sets a page length *)
(* and <esc>*r-S probably sets a page width. <esc>*b-W- is the raster command   *)
(* itself, the byte count between the b and the W appears to be in text form.   *)
(* Unlike Epson printers, one byte of raster data is eight horizontal pixels    *)
(* rather than a small portion of eight rows.                                   *)

(* When we enter this procedure we already should have an escape and two other  *)
(* characters. These will be followed by an optional numeric parameter and a    *)
(* letter.                                                                      *)

    colsPerRow := defaultWidth;
    colsWritten := 0;
    rowsWritten := 0;
    padding := 0;
    repeat
      if (Length(printerBuffer) < 3) or (printerBuffer[1] <> #$1b) then begin
        if debugLevel > 0 then
           WriteLn(stdErr, '# Pre-fill short (' + IntToStr(rowsWritten) + ', ' + IntToStr(colsWritten) + ')');
        exit('')
      end;
      number := -2;
      letter := '~';
      if not getNumberAndLetter(handle, number, letter) then begin
        if debugLevel > 0 then
           WriteLn(stdErr, '# No number+letter (' + IntToStr(number) + ', ' + letter + ')');
        exit('')
      end;
      if letter = #$0c then begin       (* This is not an error condition       *)
        if debugLevel > 0 then
           WriteLn(stdErr, '# Normal end condition');
        break
      end;
      if debugLevel > 6 then
         WriteLn(stdErr, '# Parse ' + Copy(printerBuffer, 2, 2));
      case Copy(printerBuffer, 2, 2) of
        '&l': if debugLevel > 3 then
                WriteLn(stdErr, '# <esc>&l- Explicit line count ' + IntToStr(number));
        '*r': case letter of
                'A': if debugLevel > 3 then
                       WriteLn(stdErr, '# <esc>*rA Explicit start graphics');
                'B': if debugLevel > 3 then
                       WriteLn(stdErr, '# <esc>*rB Explicit end graphics');
                'S': begin
                       while number mod 32 <> 0 do
                         number += 1;
                       if debugLevel > 3 then
                         WriteLn(stdErr, '# <esc>*rS Explicit line width ' + IntToStr(number));
                       if rowsWritten = 0 then
                         colsPerRow := number
                       else
                         if debugLevel > 3 then
                           WriteLn(stdErr, '# Already printing, ignored')
                     end
              otherwise
                if debugLevel > 0 then
                   WriteLn(stdErr, '# Got unexpected ' + letter);
                exit('')
              end;
        '*b': begin
                colsWritten := 0;
                if topMarginWidth < 0 then begin

(* If this is the first graphics block that we are outputting then either       *)
(* assume the default width or use one that we've been told explicitly, work    *)
(* out how much padding we're going to need to make the output into a valid     *)
(* .bmp file, and output a top margin to make things look better.               *)

                  padding := (8 + colsPerRow) - (number * 8);   (* Pixels       *)
                  while ((number * 8) + padding) mod 32 <> 0 do
                    padding += 1;
                  topMarginWidth := (number * 8) + padding;
                  topMarginHeight := padding div 4;
                  if topMarginHeight < 8 then
                    topMarginHeight := 8;
                  if debugLevel > 4 then
                    WriteLn(stdErr, '# Padding ' + IntToStr(padding) + ' over ' +
                                        IntToStr(number * 8) + ' for ' +
                                        IntToStr((number * 8) + padding) + ' pixels total');
                  if debugLevel > 4 then
                    WriteLn(stdErr, '# Top margin ' + IntToStr(topMarginHeight) + ' x ' + IntToStr(topMarginWidth));
                  if debugLevel > 4 then
                    WriteLn(stdErr, '# First graphics line ' + IntToStr(number * 8) + ' + ' + IntToStr(padding) + ' pixels');
                  for i := 1 to topMarginHeight do begin (* 8 lines of margin at the top      *)
                    for j := 1 to topMarginWidth div 8 do begin (* Each byte fulfills 8 pixels *)
                      if not outline then
                        b := $00
                      else
                        if i = 1 then
                          b := $ff
                        else
                          if j = 1 then
                            b := $80
                          else
                            if j = topMarginWidth div 8 then
                              b := $01
                            else
                              b := $00;
                      BlockWrite(bmpFile, b, 1)
                    end;
                    rowsWritten += 1
                  end
                end;
                paddingL := padding div 2;
                paddingR := padding - paddingL;
                if (paddingL > 0) and (debugLevel > 5) then
                  WriteLn(stdErr, '# Padding left ' + IntToStr(paddingL) + ' pixels');
                while paddingL > 0 do begin
                  if (paddingL = padding div 2) and outline then
                    b := $80
                  else
                    b := $00;
                  BlockWrite(bmpFile, b, 1);
                  colsWritten += 8;
                  paddingL -= 8
                end;
                if debugLevel > 5 then
                  WriteLn(stdErr, '# <esc>*b-W Raster data ' + IntToStr(number * 8) + ' pixels');
                while (number > 0) and (letter = 'W') do begin
                  if SerReadTimeout(handle, b, 1, graphicsTimeout) <> 1 then begin
                    if debugLevel > 0 then
                      WriteLn(stdErr, '# Raster read failed at ' + IntToStr(number) + ' bytes');
                    exit('')
                  end;
                  if debugLevel = 9 then
                    Write(stdErr, HexStr(b, 2) + ' ');
                  BlockWrite(bmpFile, b, 1);
                  colsWritten += 8;
                  number -= 1
                end;
// TODO : Doesn't check actual length of current line of pixels.
                if (paddingR > 0) and (debugLevel > 5) then
                  WriteLn(stdErr, '# Padding right ' + IntToStr(paddingR) + ' pixels');
                while paddingR > 0 do begin
                  if (paddingR = 8) and outline then
                    b := $01
                  else
                    b := $00;
                  BlockWrite(bmpFile, b, 1);
                  colsWritten += 8;
                  paddingR -= 8
                end;
                rowsWritten += 1;
                if debugLevel = 9 then begin
                  WriteLn(stdErr);
                  WriteLn('# Written ' + IntToStr(rowsWritten) + ' rows, ' + IntToStr(colsWritten) + ' cols')
                end
              end
      otherwise
      end;
      SetLength(printerBuffer, 3);

(* Expect the next escape sequence, or a formfeed, or under certain conditions  *)
(* a timeout.                                                                   *)

      if SerReadTimeout(handle, b, 1, graphicsTimeout) = 1 then begin
        if b = $0c then
          break;
        printerBuffer[1] := Chr(b)
      end else begin
        if debugLevel > 0 then
           WriteLn(stdErr, '# Post-fill 1 fail');
        exit('')
      end;

(* We've started another command sequence i.e. are not at the end of the data   *)
(* stream, so not receiving more data is an error condition.                    *)

      if SerReadTimeout(handle, b, 1, graphicsTimeout) <> 1 then begin
        if debugLevel > 0 then
           WriteLn(stdErr, '# Post-fill 2 fail');
        exit('')
      end;
      printerBuffer[2] := Chr(b);
      if SerReadTimeout(handle, b, 1, graphicsTimeout) <> 1 then begin
        if debugLevel > 0 then
           WriteLn(stdErr, '# Post-fill 3 fail');
        exit('')
      end;
      printerBuffer[3] := Chr(b)
    until false
  finally
    if topMarginWidth > 0 then begin    (* Also write a bottom margin           *)
      if debugLevel > 4 then
        WriteLn(stdErr, '# Bottom margin ' + IntToStr(topMarginHeight) + ' x ' + IntToStr(topMarginWidth));
      for i := 1 to topMarginHeight do begin (* 8 lines of margin at the bottom *)
        for j := 1 to topMarginWidth div 8 do begin (* Each byte fulfills 8 pixels *)
          if not outline then
            b := $00
          else
            if i = topMarginHeight then
              b := $ff
            else
              if j = 1 then
                b := $80
              else
                if j = topMarginWidth div 8 then
                  b := $01
                else
                  b := $00;
          BlockWrite(bmpFile, b, 1)
        end;
        rowsWritten += 1
      end
    end;
    with bmpHeader do begin
      if result <> '' then begin
        sig[0] := 'B';
        sig[1] := 'M'
      end;
      if topMarginWidth <= 0 then
        width := colsPerRow
      else
        width := topMarginWidth;
      height := -rowsWritten
    end;
    Seek(bmpFile, 0);
    BlockWrite(bmpFile, bmpHeader, SizeOf(bmpHeader));
    Close(bmpFile)
  end
end { processGraphics } ;


(* Wait until there is a gap in the data to make sure we don't try to treat data
  as a sync byte;
*)
procedure waitDataGap(port: TSerialHandle);

var
  scratch: byte;

begin
  while SerReadTimeout(port, scratch, textTimeout) > 0 do (* Originally 10 mSec timeout *)
    Sleep(1)
end { waitDataGap } ;


(* Main function, return 0 if no error.
*)
function RunConsoleApp(portName: string): integer;

var
  portHandle: TSerialHandle= InvalidSerialHandle;
  scratch: string;
  i: integer;
  ports: TStringList;


  function serReadLn(handle: TSerialHandle): string;

  var
    buffer: array[0..127] of byte;
    i: integer;

  begin
    SetLength(result, SerReadTimeout(handle, buffer, SizeOf(buffer), 500));
// TODO : This doesn't actually insist on a valid line-end, but is only used for local responses.
    for i := 1 to Length(result) do
      result[i] := Char(buffer[i - 1])
  end { SerReadLn } ;


  function readThreeBytes(handle: TSerialHandle): integer;

  var
    b1, b2, b3: byte;


    function avail(handle: TSerialHandle): integer; inline;

    begin
      if fpIoctl(handle, FIONREAD, @result) <> 0 then
        result := -1
    end { avail } ;


  begin
    result := -1;
    while avail(handle) < 3 do
      Sleep(100);
    if SerRead(handle, b1, 1) <> 1 then
      exit;
    if SerRead(handle, b2, 1) <> 1 then
      exit;
    if SerRead(handle, b3, 1) <> 1 then
      exit;
    result := b1 + (b2 shl 8) + (b3 shl 16)
  end { readThreeBytes } ;


begin
  result := 3;                          (* Unresponsive is a good default       *)
  i := 1;
  while i <= ParamCount() do begin
    case ParamStr(i) of
      '-',                              (* Placeholder only                     *)
      '--',                             (* This doesn't work with GUI/LCL       *)
      '--ports',                        (* Used as --help modifier only         *)
      '--portscan',
      '--portsScan':  ;
      '--debug':      if i = ParamCount() then begin
                        WriteLn(stderr, 'Debug level has no parameter');
                        exit(9)         (* Missing debug level                  *)
                      end else begin
                        i += 1;
                        try
                          debugLevel := Abs(StrToInt(ParamStr(i)));
                        except
                          WriteLn(stderr, 'Debug level not numeric');
                          exit(9)       (* Bad debug level                      *)
                        end
                      end;
      '-g',
      '--green':      begin
                        background := $00000000;
{$ifdef ENDIAN_LITTLE }                 (* Probably other things to fix as well *)
                        foreground := $0000ff00
{$else                }
                        foreground := $00ff0000
{$endif ENDIAN_LITTLE }
                      end;
      '-o',
      '--outline':    outline := true
    otherwise
      if i <> ParamCount() then begin
        WriteLn(stderr, 'Bad device name');
        exit(1)                         (* Bad device name                      *)
      end else
        portName := ParamStr(i)
    end;
    i += 1
  end;

(* In principle, if the debugging level were appropriate I could list the auto- *)
(* detected serial ports here. In practice telling the user anything useful     *)
(* would be quite a lot of work, since the standard code doesn't actually save  *)
(* manufacturer and driver names as it's scanning the /sys tree trying to find  *)
(* a satisfactory match.                                                        *)

  if debugLevel > 1 then begin
    ports := ListPorts;
    try
      for i := 0 to ports.Count - 1 do
        WriteLn(stderr, '# ' + ports[i])
    finally
      FreeAndNil(ports)
    end
  end;

// OK, so I did a bit but it doesn't show very much that's useful. What I'm
// inclined to do next is hang a secondary stringlist onto each line that
// represents a port, and then as properties (e.g. kernel driver) are being
// checked update indexed lines which can be subsequently walked.

  portHandle := SerOpen(portName);
  {$ifdef UNIX }
  if portHandle > 0 then
    if fpIoctl(portHandle, TIOCEXCL, nil) <> 0 then begin (* Mandatory lock,    *)
      SerClose(portHandle);             (* unlike flock() (if it even works in  *)
      portHandle := -1                  (* this context) or a lock file as used *)
    end;                                (* by various gettys etc.               *)
  {$endif UNIX }
  if portHandle = InvalidSerialHandle then begin
    WriteLn(stderr, 'Device ' + portName + ' cannot be opened');
    exit(2)                             (* Cannot be opened                     *)
  end;
  if debugLevel > 0 then
    WriteLn(stderr, '# Using port ', portName);
  try
    SerSetParams(portHandle, 115200, 8, NoneParity, 1, []);
    waitDataGap(portHandle);
    if debugLevel > 0 then
      WriteLn(stderr, '# Getting interface version... ');
    scratch := '++ver' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    scratch := Trim(serReadLn(portHandle));
    if Pos('Prologix', scratch) <= 0 then begin
      WriteLn('No response from interface, terminating');
      Halt(3)
    end;
    WriteLn(scratch);

(* Send the sequence of commands needed to tell the HP-IB interface to accept   *)
(* output (assumed to be printer-compatible) irrespective of address. These     *)
(* don't return OK or anything useful, so issue another command each time and   *)
(* and look for something sensible in the result.                               *)

    if debugLevel > 0 then
      Write(stderr, '# ++savecfg 0... ');
    scratch := '++savecfg 0' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    Sleep(100);
    scratch := '++ver' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    if Pos('Prologix', serReadLn(portHandle)) <= 0 then begin
      WriteLn('Initialisation failure, terminating');
      Halt(3)
    end else
      if debugLevel > 0 then
        WriteLn(stderr, 'OK');
    if debugLevel > 0 then
      Write(stderr, '# ++mode 0... ');
    scratch := '++mode 0' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    Sleep(100);
    scratch := '++mode' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    if Pos('0', serReadLn(portHandle)) <= 0 then begin
      WriteLn('Initialisation failure, terminating');
      Halt(3)
    end else
      if debugLevel > 0 then
        WriteLn(stderr, 'OK');
    if debugLevel > 0 then
      Write(stderr, '# ++lon 1... ');
    scratch := '++lon 1' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    Sleep(100);
    scratch := '++lon' + #$0d;
    SerWrite(portHandle, scratch[1], Length(scratch));
    if Pos('1', serReadLn(portHandle)) <= 0 then begin
      WriteLn('Initialisation failure, terminating');
      Halt(3)
    end else
      if debugLevel > 0 then
        WriteLn(stderr, 'OK');

(* Wait for printer data. This is tested with text and graphical data emitted   *)
(* by an HP1630G logic analyzer and an HP54501A oscilloscope, it is not         *)
(* intended to be a complete printer emulation.                                 *)
(*                                                                              *)
(* At this stage, we are interested in knowing whether the device is sending    *)
(* text (with a small amount of enhancement) or a graphical bitmap. Text will   *)
(* usually start with an ASCII character (7-bit plus possibly high-range block  *)
(* graphics) but it could potentially start with <esc>&d which turns on/off     *)
(* underline or some other enhancement. Graphics will normally start with       *)
(* <esc>*b or <esc>&l which is are graphics commands. Both types of data are    *)
(* terminated by a formfeed, although strictly that is optional so a timeout    *)
(* should be treated as an alternative; assume that a formfeed indicates a page *)
(* end and as such might be followed by additional data indicating more pages.  *)

    repeat
      WriteLn('Waiting for printer data, ^C to terminate... ');
      i := readThreeBytes(portHandle);
      if i < 0 then
        Halt(4);
      SetLength(scratch, 3);
      scratch[1] := char(i and $ff);
      scratch[2] := char((i shr 8) and $ff);
      scratch[3] := char((i shr 16) and $ff);
      case scratch[1] of
        #$00..
        #$1a: begin
                Write('text: ');
                scratch := processText(portHandle, scratch)
              end;
        #$1b: if (scratch[1] = '&') and (scratch[2] = 'd') then begin
                Write('text: ');
                scratch := processText(portHandle, scratch)
              end else begin
                Write('graphics: ');
                scratch := processGraphics(portHandle, scratch)
              end
      otherwise
        Write('text: ');
        scratch := processText(portHandle, scratch)
      end;
      WriteLn(scratch)                  (* Name and size of saved file          *)
    until false
  finally
    SerClose(portHandle)
  end;
  result := 0
end { RunConsoleApp };


initialization
  Assert(defaultWidth mod 32 = 0, 'Width must be multiple of 32')
end.

