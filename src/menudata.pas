{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>. }

{ Menu contents.  The whole menu tree lives here as data so that the UI and the
  command layer can be tested without a terminal. }
unit menudata;
{$mode objfpc}{$H+}

interface

uses menutree;

function BuildMenuTree: TMenuTree;

implementation

var
  B: TMenuTree;

procedure A(d: Integer; const s: string);
begin
  B.Add(d, s);
end;

procedure FormatMenu(d: Integer);
begin
  A(d, 'Fixed|Fixed number of decimal places (x.xx)');
  A(d, 'Sci|Exponential format (x.xxE+xx)');
  A(d, 'Currency|Currency format ($x,xxx.xx)');
  A(d, ',|Comma format (x,xxx.xx)');
  A(d, 'General|Standard format (x.xx or x.xxExx)');
  A(d, '+/-|Horizontal bar graph format (+++ or ---)');
  A(d, 'Percent|Percent format (x.xx%)');
  A(d, 'Date|Date and Time formats (all types)');
  A(d + 1, '1|DD-MMM-YY');
  A(d + 1, '2|DD-MMM');
  A(d + 1, '3|MMM-YY');
  A(d + 1, '4|Full International date format');
  A(d + 1, '5|Partial International date format');
  A(d + 1, 'Time|Time formats');
  A(d + 2, '1|HH:MM:SS AM/PM');
  A(d + 2, '2|HH:MM AM/PM');
  A(d + 2, '3|Full International time format');
  A(d + 2, '4|Partial International time format');
  A(d, 'Text|Display the formula in the cell, not its value');
  A(d, 'Hidden|Do not display the contents of the cell');
end;

procedure LabelMenu(d: Integer);
begin
  A(d, 'Left|Left-align labels');
  A(d, 'Right|Right-align labels');
  A(d, 'Center|Center labels');
end;

procedure PrintMenu(d: Integer);
begin
  A(d, 'Range|Specify a print range');
  A(d, 'Line|Advance paper one line');
  A(d, 'Page|Advance paper to top of next page');
  A(d, 'Options|Specify headers, footers, margins, borders, setup string');
  A(d + 1, 'Header|Create a header');
  A(d + 1, 'Footer|Create a footer');
  A(d + 1, 'Margins|Change margins');
  A(d + 2, 'Left|Set left margin');
  A(d + 2, 'Right|Set right margin');
  A(d + 2, 'Top|Set top margin');
  A(d + 2, 'Bottom|Set bottom margin');
  A(d + 1, 'Borders|Print specified columns or rows on each page');
  A(d + 2, 'Columns|Specify border columns');
  A(d + 2, 'Rows|Specify border rows');
  A(d + 1, 'Setup|Enter a printer setup string');
  A(d + 1, 'Pg-Length|Set the number of lines per page');
  A(d + 1, 'Other|Specify how to print the data');
  A(d + 2, 'As-Displayed|Print the range as it appears on the screen');
  A(d + 2, 'Cell-Formulas|Print each cell''s contents, one per line');
  A(d + 2, 'Formatted|Print headers, footers and page breaks');
  A(d + 2, 'Unformatted|Do not print headers, footers or page breaks');
  A(d + 1, 'Quit|Return to the previous menu');
  A(d, 'Clear|Reset some or all print options');
  A(d + 1, 'All|Cancel all print settings');
  A(d + 1, 'Range|Cancel the print range');
  A(d + 1, 'Borders|Cancel border columns and rows');
  A(d + 1, 'Format|Restore default margins, page length and setup');
  A(d, 'Align|Tell the program the paper is at the top of a page');
  A(d, 'Go|Print the specified range');
  A(d, 'Quit|Return to READY mode');
end;

procedure DataRangeMenu(d: Integer);
var
  c: Char;
begin
  for c := 'A' to 'F' do
    A(d, c + '|Specify the ' + c + ' data range');
end;

procedure BuildMenus;
var
  c: Char;
