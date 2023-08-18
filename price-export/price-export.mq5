/*
Date: 16 Aug 2023 06:56:48.816996064
File: price-export.mq5

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

Sign:    __PRICE-EXPORT_MQ5_D61A05A71F53782E4175F38980AC8629__
Purpose: Price exporting tool for Metatrader 5.
         Some notes:
         - Files are written to: MQL5\Files.
         - Files whose last entry is in the future won't be written to.

Version control
16 Aug 2023 Duncan Camilleri           Initial development
18 Aug 2023 Duncan Camilleri           Corrected use of volume
18 Aug 2023 Duncan Camilleri           Add a header.
*/
#property description   "Price export tool.\n"
                        "\n"
                        "Exports prices for the active chart symbol.\n"
                        "Currently this exports data as follows:\n"
                        "YYYY/MM/DD HH:MM:SS A|PM, "
                        "open, high, low, close, volume\n"
#property copyright     "Copyright 2023, Duncan Camilleri."
#property link          "http://www.dnc77.com"
#property version       "1.01"
#property strict

#define product         "Price export"

#define FILEWRITEFLAGS  (FILE_TXT | FILE_ANSI | FILE_WRITE | FILE_READ)

//
// INCLUDES.
//
#include <Arrays\ArrayObj.mqh>

//
// Type definitions.
//

// Different type of date formats.
enum DateFmt {
   Y4M2D2H2M2S2AP_SEP   = 0x01
};

// Represents one csv record.
struct Record {
   datetime mTime;
   double mOpen;
   double mHigh;
   double mLow;
   double mClose;
   long mVolume;
};

// Represents info about a file.
class PriceFile : public CObject {
private:
   // Construction/etc...
   PriceFile() { }                                 // no default constructor

public:
   PriceFile(string symbol, ENUM_TIMEFRAMES period);
   virtual ~PriceFile();

   // Accessors.
   const string filename()                         { return mFilename; }

   // Loading/unloading.
   bool load();                                    // loads last record
   void unload();                                  // closes open handle

   // Updating file with new prices.
   // These functions assume the file is already open in write mode.
   bool update();

protected:
   // File specific.
   int mHandle;                                    // INVALID_HANDLE if closed
   string mFilename;
   Record mLastRecord;

   // Data info.
   string mSymbol;
   ENUM_TIMEFRAMES mPeriod;

   // Processing data.
   int mSeconds;                                   // seconds per candle

protected:
   // Last record functionality.
   void emptyLast();                               // empties last record
   bool isLastEmpty();
};

//
// GLOBALS.
//

// Input parameters
input DateFmt iDateFmt = Y4M2D2H2M2S2AP_SEP;       // Date format:
input int iPastCandles = 200;                      // Past candles:
input bool iShowGapRecord = true;                  // Show gap record:
input bool iM1;                                    // Export M1 data:
input bool iM5;                                    // Export M5 data:
input bool iM15;                                   // Export M15 data:
input bool iM30;                                   // Export M30 data:
input bool iH1;                                    // Export H1 data:
input bool iH4;                                    // Export H4 data:
input bool iD1;                                    // Export D1 data:
input bool iW1;                                    // Export W1 data:

// App globals.
string gLogMsgHdr = "priceexport msg: ";           // Log message header
CArrayObj gPriceFiles;

// Constants
datetime gInvalidTime = D'1970.01.01 00:00';

//
// CSV ROW CONVERSION.
//

// AMPM field format is as follows:
// YYYY/MM/DD HH:MM:SS A|PM
// Note: hours are treated as 24 hours and we are working with AMPM (12 hour).
// So we need to get the time to a struct first before converting to a string.
// We don't want to convert directly to a string else it would cause us a
// potential 24 hour value incorrectly. Faster to just get to struct and dump
// to string ;)
string timeToAmpmField(datetime in)
{
   MqlDateTime mdt;
   if (!TimeToStruct(in, mdt)) return "";

   // AM/PM?
   string ampm = "AM";
   if (mdt.hour >= 12) {
      ampm = "PM";
      mdt.hour -= 12;
   }

   // Combine.
   return IntegerToString(mdt.year) + "/" +
      StringFormat("%02d", mdt.mon) + "/" +
      StringFormat("%02d", mdt.day) + " " +
      StringFormat("%02d", mdt.hour) + ":" +
      StringFormat("%02d", mdt.min) + ":" +
      StringFormat("%02d", mdt.sec) + " " + ampm;
}

