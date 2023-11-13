/*
Date: 29 Sep 2023 21:35:26.114548507
File: gannswing.mq5

Copyright Notice
This document is protected by the GNU General Public License v3.0.

This allows for commercial use, modification, distribution, patent and private
use of this software only when the GNU General Public License v3.0 and this
copyright notice are both attached in their original form.

For developer and author protection, the GPL clearly explains that there is no
warranty for this free software and that any source code alterations are to be
shown clearly to identify the original author as well as any subsequent changes
made and by who.

For any questions or ideas, please contact:
github:  https://github(dot)com/dnc77
email:   dnc77(at)hotmail(dot)com
web:     http://www(dot)dnc77(dot)com

Copyright (C) 2023 Duncan Camilleri, All rights reserved.
End of Copyright Notice

Sign:    __GANNSWING_MQ5_CA35703CE56E61E77AFD55A158DA2B3B__
Purpose:    Draws gann swing chart overlayed on chart.

Version control
29 Sep 2023 Duncan Camilleri           Initial development
20 Oct 2023 Duncan Camilleri           Introducing price and bar filtering
11 Nov 2023 Duncan Camilleri           Finalized filtering support
13 Nov 2023 Duncan Camilleri           Added custom swing label
*/

#property description   "Gann Swing.\n"
                        "\n"
                        "Draws swing chart on MT5.\n"
#property copyright     "Copyright (C) 2023 Duncan Camilleri."
#property link          "http://www.dnc77.com"
#property version       "2.03"

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots 1

#property indicator_label1 "gannswing"
#property indicator_type1 DRAW_SECTION
#property indicator_color1 Blue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1

#property strict

// Inputs
input string iGannLabel = "gannswing[untitled]";   // Indicator label:
input int iBarFilter = 1;                          // [filter] bars per swing:
input double iPriceFilter = 0.000;                 // [filter] price:
input bool iSwingOnPrevBreak = false;              // Swing on break of prev.:

#define product         "gannswing"

//
// Structures.
//

// Swing type determines whether there is an up candle, down, out or in candle.
enum SwingType {
   stUnknown = 0x00,
   stUp = 0x01,
   stDown = 0x02,
   stIn = 0x03,
   stOut = 0x04
};

// Candle represents one single candle to be used to aid in drawing the swings.
struct Candle {
   double mOpen;
   double mHigh;
   double mLow;
   double mClose;
};

// Swing status tracker.
struct SwingStatus {
   int mBarCount;                                  // number of swings (-/+)
   int mLastDownSwing;                             // last downswing index
   int mLastUpSwing;                               // last upswing index
};

//
// Globals.
//
SwingStatus gStatus;                               // Tracks swing status
double gSwingPoints[];                             // swing prices
double gSwings[];                                  // swing type of each swing

//
// Init/Term.
//

int OnInit()
{
   // Deinitialize first.
   OnDeinit(0);
   printf("%s: initializing...", product);

   // Set index buffers.
   SetIndexBuffer(0, gSwingPoints, INDICATOR_DATA);
   SetIndexBuffer(1, gSwings, INDICATOR_DATA);

   // Define empty.
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   // Init globals.
   gStatus.mBarCount = 0;
   gStatus.mLastDownSwing = 0;
   gStatus.mLastUpSwing = 0;

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   printf("%s: deinitializing...", product);
   ArrayFree(gSwings);
   ArrayFree(gSwingPoints);
}

