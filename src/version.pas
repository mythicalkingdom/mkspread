{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors  (GPL-3.0-or-later; see COPYING) }
unit version;
{$mode objfpc}{$H+}

interface

const
  ProgramName = 'mkspread';
  ProgramVersion = '0.10.0';

{ the text printed by --version }
function VersionText: string;

implementation

function VersionText: string;
begin
  Result := ProgramName + ' ' + ProgramVersion + LineEnding +
    'Copyright (C) 2026 The mkspread authors' + LineEnding +
    'License GPLv3+: GNU GPL version 3 or later <https://www.gnu.org/licenses/gpl-3.0.html>' + LineEnding +
    'This is free software: you are free to change and redistribute it.' + LineEnding +
    'There is NO WARRANTY, to the extent permitted by law.' + LineEnding +
    'A terminal spreadsheet with the menus, keystrokes and file formats of the' + LineEnding +
    'classic DOS spreadsheets.  Not connected with the makers of any other product.';
end;

end.