// AMPM field format is as follows:
// YYYY/MM/DD HH:MM:SS A|PM
datetime ampmFieldToTime(string ampm)
{
   // Parse the date.
   string dateTime[];
   string date[];
   string time[];
   
   // Date, Time, AMPM.
   if (3 != StringSplit(ampm, ' ', dateTime)) {
      return gInvalidTime;
   }

   // Split date.
   if (3 != StringSplit(dateTime[0], '/', date)) {
      return gInvalidTime;
   }

   // Split time.
   if (3 != StringSplit(dateTime[1], ':', time)) {
      return gInvalidTime;
   }

   // Ok; get the hour in 12 hour format and convert it to 24.
   long hour = StringToInteger(time[0]);
   if (dateTime[2][0] == 'p' || dateTime[2][0] == 'P') {
      if (hour < 12) hour = hour + 12;
   }

   // Put them all together!
   return StringToTime(date[0] + "." + date[1] + "." + date[2] + " " +
      IntegerToString(hour) + ":" + time[1] + ":" + time[2]
   );
}

// Converts a record into a string for writing to csv.
string RecordToString(const Record& r)
{
   return timeToAmpmField(r.mTime) + "," + DoubleToString(r.mOpen) + "," +
      DoubleToString(r.mHigh) + "," + DoubleToString(r.mLow) + "," +
      DoubleToString(r.mClose) + "," + IntegerToString(r.mVolume) +
      "\r\n";
}

// Converts a string into a record. String format is as follows:
// YYYY/MM/DD HH:MM:SS A|PM, open, high, low, close, volume
bool StringToRecord(const string sRow, Record& r) 
{
   // Convert input string to array.
   string fields[];
   if (6 != StringSplit(sRow, ',', fields))
      return false;

   // Read values into structure.
   r.mTime = ampmFieldToTime(fields[0]);
   r.mOpen = StringToDouble(fields[1]);
   r.mHigh = StringToDouble(fields[2]);
   r.mLow = StringToDouble(fields[3]);
   r.mClose= StringToDouble(fields[4]);
   r.mVolume = StringToInteger(fields[5]);

   // Done.
   return true;
}

//
// PRICEFILE CLASS.
//

//
// Construction/etc...
//

