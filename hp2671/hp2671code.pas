(* Lazarus+FPC 2.1.0+3.0.4 on Linux Lazarus+FPC 2.1.0+3.0.4 on Linux Lazarus+FP *)

unit hp2671Code;


{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ExtCtrls, StdCtrls;

type

  { THp2671Form }

  THp2671Form = class(TForm)
    Image1: TImage;
    MainMenu1: TMainMenu;
    Memo1: TMemo;
    PageControl1: TPageControl;
    StatusBar1: TStatusBar;
    TabSheet1: TTabSheet;
  private

  public
    DefaultPort: string;
  end;

var
  Hp2671Form: THp2671Form;


implementation

{$R *.lfm}

end.