// 
// Calculation.
//
int OnCalculate(const int rates_total, const int prev_calculated,
   const datetime &time[],
   const double &open[], const double &high[],
   const double &low[], const double &close[],
   const long &tick_volume[], const long &volume[],
   const int &spread[])
{

   // Validate inputs!
   if (iBarFilter < 1) {
      Alert("Invalid filter - bars per swing. Please specify a positive integer!");
      return rates_total;
   }
   if (iPriceFilter < 0) {
      Alert("Invalid filter - price. "
         "Please specify a positive price or 0 for no filter!"
      );
      return rates_total;
   }

   // Set label.
   PlotIndexSetString(0, PLOT_LABEL, iGannLabel);

   // Go through each candle.
   for (int n = 0; n < rates_total; ++n) {
      gSwingPoints[n] = gSwings[n] = 0.0;

      // First candle ever!
      if (n == 0) {
         // Identify first swing.
         Candle current;
         getCandle(open, high, low, close, current, n);
         gSwings[0] = startSwing(current);
         if (doubleToSwing(gSwings[0] == stUp)) {
            // Force first swing
            gStatus.mBarCount = iBarFilter;
            if (0 == swingUp(high, n, -1, false)) {
               gSwingPoints[0] = high[0];
            } else {
               printf("%s: unexpected exception code 02.", product);
            }
         } else {
            // Force first swing
            gStatus.mBarCount = -iBarFilter;
            if (0 == swingDown(low, n, -1, false)) {
               gSwingPoints[0] = low[0];
            } else {
               printf("%s: unexpected exception code 03.", product);
            }
         }

         // Next.
         n++;
         gSwingPoints[n] = gSwings[n] = 0.0;
      }

      // Process candle at current index.
      if (!setCandleSwings(open, high, low, close, n)) {
         printf("%s: unexpected exception code 01.", product);
      }
   }
 
   // All candles processed but ignore the last 15 candles.
   return rates_total;
}

//
// Conversion functions.
//

// Convert a swing type to double.
double swingToDouble(SwingType st)
{
   return (double)(int)st;
}

// Convert double to a swing type.
SwingType doubleToSwing(double st)
{
   return (SwingType)(int)st;
}

//
// Reference count management and swing initialization
//

// Assigns swing to starting candle.
SwingType startSwing(const Candle& start)
{
   if (start.mOpen <= start.mClose) {
      return stUp;
   }

   return stDown;
}

// Performs a swing down using the low price at index idx.
// inputs:
//    low[]       : array of low prices to use for swing consideration
//    idx         : candle considered for a swing down
//    replAt      : replace at gSwingPoints index > -1 or when last down
//                   swing is higher than low at idx.
//    replPrev    : replace gSwingPoints at previous candle (idx - 1) if
//                   gSwingPoints != 0.0 at that index.
//    peek        : true to not actuate the swing but get the result index.
// returns:       index of overwritten swing point. -1 if none written.
int swingDown(const double& low[], int idx,
               int replAt, bool replPrev, bool peek = false)
{
   int barCount = gStatus.mBarCount;

   // If previous swing down broken when option enabled, automatically swing.
   if (iSwingOnPrevBreak) {
      double lastSwingPrice =
         gSwingPoints[gStatus.mLastDownSwing] - iPriceFilter;
      if (low[idx] < lastSwingPrice) {
         barCount = -iBarFilter;
      }
   }

   // Correct/update reference count.
   if (barCount > -iBarFilter) {
      if (barCount > 0) {
         // New down move.
         barCount = -1;
      } else {
         // Next down move.
         barCount--;
      }
   }

   // We update the actual bar count now if this is not a peek request.
   if (!peek) gStatus.mBarCount = barCount;

   // If limit not reached, no writes needed.
   if (barCount != -iBarFilter) {
      return -1;
   }

   // Changing direction from up to down.
   if (gStatus.mLastUpSwing > gStatus.mLastDownSwing) {
      // When changing directions, there will be no replacing. We do however
      // consider the previous candle.
      if (replPrev) {
         int idxPrev = idx - 1;
         if (gSwingPoints[idxPrev] == 0.0) {
            if (peek) return idxPrev;

            gSwingPoints[idxPrev] = low[idx];
            gStatus.mLastDownSwing = idxPrev;

            return idxPrev;
         }
      }

      // Otherwise apply to current candle if possible.
      if (gSwingPoints[idx] == 0.0) {
         if (peek) return idx;

         gSwingPoints[idx] = low[idx];
         gStatus.mLastDownSwing = idx;

         return idx;
      }

      // Could not update swing price.
      return -1;
   }

   // Resuming a down swing. Determine price.
   double price = low[idx];

   // If last swing is down and lower than the current candle low, use last.
   if (low[gStatus.mLastDownSwing] < low[idx]) {
      price = low[gStatus.mLastDownSwing];
   }

   // Resuming a down swing - write at replAt.
   if (replAt > -1 && replAt >= gStatus.mLastDownSwing) {
      bool write = (gSwingPoints[replAt] == 0.0 ||
         gSwingPoints[replAt] >= price
      );

      // Update swing point.
      if (write) {
         if (peek) return replAt;

         gSwingPoints[gStatus.mLastDownSwing] = 0.00;
         gSwingPoints[replAt] = price;
         gStatus.mLastDownSwing = replAt;

         // Done.
         return replAt;
      }
   }

   // If swing points at replAt not updated, maybe try previous candle.
   if (replPrev && idx > gStatus.mLastDownSwing) {
      int idxPrev = idx - 1;
      bool write = (gSwingPoints[idxPrev] == 0.0 ||
         gSwingPoints[idxPrev] > price
      );
      
      // Update swing point.
      if (write) {
         if (peek) return idxPrev;

         gSwingPoints[gStatus.mLastDownSwing] = 0.00;
         gSwingPoints[idxPrev] = price;
         gStatus.mLastDownSwing = idxPrev;

         // Done.
         return idxPrev;
      }
   }

   // If none of the cases above, can we write to current candle?
   if (gSwingPoints[idx] != 0.00) {
      return -1;
   }

   // Return if peek only.
   if (peek) return idx;

   // Write last down swing.
   gSwingPoints[gStatus.mLastDownSwing] = 0.00;
   gSwingPoints[idx] = price;
   gStatus.mLastDownSwing = idx;
   return idx;
}