// Load up.
PriceFile::PriceFile(string symbol, ENUM_TIMEFRAMES period)
{
   mHandle = INVALID_HANDLE;
   mSymbol = symbol;
   mPeriod = period;

   // Set filename.
   mFilename = "PriceExport-" + mSymbol;

   // Period specifics.
   switch (mPeriod) {
   case PERIOD_M1:
      mSeconds = 60;
      mFilename = mFilename + "_M1";
      break;
   case PERIOD_M2:
      mSeconds = 120;
      mFilename = mFilename + "_M2";
      break;
   case PERIOD_M3:
      mSeconds = 180;
      mFilename = mFilename + "_M3";
      break;
   case PERIOD_M4:
      mSeconds = 240;
      mFilename = mFilename + "_M4";
      break;
   case PERIOD_M5:
      mSeconds = 300;
      mFilename = mFilename + "_M5";
      break;
   case PERIOD_M6:
      mSeconds = 360;
      mFilename = mFilename + "_M6";
      break;
   case PERIOD_M10:
      mSeconds = 600;
      mFilename = mFilename + "_M10";
      break;
   case PERIOD_M12:
      mSeconds = 720;
      mFilename = mFilename + "_M12";
      break;
   case PERIOD_M15:
      mSeconds = 900;
      mFilename = mFilename + "_M15";
      break;
   case PERIOD_M20:
      mSeconds = 1200;
      mFilename = mFilename + "_M20";
      break;
   case PERIOD_M30:
      mSeconds = 1800;
      mFilename = mFilename + "_M30";
      break;
   case PERIOD_H1:
      mSeconds = 3600;
      mFilename = mFilename + "_H1";
      break;
   case PERIOD_H2:
      mSeconds = 3600 * 2;
      mFilename = mFilename + "_H2";
      break;
   case PERIOD_H3:
      mSeconds = 3600 * 3;
      mFilename = mFilename + "_H3";
      break;
   case PERIOD_H4:
      mSeconds = 3600 * 4;
      mFilename = mFilename + "_H4";
      break;
   case PERIOD_H6:
      mSeconds = 3600 * 6;
      mFilename = mFilename + "_H6";
      break;
   case PERIOD_H8:
      mSeconds = 3600 * 8;
      mFilename = mFilename + "_H8";
      break;
   case PERIOD_H12:
      mSeconds = 3600 * 12;
      mFilename = mFilename + "_H12";
      break;
   case PERIOD_D1:
      mSeconds = 3600 * 24;
      mFilename = mFilename + "_D1";
      break;
   case PERIOD_W1:
      mSeconds = 3600 * 24 * 7;
      mFilename = mFilename + "_W1";
      break;
   };

   // Trailing extension for filename.
   mFilename = mFilename + ".csv";
}

// Free up.
PriceFile::~PriceFile()
{
   // Close file if it's open.
   unload();
   if (mHandle != INVALID_HANDLE) {
      FileClose(mHandle);
      mHandle = INVALID_HANDLE;
   }
}

//
// Loading/unloading.
//

// Loads up the last record from the local filename. If the last record is not
// found or if the file is not found, then the last record will be empty (all
// values 0) and the date is set to gInvalidTime.
// Return:  true on success.
//          false on critical error.
//          Note: If the last record is not loaded simply because it's not
//          there, return is true. If the file does not exist, it's created
//          and last record is set to empty; true is returned in this case.
//          If the file cannot be opened or created, false is returned.
//          If the file is already loaded, this will fail (at least for now).
bool PriceFile::load()
{
   // Won't reload if already loaded.
   if (mHandle != INVALID_HANDLE) {
      return false;
   }

   // Open file and try to fetch last record.
   emptyLast();
   mHandle = FileOpen(mFilename, FILE_TXT | FILE_ANSI | FILE_READ, "");
   if (INVALID_HANDLE == mHandle) {
      // No current file... Create with a header.
      mHandle = FileOpen(mFilename, FILEWRITEFLAGS, "");
      if (INVALID_HANDLE == mHandle) {
         Print(gLogMsgHdr + "cannot create file!");
         return false;
      }
      
      // Write a header.
      FileWriteString(mHandle,
         "\"Date\",\"Open\",\"High\",\"Low\",\"Close\",\"Volume\"\r\n"
      );
      FileClose(mHandle);
      mHandle = INVALID_HANDLE;

      // Success.
      return true;
   }

   // File opened successfully. Get last record (if it exists).
   // We will treat lines beginning with a '#' as a comment.
   while (!FileIsEnding(mHandle)) {
      string line = FileReadString(mHandle);
      if (line[0] == '#') continue;                // skip comments ;)

      // Read last record in.
      if (!StringToRecord(line, mLastRecord)) {
         emptyLast();
      }
   }

   // Close read only handle - done.
   FileClose(mHandle);
   mHandle = INVALID_HANDLE;
   return true;
}

// Unloads file. Closes any handles. The file is expected to have a write
// handle open to it.
void PriceFile::unload()
{
   if (INVALID_HANDLE == mHandle) {
      emptyLast();
      return;
   }

   // In case the file is open, close it and exit.
   FileClose(mHandle);
   mHandle = INVALID_HANDLE;
   emptyLast();
}