begin


  { ---- Worksheet ---- }
  A(1, 'Worksheet');
  A(2, 'Global|Set worksheet-wide options');
  A(3, 'Format|Set the global cell display format');
  FormatMenu(4);
  A(3, 'Label-Prefix|Set the global label alignment');
  LabelMenu(4);
  A(3, 'Column-Width|Set the width for all columns');
  A(3, 'Recalculation|Set recalculation order and method');
  A(4, 'Natural|Recalculate cells that others depend on first');
  A(4, 'Columnwise|Recalculate column by column');
  A(4, 'Rowwise|Recalculate row by row');
  A(4, 'Automatic|Recalculate every time entries change');
  A(4, 'Manual|Recalculate only when F9 (CALC) is pressed');
  A(4, 'Iteration|Specify the number of recalculation passes');
  A(3, 'Protection|Turn worksheet protection on or off');
  A(4, 'Enable|Turn worksheet protection on');
  A(4, 'Disable|Turn worksheet protection off');
  A(3, 'Default|Set default printer, directory and other options');
  A(4, 'Printer|Specify printer interface and default settings');
  A(4, 'Directory|Specify the default directory');
  A(4, 'Status|Display the current default settings');
  A(4, 'Update|Save the current default settings');
  A(4, 'Other|International, Help, Clock, Undo, Beep');
  A(4, 'Quit|Return to READY mode');
  A(3, 'Zero|Display or suppress zero values');
  A(4, 'No|Display zero values normally');
  A(4, 'Yes|Do not display zero values');
  A(2, 'Insert|Insert blank columns or rows');
  A(3, 'Column|Insert blank columns to the left of the cell pointer');
  A(3, 'Row|Insert blank rows above the cell pointer');
  A(2, 'Delete|Delete entire columns or rows');
  A(3, 'Column|Delete columns');
  A(3, 'Row|Delete rows');
  A(2, 'Column|Set or reset the width of columns');
  A(3, 'Set-Width|Specify the width of the current column');
  A(3, 'Reset-Width|Return the current column to the global width');
  A(3, 'Hide|Hide a range of columns');
  A(3, 'Display|Redisplay a range of hidden columns');
  A(2, 'Erase|Erase the entire worksheet from memory');
  A(3, 'No|Do not erase the worksheet; return to READY mode');
  A(3, 'Yes|Erase the entire worksheet and reset all settings');
  A(2, 'Titles|Freeze rows and columns as titles');
  A(3, 'Both|Freeze all rows above and columns to the left of the cell pointer');
  A(3, 'Horizontal|Freeze all rows above the cell pointer');
  A(3, 'Vertical|Freeze all columns to the left of the cell pointer');
  A(3, 'Clear|Unfreeze all title rows and columns');
  A(2, 'Window|Split the screen into two windows');
  A(3, 'Horizontal|Split the screen horizontally at the current row');
  A(3, 'Vertical|Split the screen vertically at the current column');
  A(3, 'Sync|Synchronize scrolling in the two windows');
  A(3, 'Unsync|Scroll the two windows independently');
  A(3, 'Clear|Return to a single full-screen window');
  A(2, 'Status|Display the current global settings');
  A(2, 'Page|Insert a page-break row above the cell pointer');
  A(2, 'Learn|Record keystrokes as a macro in a worksheet range');
  A(3, 'Range|Specify the range where keystrokes are recorded');
  A(3, 'Cancel|Forget the learn range');
  A(3, 'Erase|Erase the contents of the learn range');

  { ---- Range ---- }
  A(1, 'Range');
  A(2, 'Format|Set the display format of a range');
  FormatMenu(3);
  A(3, 'Reset|Return the range to the global format');
  A(2, 'Label|Set label alignment for a range');
  LabelMenu(3);
  A(2, 'Erase|Erase a cell or range of cells');
  A(2, 'Name|Create, delete or modify range names');
  A(3, 'Create|Create or modify a range name');
  A(3, 'Delete|Delete a range name');
  A(3, 'Labels|Create range names from adjacent labels');
  A(4, 'Right|Name the cell to the right of each label');
  A(4, 'Down|Name the cell below each label');
  A(4, 'Left|Name the cell to the left of each label');
  A(4, 'Up|Name the cell above each label');
  A(3, 'Reset|Delete all range names');
  A(3, 'Table|Create a table of range names in the worksheet');
  A(2, 'Justify|Adjust a long label to fit a specified range');
  A(2, 'Prot|Prevent changes to a range when protection is on');
  A(2, 'Unprot|Allow changes to a range when protection is on');
  A(2, 'Input|Restrict the cell pointer to unprotected cells in a range');
  A(2, 'Value|Copy a range, converting formulas to values');
  A(2, 'Trans|Copy a range, switching columns and rows');

  { ---- Copy / Move ---- }
  A(1, 'Copy|Copy a cell or range of cells');
  A(1, 'Move|Move a cell or range of cells');

  { ---- File ---- }
  A(1, 'File');
  A(2, 'Retrieve|Erase the worksheet and display a file from disk');
  A(2, 'Save|Store the entire worksheet in a file on disk');
  A(2, 'Combine|Incorporate part or all of a file into the worksheet');
  for c := 'C' to 'E' do
  begin
    case c of
      'C': A(3, 'Copy|Copy data from a file over the current data');
      'D': A(3, 'Add|Add values from a file to values in the worksheet');
      'E': A(3, 'Subtract|Subtract values in a file from the worksheet');
    end;
    A(4, 'Entire-File|Combine the entire file');
    A(4, 'Named/Specified-Range|Combine a named or specified range');
  end;
  A(2, 'Xtract|Save part of the worksheet in a file');
  A(3, 'Formulas|Save data in the range as formulas');
  A(3, 'Values|Save data in the range as values');
  A(2, 'Erase|Erase a file from disk');
  A(3, 'Worksheet|Erase a worksheet file');
  A(3, 'Print|Erase a print file');
  A(3, 'Graph|Erase a graph file');
  A(3, 'Other|Erase any other file');
  A(2, 'List|Display the names of files in the current directory');
  A(3, 'Worksheet|List worksheet files');
  A(3, 'Print|List print files');
  A(3, 'Graph|List graph files');
  A(3, 'Other|List all files');
  A(2, 'Import|Read text or numbers from a text file');
  A(3, 'Text|Import each line as a long label');
  A(3, 'Numbers|Import numbers as values and text as labels');
  A(2, 'Directory|Display and change the current directory');

  { ---- Print ---- }
  A(1, 'Print');
  A(2, 'Printer|Send output directly to a printer');
  PrintMenu(3);
  A(2, 'File|Send output to a text file');
  PrintMenu(3);

  { ---- Graph ---- }
  A(1, 'Graph');
  A(2, 'Type|Select the type of graph');
  A(3, 'Line|Line graph');
  A(3, 'Bar|Bar graph');
  A(3, 'XY|XY graph');
  A(3, 'Stack-Bar|Stacked bar graph');
  A(3, 'Pie|Pie chart');
  A(2, 'X|Specify the X-axis data range');
  DataRangeMenu(2);
  A(2, 'Reset|Cancel graph settings');
  A(3, 'Graph|Cancel all graph settings');
  A(3, 'X|Cancel the X data range');
  DataRangeMenu(3);
  A(3, 'Quit|Return to the previous menu');
  A(2, 'View|Display the current graph');
  A(2, 'Save|Save the graph in a file for printing');
  A(2, 'Options|Set legends, titles, grid, scale and other options');
  A(3, 'Legend|Create legends for data ranges');
  DataRangeMenu(4);
  A(4, 'Range|Specify a range of legends');
  A(3, 'Format|Set lines and/or symbols for data ranges');
  A(4, 'Graph|Apply to all data ranges');
  DataRangeMenu(4);
  A(4, 'Quit|Return to the previous menu');
  A(3, 'Titles|Create graph titles');
  A(4, 'First|Enter the first line of the graph title');
  A(4, 'Second|Enter the second line of the graph title');
  A(4, 'X-Axis|Enter the X-axis title');
  A(4, 'Y-Axis|Enter the Y-axis title');
  A(3, 'Grid|Draw grid lines');
  A(4, 'Horizontal|Draw horizontal grid lines');
  A(4, 'Vertical|Draw vertical grid lines');
  A(4, 'Both|Draw both horizontal and vertical grid lines');
  A(4, 'Clear|Remove grid lines');
  A(3, 'Scale|Set axis scaling');
  A(4, 'Y-Scale|Set scaling for the Y axis');
  A(4, 'X-Scale|Set scaling for the X axis');
  A(4, 'Skip|Display every nth label on the X axis');
  A(3, 'Color|Display the graph in color');
  A(3, 'B&W|Display the graph in black and white');
  A(3, 'Data-Labels|Label data points with worksheet values');
  A(4, 'A|Label points in the A range');
  A(4, 'B|Label points in the B range');
  A(4, 'C|Label points in the C range');
  A(4, 'D|Label points in the D range');
  A(4, 'E|Label points in the E range');
  A(4, 'F|Label points in the F range');
  A(4, 'Group|Label all data ranges');
  A(4, 'Quit|Return to the previous menu');
  A(3, 'Quit|Return to the previous menu');
  A(2, 'Name|Create, use or delete named graphs');
  A(3, 'Use|Make a named graph current');
  A(3, 'Create|Name the current graph');
  A(3, 'Delete|Delete a named graph');
  A(3, 'Reset|Delete all named graphs');
  A(2, 'Quit|Return to READY mode');

  { ---- Data ---- }
  A(1, 'Data');
  A(2, 'Fill|Fill a range with a sequence of values');
  A(2, 'Table|Create a table of values for one or two variables');
  A(3, '1|Create a table using one input cell');
  A(3, '2|Create a table using two input cells');
  A(3, 'Reset|Cancel table settings');
  A(2, 'Sort|Sort database records');
  A(3, 'Data-Range|Specify the range to sort');
  A(3, 'Primary-Key|Specify the primary sort key');
  A(3, 'Secondary-Key|Specify the secondary sort key');
  A(3, 'Reset|Cancel sort settings');
  A(3, 'Go|Sort the data');
  A(3, 'Quit|Return to READY mode');
  A(2, 'Query|Find or edit records that match given criteria');
  A(3, 'Input|Specify the input range');
  A(3, 'Criteria|Specify the criteria range');
  A(3, 'Output|Specify the output range');
  A(3, 'Find|Highlight each matching record');
  A(3, 'Extract|Copy matching records to the output range');
  A(3, 'Unique|Copy unique matching records to the output range');
  A(3, 'Delete|Delete matching records from the input range');
  A(3, 'Reset|Cancel query settings');
  A(3, 'Quit|Return to READY mode');
  A(2, 'Distribution|Create a frequency distribution');
  A(2, 'Matrix|Invert or multiply matrices');
  A(3, 'Invert|Invert a matrix');
  A(3, 'Multiply|Multiply two matrices');
  A(2, 'Regression|Calculate a linear regression');
  A(3, 'X-Range|Specify the independent variables');
  A(3, 'Y-Range|Specify the dependent variable');
  A(3, 'Output-Range|Specify where to put the results');
  A(3, 'Intercept|Compute or force the intercept to zero');
  A(4, 'Compute|Calculate the intercept');
  A(4, 'Zero|Force the intercept to zero');
  A(3, 'Reset|Cancel regression settings');
  A(3, 'Go|Calculate the regression');
  A(3, 'Quit|Return to READY mode');
  A(2, 'Parse|Convert a column of long labels into separate cells');
  A(3, 'Format-Line|Create or edit a format line');
  A(3, 'Input-Column|Specify the column of labels to parse');
  A(3, 'Output-Range|Specify where to put the parsed data');
  A(3, 'Reset|Cancel parse settings');
  A(3, 'Go|Parse the labels');
  A(3, 'Quit|Return to READY mode');

  { ---- System / Quit ---- }
  A(1, 'System|Leave the program temporarily and use the operating system');
  A(1, 'Quit|End the session');
  A(2, 'No|Do not end the session; return to READY mode');
  A(2, 'Yes|End the session (Answer Yes only if you have saved your work)');
end;

function BuildMenuTree: TMenuTree;
begin
  B := TMenuTree.Create;
  BuildMenus;
  Result := B;
end;

end.