// Performs a swing down using the low price at index idx.
// inputs:
//    high[]      : array of high prices to use for swing consideration
//    idx         : candle considered for a swing up
//    replAt      : replace at gSwingPoints index > -1 or when last up
//                   swing is lower than high at idx.
//    replPrev    : replace gSwingPoints at previous candle (idx - 1) if
//                   gSwingPoints != 0.0 at that index.
//    peek        : true to not actuate the swing but get the result index.
// returns:       index of overwritten swing point. -1 if none written.
int swingUp(const double& high[], int idx,
            int replAt, bool replPrev,
            bool peek = false)
{
   int barCount = gStatus.mBarCount;

   // If previous swing up broken, automatically swing.
   if (iSwingOnPrevBreak) {
      double lastSwingPrice =
         gSwingPoints[gStatus.mLastUpSwing] + iPriceFilter;
      if (high[idx] > lastSwingPrice) {
         barCount = iBarFilter;
      }
   }

   // Correct/update reference count.
   if (barCount < iBarFilter) {
      if (barCount < 0) {
         // New up move.
         barCount = 1;
      } else {
         // Next up move.
         barCount++;
      }
   }

   // We update the actual bar count now if this is not a peek request.
   if (!peek) gStatus.mBarCount = barCount;

   // If limit not reached, no writes needed.
   if (barCount != iBarFilter) {
      return -1;
   }

   // Changing direction from down to up.
   if (gStatus.mLastDownSwing > gStatus.mLastUpSwing) {
      // When changing directions, there will be no replacing. We do however
      // consider the previous candle.
      if (replPrev) {
         int idxPrev = idx - 1;
         if (gSwingPoints[idxPrev] == 0.0) {
            if (peek) return idxPrev;

            gSwingPoints[idxPrev] = high[idx];
            gStatus.mLastUpSwing = idxPrev;
            return idxPrev;
         }
      }

      // Otherwise apply to current candle if possible.
      if (gSwingPoints[idx] == 0.0) {
         if (peek) return idx;

         gSwingPoints[idx] = high[idx];
         gStatus.mLastUpSwing = idx;
         return idx;
      }

      // Could not update swing price.
      return -1;
   }

   // Resuming an up swing. Determine price.
   double price = high[idx];

   // If last swing is up and higher than the current candle high, use last.
   if (high[gStatus.mLastUpSwing] > high[idx]) {
      price = high[gStatus.mLastUpSwing];
   }

   // Resuming an up swing - write at replAt.
   if (replAt > -1 && replAt >= gStatus.mLastUpSwing) {
      bool write = (gSwingPoints[replAt] == 0.0 ||
         gSwingPoints[replAt] <= price
      );

      // Update swing point.
      if (write) {
         if (peek) return replAt;

         gSwingPoints[gStatus.mLastUpSwing] = 0.00;
         gSwingPoints[replAt] = price;
         gStatus.mLastUpSwing = replAt;

         // Done.
         return replAt;
      }
   }

   // If swing points at replAt not updated, maybe try previous candle.
   if (replPrev && idx > gStatus.mLastUpSwing) {
      int idxPrev = idx - 1;
      bool write = (gSwingPoints[idxPrev] == 0.0 ||
         gSwingPoints[idxPrev] < price
      );
      
      // Update swing point.
      if (write) {
         if (peek) return idxPrev;

         gSwingPoints[gStatus.mLastUpSwing] = 0.00;
         gSwingPoints[idxPrev] = price;
         gStatus.mLastUpSwing = idxPrev;

         // Done.
         return idxPrev;
      }
   }

   // If none of the cases above, can we write to current candle?
   if (gSwingPoints[idx] != 0.00) {
      return -1;
   }

   // Return if peek only.
   if (peek) return idx;

   // Write last up swing.
   gSwingPoints[gStatus.mLastUpSwing] = 0.00;
   gSwingPoints[idx] = price;
   gStatus.mLastUpSwing = idx;
   return idx;
}