//
// Updating file with new prices.
// These functions assume the file is already open in write mode.
// The last record entry of the file is also set.
bool PriceFile::update()
{
   // Get the last number of candles required. We ignore the last candle.
   MqlRates rates[];
   if (-1 == CopyRates(mSymbol, mPeriod, 1, iPastCandles, rates)) {
      Print(gLogMsgHdr + " data not available: too many candles requested.");
      return false;
   }

   // Get the number of rates and the offset where to start reading from.
   int ratesMax = ((int)rates.Size()) - 1;
   int startOffset = 0;                            // default: write all
   if (!isLastEmpty()) {
      // Look from the end of the current list of candles as for the most part
      // we will be updating only a small subset of all the candles fetched in
      // to the file. Find the first rate that matches the last entry of the
      // file and set the start offset to after it.
      for (int n = ratesMax; n >= 0; --n) {
         if (rates[n].time <= mLastRecord.mTime) {
            startOffset = n + 1;
            break;
         }
      }
   }

   // Open file handle.
   if (INVALID_HANDLE != mHandle) {
      FileClose(mHandle);
      mHandle = INVALID_HANDLE;
   }
   mHandle = FileOpen(mFilename, FILEWRITEFLAGS, "");
   if (INVALID_HANDLE == mHandle) {
      ArrayFree(rates);
      return false;
   }

   // Move to end of file.
   FileSeek(mHandle, 0, SEEK_END);  

   // We identified the starting offset of the candles to write to file.
   // If for whatever reason, this starting offset of candles comes before
   // the last entry in the file, we should not write it.
   for (int n = startOffset; n <= ratesMax; ++n) {
      // Write the prices to the file. Is the first fetched row in memory
      // leaves a gap in the file, we need to record that gap.
      if (n == 0 && !isLastEmpty()) {
         datetime dtPrevious = rates[n].time - mSeconds;
         if (dtPrevious > mLastRecord.mTime && iShowGapRecord) {
            FileWriteString(mHandle, "# gap : MQ5 Prices by Price Export "
               "(https://github(dot)com/dnc77) : gap. \r\n");
         } else if (dtPrevious < mLastRecord.mTime) {
            Print(gLogMsgHdr + "time period in file not in sync!");
         }
      }

      // Update last record and write to file.
      mLastRecord.mTime = rates[n].time;
      mLastRecord.mOpen = rates[n].open;
      mLastRecord.mHigh = rates[n].high;
      mLastRecord.mLow = rates[n].low;
      mLastRecord.mClose = rates[n].close;
      mLastRecord.mVolume = rates[n].tick_volume;
      
      // Write a csv entry.
      string csvLine = RecordToString(mLastRecord);
      if (0 >= FileWriteString(mHandle, csvLine)) {
         Print(gLogMsgHdr + "file write issue: record not written!");
      }
   }

   // Close file handle.
   FileClose(mHandle);
   mHandle = INVALID_HANDLE;

   // Done.
   ArrayFree(rates);
   return true;
}

//
// Last record functionality.
//

void PriceFile::emptyLast()
{
   mLastRecord.mTime = gInvalidTime;
   mLastRecord.mOpen = mLastRecord.mHigh =
      mLastRecord.mLow = mLastRecord.mClose = 0.0;
   mLastRecord.mVolume = 0;
}

bool PriceFile::isLastEmpty()
{
   return mLastRecord.mTime == gInvalidTime &&
      mLastRecord.mOpen == 0 && mLastRecord.mHigh == 0 &&
      mLastRecord.mLow == 0 && mLastRecord.mClose == 0 &&
      mLastRecord.mVolume == 0;
}

//
// PRICE FILE FUNCTIONALITY.
//

