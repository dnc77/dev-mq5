# dev-mq5
This repository hosts a subset of MQL 5 tools which can be used for trading purposes using Metatrader 5. 

**All work is provided ​“AS IS”. We make no other warranties, express or implied, and hereby disclaim all implied warranties, including any warranty of merchantability and warranty of fitness for a particular purpose.**

These are the tools available in this repository:

## gannswing

This is just a basic Gann Swing indicator for Gann Swing charting. It just needs to be dragged on to the chart and it will draw the swing chart overlayed on top of the pricing candles/bars.
For more information refer to the readme on under `gannswing`.

## Price Export

Price export is an expert advisor which aims to export prices periodically to a file. Files are stored in `MQL5\Files`.
The filename used will contain the symbol name followed by the time period. For example, if this is running on an `AUDUSD` chart and the 5 minute time frame has been selected for exporting, you will have a file `MQL5\Files\PriceExport-AUDUSD.a_M5.csv` provided the name of the symbol is `AUDUSD.a` in your platform.

To export multiple timeframe, this advisor should only be active in one timeframe at a time. There will be the option to choose which timeframes to export before the export kicks off just after it is added to the chart window. Do not attempt to add this EA to multiple chart windows of the same symbol as that is not how this EA works and one chart window per symbol is enough.

This tool is very safe to use. In case of any issues or difficulties, do not hesitate to reach out. This is still in beta phase.

### Usage input parameters:
#### Date Format
The date format string is represented by a numeral and a letter to represent the number of characters to represent that part of the date.
For example: `4Y` represents 4 digits for the year component of the date period.

Currently there is only one date format option. The format currently in use is `Y4M2D2H2M2S2AP_SEP`. Let's break it down:

- Y4 - four digits for the year.
- M2 - two digits for the month.
- D2 - two digits for day.
- H2 - two digits for hour.
- M2 - two digits for minutes.
- S2 - two digits for seconds.
- AP - An AM/PM designator making this a 12 hour time.
- SEP - indicates that there is a separator between each item.

Best not to get too bogged down in this detail and just put it to use and see what it produces.

#### Past candles
Price export by default will get 200 candles of each timeframe selected from the current time moving backwards.
If a file already exists for that time frame, it will continue writing where it left off.
If there is not enough candles to reach the last entry in the file from the current time, then a gap record will be inserted.

#### Show gap record
Following on from previously, if a gap record is not desired, turn this to false. By default it's true.

#### Update frequency
This allows the definition of an update frequency in minutes.

#### Export ??? data
By default the price export tool is not set to export anything. Here one can choose the time frames to export.

### Known limitations:
1. There is only so much candles that can be downloaded in one go at this stage.