//
// Utility functions - type of swing detection.
//

// Determines if next candle is a down, up, out or in candle from prior one.
SwingType findSwing(const Candle& prior, const Candle& next)
{
   // Set next high and low prices to include price filter.
   double priorHigh = prior.mHigh + iPriceFilter;
   double priorLow = prior.mLow - iPriceFilter;

   // Previous candle is lower than next... going up.
   if (priorLow < next.mLow) {
      // Up candle.
      if (priorHigh < next.mHigh) {
         return stUp;
      // Inside candle.
      } else if (priorHigh >= next.mHigh) {
         return stIn;
      }
   // Previous and next candle lows are alike.
   } else if (priorLow == next.mLow) {
      // Up candle.
      if (priorHigh < next.mHigh) {
         return stUp;
      // Inside candle.
      } else if (priorHigh >= next.mHigh) {
         return stIn;
      }
   // Previous candle is higher than next... going down.
   } else if (priorLow > next.mLow) {
      // Down candle.
      if (priorHigh >= next.mHigh) {
         return stDown;
      // Outside candle.
      } else if (priorHigh < next.mHigh) {
         return stOut;
      }
   }

   // Should not happen.
   return stUnknown;
}

// Simply fills the candle with the index specified.
// idx *must* be valid.
void getCandle(const double& open[],
   const double& high[], const double& low[],
   const double& close[], Candle& c, const int idx)
{
   c.mOpen = open[idx];
   c.mHigh = high[idx];
   c.mLow = low[idx];
   c.mClose = close[idx];
}

// Locates a previous swing and returns it's index from the current index.
// If none found, returns -1.
// A valid previous swing is one which has a swing point price or otherwise
// an inside candle.
int findPreviousSwing(int nIdx, bool ignoreInside = false)
{
   int nFound = nIdx - 1;
   while (nFound >= 0) {
      // A valid previous swing is one where we had an inside bar
      // previously as we would want to process a swing on the break
      // of an inside bar.
      if (!ignoreInside && doubleToSwing(gSwings[nFound]) == stIn)
         return nFound;

      // A valid previous swing otherwise has a price as a swing point.
      // These mark valid swing locations and are constantly updated
      // to the highest/lowest top/bottom of a swing.
      if (gSwingPoints[nFound] != 0.0)
         return nFound;

      nFound--;
   }

   // None found!
   return -1;
}

//
// Main swinging functionality.
//