// Ditto.
bool createAllPriceFiles()
{
   PriceFile* pNew = NULL;
   if (iM1) {
      pNew = new PriceFile(Symbol(), PERIOD_M1);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_M1 - out of memory.");
         return false;
      }
   }
   if (iM5) {                                  
      pNew = new PriceFile(Symbol(), PERIOD_M5);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_M5 - out of memory.");
         return false;
      }
   }
   if (iM15) {                                 
      pNew = new PriceFile(Symbol(), PERIOD_M15);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_M15 - out of memory.");
         return false;
      }
   }
   if (iM30) {                                 
      pNew = new PriceFile(Symbol(), PERIOD_M30);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_M30 - out of memory.");
         return false;
      }
   }
   if (iH1) {                                  
      pNew = new PriceFile(Symbol(), PERIOD_H1);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_H1 - out of memory.");
         return false;
      }
   }
   if (iH4) {                                  
      pNew = new PriceFile(Symbol(), PERIOD_H4);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_H4 - out of memory.");
         return false;
      }
   }
   if (iD1) {                                  
      pNew = new PriceFile(Symbol(), PERIOD_D1);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_D1 - out of memory.");
         return false;
      }
   }
   if (iW1) {                                  
      pNew = new PriceFile(Symbol(), PERIOD_W1);
      if (NULL == pNew || !gPriceFiles.Add(pNew)) {
         Print(gLogMsgHdr + "could not load PERIOD_W1 - out of memory.");
         return false;
      }
   }

   // Done!
   return true;
}

// Ditto.
void destroyAllPriceFiles()
{
   // Free up all price files.
   for (int n = 0; n < gPriceFiles.Total(); ++n) {
      if (gPriceFiles.At(n))
         delete gPriceFiles.At(n);
   }
   gPriceFiles.Clear();
   gPriceFiles.Shutdown();
}

//
// Main EA Events.
//

// Initialize - Read last row from files.
// When no last row or file is found, create a new file and read last past
// candle count to fetch. Filename created will be SYMBOL_PERIOD.csv
// in the provided input directory.
// When a last row is found, if it's not fetchable from the live candle
// prices within the last candle count to fetch, a gap line will be
// created. A gap line will look like this:
// # gap : MQ5 Prices by Price Export (https://github(dot)com/dnc77) : gap.
int OnInit()
{
   // Create PriceFile objects first.
   if (!createAllPriceFiles()) {
      destroyAllPriceFiles();
      return INIT_FAILED;
   }

   // Load all last records.
   for (int n = 0; n < gPriceFiles.Total(); ++n) {
      PriceFile* pFile = gPriceFiles.At(n);
      if (!pFile.load()) {
         Print(gLogMsgHdr + "failed loading file '" + pFile.filename() + "'");
         destroyAllPriceFiles();
         return INIT_FAILED;
      }
   }

   // Do a one time initialization (first update).
   OnTimer();

   // Sync with one minute candles ;)
   MqlDateTime svrTime;
   TimeTradeServer(svrTime);
   if (svrTime.sec > 0) {
      Print(gLogMsgHdr + "initialization complete in " +
         IntegerToString(60 - svrTime.sec) + " seconds...");
      do {
         Sleep(100);
         TimeTradeServer(svrTime);
      } while (svrTime.sec != 0);
   }

   // Set timer to run each minute on the 0th second.
   if (!EventSetTimer(60)) {
      Print(gLogMsgHdr + "failed setting export timer!");
      destroyAllPriceFiles();
      return INIT_FAILED;
   }

   // Done initializing.
   Print(gLogMsgHdr + "initialization complete.");
   return INIT_SUCCEEDED;
}

// Terminate.
void OnDeinit(const int reason)
{
   EventKillTimer();
   destroyAllPriceFiles();
}

// Every second (on the 00 second), update the prices in the file.
// We know what the last price of each file is so we don't have to look
// for that in the file each time ;)
void OnTimer()
{
   // Basically just iterate through all the files and write out the
   // last candles if there were any.
   // A gap is written to the file if the last n candles obtained leave
   // a gap in the candles in the file.
   for (int n = 0; n < gPriceFiles.Total(); ++n) {
      PriceFile* pFile = gPriceFiles.At(n);
      if (!pFile.update()) {
         Print(gLogMsgHdr + "failed updating file '" + pFile.filename() + "'");
      }
   }
}

/* We won't be using these.
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
}

void OnTick()
{
}
*/
