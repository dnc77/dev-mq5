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
Features:   Draw as separate window? Draw as straight line.

Version control
29 Sep 2023 Duncan Camilleri           Initial development
*/

#property description   "Gann Swing.\n"
                        "\n"
                        "Draws swing chart on MT5.\n"
#property copyright     "Copyright (C) 2023 Duncan Camilleri."
#property link          "http://www.dnc77.com"
#property version       "1.00"

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots 1

#property indicator_label1 "gannswing"
#property indicator_type1 DRAW_SECTION
#property indicator_color1 Blue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1

#property strict

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
   stOut = 0x04,
   stOutHalf = 0x05                                // unswung outside bar
};

// Candle represents one single candle to be used to aid in drawing the swings.
struct Candle {
   double mOpen;
   double mHigh;
   double mLow;
   double mClose;
};

//
// Globals.
//
double gSwingPoints[];                             // swing prices
double gSwings[];                                  // swing type of each swing

//
// Init/Term.
//

int OnInit()
{
   // Deinitialize first.
   OnDeinit(0);
   // printf("init");

   // Set index buffers.
   SetIndexBuffer(0, gSwingPoints, INDICATOR_DATA);
   SetIndexBuffer(1, gSwings, INDICATOR_DATA);

   // Define empty.
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // printf("deinit");
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
   // Go through each candle.
   for (int n = prev_calculated; n < rates_total; ++n) {
      // First candle ever!
      if (n == 0) {
         // Identify first swing.
         Candle current;
         getCandle(open, high, low, close, current, n);
         gSwings[0] = startSwing(current);
         if (doubleToSwing(gSwings[0] == stUp)) {
            gSwingPoints[0] = high[0];
         } else {
            gSwingPoints[0] = low[0];
         }

         // Next.
         n++;
      }

      // Process candle at current index.
      setCandleSwings(open, high, low, close, n);
   }

   // All candles processed but ignore the last 15 candles.
   // return lastValid + 1;
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
// Utility functions - type of swing detection.
//

// Assigns swing to starting candle.
SwingType startSwing(const Candle& start)
{
   if (start.mOpen <= start.mClose) {
      return stUp;
   }

   return stDown;
}

// Determines if next candle is a down, up, out or in candle from prior one.
SwingType findSwing(const Candle& prior, const Candle& next)
{
   // Previous candle is lower than next... going up.
   if (prior.mLow < next.mLow) {
      // Up candle.
      if (prior.mHigh < next.mHigh) {
         return stUp;
      // Inside candle.
      } else if (prior.mHigh >= next.mHigh) {
         return stIn;
      }
   // Previous and next candle lows are alike.
   } else if (prior.mLow == next.mLow) {
      // Up candle.
      if (prior.mHigh < next.mHigh) {
         return stUp;
      // Inside candle.
      } else if (prior.mHigh >= next.mHigh) {
         return stIn;
      }
   // Previous candle is higher than next... going down.
   } else if (prior.mLow > next.mLow) {
      // Down candle.
      if (prior.mHigh >= next.mHigh) {
         return stDown;
      // Outside candle.
      } else if (prior.mHigh < next.mHigh) {
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
int findPreviousSwing(int nIdx)
{
   int nFound = nIdx - 1;
   while (nFound >= 0) {
      // A valid previous swing is one where we had an inside bar
      // previously as we would want to process a swing on the break
      // of an inside bar.
      if (doubleToSwing(gSwings[nFound]) == stIn)
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


// Set candle swings from a down swing only. nIdx assumed
// valid and previous index obtainable as well. This just
// assigns the appropriate global buffers based on the current
// swing type assuming a previous down swing (1.x from swing
// charting sheet). Called internally only by setCandleSwings().
void setCandleSwingsFromDown(
   const double& open[], const double& high[],
   const double& low[], const double& close[],
   const SwingType stCurrent, const int nIdx,
   const int nPrevious)
{
   if (stCurrent == stDown) {
      // 1.1.
      gSwingPoints[nPrevious] = 0.0;
      gSwingPoints[nIdx] = low[nIdx];
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stUp) {
      // 1.2.
      gSwingPoints[nIdx] = high[nIdx];
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stIn) {
      // 1.3. Do nothing.
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stOut) {
      if (close[nIdx] > open[nIdx]) {
         // 1.4.
         if (0 == gSwingPoints[nPrevious] ||
            gSwingPoints[nPrevious] > low[nIdx]
         ) {
            gSwingPoints[nPrevious] = low[nIdx];
         }

         gSwingPoints[nIdx] = high[nIdx];
         gSwings[nIdx] = swingToDouble(stOut);
      } else if (open[nIdx] > close[nIdx]) {
         // 1.5.
         gSwingPoints[nIdx] = high[nIdx];
         gSwings[nIdx] = swingToDouble(stOutHalf);
      } else { // open == close
         double topWick = high[nIdx] - open[nIdx];
         double btmWick = open[nIdx] - low[nIdx];
         if (topWick <= btmWick) {
            // 1.6 (replicate 1.5).
            gSwingPoints[nIdx] = high[nIdx];
            gSwings[nIdx] = swingToDouble(stOutHalf);         
         } else {
            // 1.7 (replicate 1.4).
            if (0 == gSwingPoints[nPrevious] ||
               gSwingPoints[nPrevious] > low[nIdx]
            ) {
               gSwingPoints[nPrevious] = low[nIdx];
            }

            gSwingPoints[nIdx] = high[nIdx];
            gSwings[nIdx] = swingToDouble(stOut);         
         }
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
      gSwingPoints[nPrevious] = 0.0;
      gSwingPoints[nIdx] = high[nIdx];
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stDown) {
      // 2.2.
      gSwingPoints[nIdx] = low[nIdx];
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stIn) {
      // 2.3. Do nothing.
      gSwings[nIdx] = swingToDouble(stCurrent);
   } else if (stCurrent == stOut) {
      if (close[nIdx] > open[nIdx]) {
         // 2.4.
         gSwingPoints[nIdx] = low[nIdx];
         gSwings[nIdx] = swingToDouble(stOutHalf);
      } else if (open[nIdx] > close[nIdx]) {
         // 2.5.
         if (gSwingPoints[nPrevious] == 0.0 ||
            gSwingPoints[nPrevious] < high[nIdx]) {
               gSwingPoints[nPrevious] = high[nIdx];            
         }

         gSwingPoints[nIdx] = low[nIdx];
         gSwings[nIdx] = swingToDouble(stOut);
      } else { // open == close
         double topWick = high[nIdx] - open[nIdx];
         double btmWick = open[nIdx] - low[nIdx];
         if (topWick <= btmWick) {
            // 2.6 (replicate 2.5).
            if (gSwingPoints[nPrevious] == 0.0 ||
               gSwingPoints[nPrevious] < high[nIdx]) {
                  gSwingPoints[nPrevious] = high[nIdx];            
            }
   
            gSwingPoints[nIdx] = low[nIdx];
            gSwings[nIdx] = swingToDouble(stOut);
         } else {
            // 2.7 (replicate 2.4).
            gSwingPoints[nIdx] = low[nIdx];
            gSwings[nIdx] = swingToDouble(stOutHalf);
         }
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
// Note: We split all situations separately for simplicity. In reality,
// everything sums up to two conditions and the half outside bars.
bool setCandleSwings(const double& open[],
   const double& high[], const double& low[],
   const double& close[], const int nIdx)
{
   // Get indices
   if (nIdx < 1) return false;

   // Get to next inside bar or last actual swing.
   int nPrevious = findPreviousSwing(nIdx);
   if (nPrevious == -1) return false;              // this shouldn't happen

   // Get candles and swing from previous to current.
   Candle cPrevious;
   Candle cCurrent;
   getCandle(open, high, low, close, cPrevious, nPrevious);
   getCandle(open, high, low, close, cCurrent, nIdx);
   SwingType stPrev = doubleToSwing(gSwings[nPrevious]);
   SwingType stCurrent = findSwing(cPrevious, cCurrent);

   // 1.x: from previous downswing.
   if (stPrev == stDown) {
      setCandleSwingsFromDown(open, high, low, close,
         stCurrent, nIdx, nPrevious
      );
      return true;
   }

   // 2.x: from previous upswing.
   if (stPrev == stUp) {
      setCandleSwingsFromUp(open, high, low, close,
         stCurrent, nIdx, nPrevious
      );
      return true;
   }

   // 3.x from previous outside bar downswing.
   if (stPrev == stOut && gSwingPoints[nPrevious] == low[nPrevious]) {
      setCandleSwingsFromDown(open, high, low, close,
         stCurrent, nIdx, nPrevious
      );
      return true;
   }

   // 4.x from previous outside bar upswing.
   if (stPrev == stOut && gSwingPoints[nPrevious] == high[nPrevious]) {
      setCandleSwingsFromUp(open, high, low, close,
         stCurrent, nIdx, nPrevious
      );
      return true;
   }

   // Half outside bars (unswung).
   // If we have an unswung outside bar, we first try to resolve it by
   // seeing if the previous candle has a swing point. Note: previous
   // candle may not necessarily be nPrevious. Be wary of that as we
   // may later have a filter for multiple candles. If the immediate
   // previous candle has no swing point, move the outside bar's swing
   // point to the previous candle and perform the second half of the
   // outside bar swing on the outside bar.
   // If we don't have an empty previous candle, we skip the extra
   // outside bar swing. :(.

   // 5.x from previous half (unswung) outside bar downswing.
   if (stPrev == stOutHalf && gSwingPoints[nPrevious] == low[nPrevious]) {
      // Try take advantage of a prior candle that has no swing on it to
      // process the full outside bar swing.
      int nPrior = nPrevious - 1;
      if (nPrior >= 0 && gSwingPoints[nPrior] == 0.0) {
         gSwingPoints[nPrior] = low[nPrevious];
         gSwingPoints[nPrevious] = high[nPrevious];
         gSwings[nPrevious] = swingToDouble(stOut);

         // We changed direction. Treat as an upswing.
         setCandleSwingsFromUp(open, high, low, close,
            stCurrent, nIdx, nPrevious
         );
      } else {
         // Treat as normal downswing.
         setCandleSwingsFromDown(open, high, low, close,
            stCurrent, nIdx, nPrevious
         );
      }
      
      return true;
   }

   // 6.x from previous half (unswung) outside bar upswing.
   if (stPrev == stOutHalf && gSwingPoints[nPrevious] == high[nPrevious]) {
      // Try take advantage of a prior candle that has no swing on it to
      // process the full outside bar swing.
      int nPrior = nPrevious - 1;
      if (nPrior >= 0 && gSwingPoints[nPrior] == 0.0) {
         gSwingPoints[nPrior] = high[nPrevious];
         gSwingPoints[nPrevious] = low[nPrevious];
         gSwings[nPrevious] = swingToDouble(stOut);

         // We changed direction. Treat as a downswing.
         setCandleSwingsFromDown(open, high, low, close,
            stCurrent, nIdx, nPrevious
         );
      } else {
         // Treat as normal upswing.
         setCandleSwingsFromUp(open, high, low, close,
            stCurrent, nIdx, nPrevious
         );
      }

      return true;
   }

   // Inside bars fall into two categories 7.x and 8.x. We need the prior
   // swing to determine which category the inside bar falls under.
   if (stPrev == stIn) {
      // Find swing prior to the inside bar nPrior.
      int nPrior = findPreviousSwing(nPrevious);
      while (nPrior > 0 && doubleToSwing(gSwings[nPrior]) == stIn) {
         // Always clear previous inside bar swings.
         gSwingPoints[nPrior] = 0.0;
            nPrior = findPreviousSwing(nPrior);
      }
      if (doubleToSwing(gSwings[nPrior]) == stUnknown) return false;

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