// This swings an outside bar (current candle) from a down or up swing, 
// and is called by setCandleSwingsFromUp (or down).
// When swinging outside bars we will give less priority to the first swing
// such that if we only have one candle to represent the two swings, we
// represent only the second swing.
bool setCandleSwingsOutbar(
   const double& open[], const double& high[],
   const double& low[], const double& close[],
   const SwingType stCurrent, const int nIdx,
   const int nPrevious)
{
   // Candle before current is referred to as last here.
   int nLast = nIdx - 1;
   
   // Calculate top and bottom wick sizes.
   bool openEqClose = (open[nIdx] == close[nIdx]);
   double topWick = high[nIdx] - open[nIdx];
   double btmWick = open[nIdx] - low[nIdx];

   // Determine swing directions.
   bool upDown = (
      open[nIdx] > close[nIdx] ||
      (openEqClose && topWick <= btmWick)
   );
   bool downUp = (
      close[nIdx] > open[nIdx] ||
      (openEqClose && topWick > btmWick)
   );
   if ((upDown && downUp) || (!upDown && !downUp)) {
      return false;
   }

   // First peek at the first swing to see what index will be used.
   int swing1Idx = 0;
   if (downUp) {
      swing1Idx = swingDown(low, nIdx, nPrevious, true, true);
   } else {
      swing1Idx = swingUp(high, nIdx, nPrevious, true, true);
   }

   // Once we know what index will be used after the first swing make a decision
   // on the second swing. We will ignore the first swing if the first swing can
   // only be stored on the current candle (nIdx) because we may have a valid
   // second swing.
   bool skipFirstSwing = (swing1Idx == nIdx) || swing1Idx == -1;

   // We may skip genuine first swings here when the second swing is not going
   // to swing up but we rather miss first swings than second swings. Second
   // swings will swing up if bar filter is 1 or if it is greater but the second
   // swing is higher than the previous swing when 'swing on previous break' is
   // set.
   if (!skipFirstSwing) {
      if (downUp) {
         swing1Idx = swingDown(low, nIdx, nPrevious, true, false);
         gSwings[swing1Idx] = swingToDouble(stDown);
      } else {
         swing1Idx = swingUp(high, nIdx, nPrevious, true, false);
         gSwings[swing1Idx] = swingToDouble(stUp);
      }
   }

   // Do the second swing now.
   int swing2Idx = 0;
   if (downUp) {
      swing2Idx = swingUp(high, nIdx, -1, false, false);
   } else {
      swing2Idx = swingDown(low, nIdx, -1, false, false);
   }
   if (swing2Idx != -1) {
      gSwings[swing2Idx] = swingToDouble(stOut);
   }

   return true;
}

// Set candle swings from a down swing only. nIdx assumed
// valid and previous index obtainable as well. This just
// assigns the appropriate global buffers based on the current
// swing type assuming a wprevious down swing (1.x from swing
// charting sheet). Called internally only by setCandleSwings().
void setCandleSwingsFromDown(
   const double& open[], const double& high[],
   const double& low[], const double& close[],
   const SwingType stCurrent, const int nIdx,
   const int nPrevious)
{
   if (stCurrent == stDown) {
      // 1.1. Clear swing points from previous candle. We swing
      // down further.
      swingDown(low, nIdx, -1, false);
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stUp) {
      // 1.2.
      swingUp(high, nIdx, -1, false);
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stIn) {
      // 1.3. Do nothing.
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stOut) {
      // 1.4, 1.5, 1.6, 1.7.
      if (!setCandleSwingsOutbar(open, high, low, close,
         stCurrent, nIdx, nPrevious)
      ) {
         printf("%s: unexpected exception code 04.", product);
      }
   }
}

// Set candle swings from an up swing only. nIdx assumed
// valid and previous index obtainable as well. This just
// assigns the appropriate global buffers based on the current
// swing type assuming a previous down swing (2.x from swing
// charting sheet). Called internally only by setCandleSwings().
void setCandleSwingsFromUp(
   const double& open[], const double& high[],
   const double& low[], const double& close[],
   const SwingType stCurrent, const int nIdx,
   const int nPrevious)
{
   if (stCurrent == stUp) {
      // 2.1.
      swingUp(high, nIdx, -1, false);
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stDown) {
      // 2.2. Set swing type.
      swingDown(low, nIdx, -1, false);
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stIn) {
      // 2.3. Do nothing.
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stOut) {
      // 2.4, 2.5, 2.6, 2.7.
      if (!setCandleSwingsOutbar(open, high, low, close,
         stCurrent, nIdx, nPrevious)
      ) {
         printf("%s: unexpected exception code 05.", product);
      }
   }
}

