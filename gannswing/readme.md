# Gann Swing chart indicator

## Introduction

This indicator allows for the plotting of Gann swings on the Metatrader chart. 

## How to use

These are the available options for the Gann Swing chart indicator:

### [filter] bars per swing

This adds a filter to the swing chart to not swing until a number of consecutive swings have been reached. In other words, if the filter is set to 2, the swing will only happen whenever two consecutive bars swing up. This has to be a number greater than 0.

### [filter] price

This adds another filter to the swing chart; price. The swing happens only if the price exceeds the high or low by the specified price quantity which must be 0.00 or greater.

### Swing on Previous break!

This feature is particularly useful when there is a bars per swing filter set. Whenever the price exceeds the previous swing, despite not having reached the bars per swing filter, the swing will still happen if this is set to true.

## Release history

| Version   | Summary                                                      |
| :--       | :--                                                          |
| 1.00      | initial development                                          |
| 1.01      | introduced price filtering                                   |
| 2.02      | introduced full bar and price filtering support              |

### Version 2.02 release notes

This is a major update over the previous version which introduces advanced filtering support to Gann Swing charting. These are the released features:

- Introduced price filtering support.
- Introduced bar filtering support.
- Corrected a bug which may occur at times due to incorrect initialization of swing chart data.
- Introduced "Swing on Previous break!".
- Removed the whole half outside bar swing type (see above for details).

### Version 1.00 release notes

This is the first version released to use of the Gann Swing indicator. It is an initial entry level development of Gann Swing Charting support for MT5.
 
## Disclaimer

**All work is provided ​“AS IS”. We make no warranties, express or implied, and hereby disclaim all implied warranties, including any warranty of merchantability and warranty of fitness for a particular purpose.**
