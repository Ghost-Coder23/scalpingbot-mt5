//+------------------------------------------------------------------+
//|                                              ImprovedScalpingBot.mqh |
//|                        Copyright 2024, Your Name                |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.mql5.com"

// Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

// Global variables for trade management
CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;

// Indicator handles
int emaHandle;
int rsiHandle;
int bbHandle;
int smaHandle15;

// Magic number for position identification
#define MAGIC_NUMBER 123456

//+------------------------------------------------------------------+
//| Initialize indicators                                             |
//+------------------------------------------------------------------+
bool InitializeIndicators(int emaPeriod, int rsiPeriod, int bbPeriod)
{
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return false;
   }
   
   // Set magic number for trade operations
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   
   // Create indicator handles
   emaHandle = iMA(_Symbol, PERIOD_M5, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M5, rsiPeriod, PRICE_CLOSE);
   bbHandle = iBands(_Symbol, PERIOD_M5, bbPeriod, 0, 2.0, PRICE_CLOSE);
   smaHandle15 = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
   
   // Validate handles
   if(emaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || 
      bbHandle == INVALID_HANDLE || smaHandle15 == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Clean up indicators                                               |
//+------------------------------------------------------------------+
void CleanupIndicators()
{
   IndicatorRelease(emaHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(bbHandle);
   IndicatorRelease(smaHandle15);
}

//+------------------------------------------------------------------+
//| Get EMA value with error checking                                |
//+------------------------------------------------------------------+
double GetEMA(int shift = 0)
{
   double buffer[1];
   if(CopyBuffer(emaHandle, 0, shift, 1, buffer) <= 0)
   {
      Print("Failed to copy EMA buffer");
      return EMPTY_VALUE;
   }
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Get RSI value with error checking                               |
//+------------------------------------------------------------------+
double GetRSI(int shift = 0)
{
   double buffer[1];
   if(CopyBuffer(rsiHandle, 0, shift, 1, buffer) <= 0)
   {
      Print("Failed to copy RSI buffer");
      return EMPTY_VALUE;
   }
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Get Bollinger Bands values                                      |
//+------------------------------------------------------------------+
bool GetBollingerBands(double& upper, double& middle, double& lower, int shift = 0)
{
   double upperBuffer[1], middleBuffer[1], lowerBuffer[1];
   
   if(CopyBuffer(bbHandle, 0, shift, 1, middleBuffer) <= 0 ||
      CopyBuffer(bbHandle, 1, shift, 1, upperBuffer) <= 0 ||
      CopyBuffer(bbHandle, 2, shift, 1, lowerBuffer) <= 0)
   {
      Print("Failed to copy Bollinger Bands buffer");
      return false;
   }
   
   upper = upperBuffer[0];
   middle = middleBuffer[0];
   lower = lowerBuffer[0];
   return true;
}

//+------------------------------------------------------------------+
//| Check if market is trending up on higher timeframe             |
//+------------------------------------------------------------------+
bool IsUptrendMTF()
{
   double current[1], previous[1];
   
   if(CopyBuffer(smaHandle15, 0, 0, 1, current) <= 0 ||
      CopyBuffer(smaHandle15, 0, 1, 1, previous) <= 0)
   {
      Print("Failed to copy SMA15 buffer");
      return false;
   }
   
   return current[0] > previous[0];
}

//+------------------------------------------------------------------+
//| Improved bullish engulfing pattern detection                   |
//+------------------------------------------------------------------+
bool IsBullishEngulfing()
{
   double open[2], close[2], high[2], low[2];
   
   if(CopyOpen(_Symbol, PERIOD_M5, 0, 2, open) != 2 ||
      CopyClose(_Symbol, PERIOD_M5, 0, 2, close) != 2 ||
      CopyHigh(_Symbol, PERIOD_M5, 0, 2, high) != 2 ||
      CopyLow(_Symbol, PERIOD_M5, 0, 2, low) != 2)
   {
      return false;
   }
   
   // Previous candle is bearish
   bool prevBearish = close[1] < open[1];
   // Current candle is bullish
   bool currentBullish = close[0] > open[0];
   // Current candle engulfs previous
   bool engulfs = close[0] > open[1] && open[0] < close[1];
   // Add volume confirmation if available
   bool volumeConfirm = true; // Can add volume check here
   
   return prevBearish && currentBullish && engulfs && volumeConfirm;
}

//+------------------------------------------------------------------+
//| Improved bearish engulfing pattern detection                   |
//+------------------------------------------------------------------+
bool IsBearishEngulfing()
{
   double open[2], close[2], high[2], low[2];
   
   if(CopyOpen(_Symbol, PERIOD_M5, 0, 2, open) != 2 ||
      CopyClose(_Symbol, PERIOD_M5, 0, 2, close) != 2 ||
      CopyHigh(_Symbol, PERIOD_M5, 0, 2, high) != 2 ||
      CopyLow(_Symbol, PERIOD_M5, 0, 2, low) != 2)
   {
      return false;
   }
   
   // Previous candle is bullish
   bool prevBullish = close[1] > open[1];
   // Current candle is bearish
   bool currentBearish = close[0] < open[0];
   // Current candle engulfs previous
   bool engulfs = close[0] < open[1] && open[0] > close[1];
   // Add volume confirmation if available
   bool volumeConfirm = true; // Can add volume check here
   
   return prevBullish && currentBearish && engulfs && volumeConfirm;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable for trading                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(double maxSpreadPoints = 3.0)
{
   double spread = symbolInfo.Spread() * symbolInfo.Point();
   double maxSpread = maxSpreadPoints * symbolInfo.Point();
   return spread <= maxSpread;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on risk                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPercent, double stopLossPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * riskPercent / 100.0;
   
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();
   double point = symbolInfo.Point();
   
   // Calculate point value
   double pointValue = tickValue * point / tickSize;
   
   // Calculate lot size
   double lotSize = riskAmount / (stopLossPoints * pointValue);
   
   // Normalize lot size
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double stepLot = symbolInfo.LotsStep();
   
   lotSize = MathMax(minLot, lotSize);
   lotSize = MathMin(maxLot, lotSize);
   lotSize = MathRound(lotSize / stepLot) * stepLot;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Open buy order with improved risk management                   |
//+------------------------------------------------------------------+
bool OpenBuyOrder(double lotSize, double stopLossPoints, double takeProfitPoints)
{
   if(!IsSpreadAcceptable())
   {
      Print("Spread too wide for trading");
      return false;
   }
   
   double price = symbolInfo.Ask();
   double point = symbolInfo.Point();
   
   // Adjust for 5-digit brokers
   if(symbolInfo.Digits() == 5 || symbolInfo.Digits() == 3)
   {
      stopLossPoints *= 10;
      takeProfitPoints *= 10;
   }
   
   double sl = NormalizeDouble(price - stopLossPoints * point, symbolInfo.Digits());
   double tp = NormalizeDouble(price + takeProfitPoints * point, symbolInfo.Digits());
   
   // Validate levels
   double minStop = symbolInfo.StopsLevel() * point;
   if(price - sl < minStop || tp - price < minStop)
   {
      Print("Stop loss or take profit too close to market price");
      return false;
   }
   
   if(trade.Buy(lotSize, _Symbol, price, sl, tp, "ScalpBot Buy"))
   {
      Print("Buy order opened: Price=", price, " SL=", sl, " TP=", tp, " Lot=", lotSize);
      return true;
   }
   else
   {
      Print("Failed to open buy order. Error: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Open sell order with improved risk management                  |
//+------------------------------------------------------------------+
bool OpenSellOrder(double lotSize, double stopLossPoints, double takeProfitPoints)
{
   if(!IsSpreadAcceptable())
   {
      Print("Spread too wide for trading");
      return false;
   }
   
   double price = symbolInfo.Bid();
   double point = symbolInfo.Point();
   
   // Adjust for 5-digit brokers
   if(symbolInfo.Digits() == 5 || symbolInfo.Digits() == 3)
   {
      stopLossPoints *= 10;
      takeProfitPoints *= 10;
   }
   
   double sl = NormalizeDouble(price + stopLossPoints * point, symbolInfo.Digits());
   double tp = NormalizeDouble(price - takeProfitPoints * point, symbolInfo.Digits());
   
   // Validate levels
   double minStop = symbolInfo.StopsLevel() * point;
   if(sl - price < minStop || price - tp < minStop)
   {
      Print("Stop loss or take profit too close to market price");
      return false;
   }
   
   if(trade.Sell(lotSize, _Symbol, price, sl, tp, "ScalpBot Sell"))
   {
      Print("Sell order opened: Price=", price, " SL=", sl, " TP=", tp, " Lot=", lotSize);
      return true;
   }
   else
   {
      Print("Failed to open sell order. Error: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Close all positions for this EA                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MAGIC_NUMBER)
         {
            trade.PositionClose(positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions for this EA                                    |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MAGIC_NUMBER)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed at current time                    |
//+------------------------------------------------------------------+
bool IsTradingTimeAllowed()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Avoid trading during major news times (example: avoid first 30 min of major sessions)
   // You can customize this based on your requirements
   
   // Example: Trade only during London and New York sessions
   int hour = timeStruct.hour;
   
   // London session: 8-17 GMT, New York session: 13-22 GMT
   bool londonSession = (hour >= 8 && hour < 17);
   bool newYorkSession = (hour >= 13 && hour < 22);
   
   return londonSession || newYorkSession;
}