// Defining the current candle at index nIdx, we need to set the
// swing data as follows:
// gSwingPoints[] - prices of swing bottoms and tops
// gSwings[]      - type of swing using swingToDouble and doubleToSwing
// To determine the swing we look at the candle at the previous index.
// nIdx always greater than 0.
// From the previous candle we determine if we have an up swing or a down
// swing in a nutshell. It gets more complex than this and we follow our
// swing charging draft sheet to determine the rules accordingly.
bool setCandleSwings(const double& open[],
   const double& high[], const double& low[],
   const double& close[], const int nIdx)
{
   // Get indices
   if (nIdx < 1) {
      return false;
   }

   // Get last actual swing.
   int nPrevSwng = findPreviousSwing(nIdx, true);
   if (nPrevSwng == -1) {
      // This shouldn't happen.
      return false;
   }

   // Get candles and swing from previous to current.
   int nLastCandle = nIdx - 1;
   Candle cLastCandle;                             // candle before current
   Candle cCurrent;                                // current candle
   getCandle(open, high, low, close, cLastCandle, nLastCandle);
   getCandle(open, high, low, close, cCurrent, nIdx);
   SwingType stPrev = doubleToSwing(gSwings[nPrevSwng]);
   SwingType stCurrent = findSwing(cLastCandle, cCurrent);

   // 1.x: from previous downswing.
   if (stPrev == stDown) {
      setCandleSwingsFromDown(open, high, low, close,
         stCurrent, nIdx, nPrevSwng
      );
      return true;
   }

   // 2.x: from previous upswing.
   if (stPrev == stUp) {
      setCandleSwingsFromUp(open, high, low, close,
         stCurrent, nIdx, nPrevSwng
      );
      return true;
   }

   // 3.x from previous outside bar downswing.
   if (stPrev == stOut && gSwingPoints[nPrevSwng] <= low[nPrevSwng]) {
      setCandleSwingsFromDown(open, high, low, close,
         stCurrent, nIdx, nPrevSwng
      );
      return true;
   }

   // 4.x from previous outside bar upswing.
   if (stPrev == stOut && gSwingPoints[nPrevSwng] >= high[nPrevSwng]) {
      setCandleSwingsFromUp(open, high, low, close,
         stCurrent, nIdx, nPrevSwng
      );
      return true;
   }

   // Inside bars fall into two categories 7.x and 8.x. We need the prior
   // swing to determine which category the inside bar falls under.
   if (stPrev == stIn) {
      // Does the inside bar contain a swing that has been imposed on due
      // to an outside bar?
      if (gSwingPoints[nPrevSwng] != 0) {
         if (nPrevSwng == gStatus.mLastDownSwing) {
            setCandleSwingsFromDown(open, high, low, close,
               stCurrent, nIdx, nPrevSwng
            );
         } else if (nPrevSwng == gStatus.mLastUpSwing) {
            setCandleSwingsFromUp(open, high, low, close,
               stCurrent, nIdx, nPrevSwng
            );
         } else {
            // We should not have a previous swing that's not the last up
            // or down swing. Capture an anomaly here...
            return false;
         }
         
         // Inside bar treated as a regular swing instead of an inside bar.
         return true;
      }
      
      // Find swing prior to the inside bar nPrior.
      int nPrior = findPreviousSwing(nPrevSwng);
      while (nPrior > 0 && doubleToSwing(gSwings[nPrior]) == stIn) {
         // Always clear previous inside bar swings.
         gSwingPoints[nPrior] = 0.0;
            nPrior = findPreviousSwing(nPrior);
      }
      if (doubleToSwing(gSwings[nPrior]) == stUnknown) {
         return false;
      }

      // 7.x from a downswing.
      // When prior swing was at low or below (outside bar low).
      if (gSwingPoints[nPrior] <= low[nPrior] && gSwingPoints[nPrior] > 0) {
         setCandleSwingsFromDown(open, high, low,
            close, stCurrent, nIdx, nPrior
         );
      }

      // 8.x from an upswing.
      // When prior swing was at high or above (outside bar low).
      if (gSwingPoints[nPrior] >= high[nPrior]) {
         setCandleSwingsFromUp(open, high, low,
            close, stCurrent, nIdx, nPrior
         );
      }
   }

   // Done.
   return true;
}
