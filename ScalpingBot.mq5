//+------------------------------------------------------------------+
//|                                              ImprovedScalpingBot.mq5 |
//|                        Copyright 2024, Your Name                |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.mql5.com"
#property version   "2.00"

#include "ImprovedScalpingBot.mqh"

// Input parameters
input group "=== Trading Parameters ==="
input double Lots = 0.01;                    // Fixed lot size (0 = auto calculation)
input double RiskPercent = 1.0;              // Risk per trade (% of account)
input int StopLoss = 20;                     // Stop loss in points
input int TakeProfit = 40;                   // Take profit in points
input double MaxSpreadPoints = 3.0;          // Maximum spread in points

input group "=== Indicator Settings ==="
input int RSIPeriod = 14;                    // RSI period
input int EMAPeriod = 20;                    // EMA period  
input int BBPeriod = 20;                     // Bollinger Bands period

input group "=== Risk Management ==="
input int MaxPositions = 1;                  // Maximum open positions
input bool UseTrailingStop = true;           // Use trailing stop
input int TrailingStop = 15;                 // Trailing stop in points
input int TrailingStep = 5;                  // Trailing step in points

input group "=== Advanced Filters ==="
input bool UseTimeFilter = true;             // Use time filter
input bool UseATRFilter = true;              // Use ATR volatility filter
input int ATRPeriod = 14;                    // ATR period
input double ATRMultiplier = 1.5;            // ATR multiplier for volatility

// Global variables
datetime lastBarTime = 0;
int atrHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Improved ScalpingBot v2.0 initializing...");
   
   // Initialize indicators
   if(!InitializeIndicators(EMAPeriod, RSIPeriod, BBPeriod))
   {
      Print("Failed to initialize indicators");
      return(INIT_FAILED);
   }
   
   // Initialize ATR if using ATR filter
   if(UseATRFilter)
   {
      atrHandle = iATR(_Symbol, PERIOD_M5, ATRPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle");
         return(INIT_FAILED);
      }
   }
   
   // Set up chart
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, true);
   
   Print("ScalpingBot initialized successfully");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: M5");
   Print("Risk per trade: ", RiskPercent, "%");
   Print("Max positions: ", MaxPositions);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupIndicators();
   
   if(UseATRFilter && atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
      
   Print("ScalpingBot deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get ATR value                                                   |
//+------------------------------------------------------------------+
double GetATR(int shift = 0)
{
   if(!UseATRFilter) return 0.0;
   
   double buffer[1];
   if(CopyBuffer(atrHandle, 0, shift, 1, buffer) <= 0)
   {
      Print("Failed to copy ATR buffer");
      return 0.0;
   }
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Check volatility using ATR                                     |
//+------------------------------------------------------------------+
bool IsVolatilityAcceptable()
{
   if(!UseATRFilter) return true;
   
   double atr = GetATR();
   if(atr <= 0) return false;
   
   double currentSpread = symbolInfo.Spread() * symbolInfo.Point();
   double minVolatility = currentSpread * ATRMultiplier;
   
   return atr >= minVolatility;
}

//+------------------------------------------------------------------+
//| Manage trailing stop                                           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!UseTrailingStop) return;
   
   double point = symbolInfo.Point();
   double trailStop = TrailingStop * point;
   double trailStep = TrailingStep * point;
   
   // Adjust for 5-digit brokers
   if(symbolInfo.Digits() == 5 || symbolInfo.Digits() == 3)
   {
      trailStop *= 10;
      trailStep *= 10;
   }
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != MAGIC_NUMBER) continue;
      
      double currentPrice = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? 
                           symbolInfo.Bid() : symbolInfo.Ask();
      double currentSL = positionInfo.StopLoss();
      double openPrice = positionInfo.PriceOpen();
      
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(currentPrice - trailStop, symbolInfo.Digits());
         
         if(newSL > currentSL + trailStep || currentSL == 0)
         {
            if(newSL > openPrice) // Only move SL to profit
            {
               trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit());
               Print("Trailing stop updated for BUY position. New SL: ", newSL);
            }
         }
      }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(currentPrice + trailStop, symbolInfo.Digits());
         
         if(newSL < currentSL - trailStep || currentSL == 0)
         {
            if(newSL < openPrice) // Only move SL to profit
            {
               trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit());
               Print("Trailing stop updated for SELL position. New SL: ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Enhanced signal validation                                      |
//+------------------------------------------------------------------+
bool ValidateBuySignal(double price, double ema, double rsi, double bbUpper, double bbLower)
{
   // Basic conditions
   if(!(price > ema && rsi < 35 && price <= bbLower + (bbUpper - bbLower) * 0.2))
      return false;
   
   // Check if bullish engulfing pattern exists
   if(!IsBullishEngulfing())
      return false;
   
   // Additional confirmation: Price should be in lower 30% of BB range
   double bbRange = bbUpper - bbLower;
   double pricePosition = (price - bbLower) / bbRange;
   if(pricePosition > 0.3)
      return false;
   
   // RSI should be recovering from oversold
   double rsiPrev = GetRSI(1);
   if(rsiPrev == EMPTY_VALUE || rsi <= rsiPrev)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Enhanced signal validation for sell                            |
//+------------------------------------------------------------------+
bool ValidateSellSignal(double price, double ema, double rsi, double bbUpper, double bbLower)
{
   // Basic conditions  
   if(!(price < ema && rsi > 65 && price >= bbUpper - (bbUpper - bbLower) * 0.2))
      return false;
   
   // Check if bearish engulfing pattern exists
   if(!IsBearishEngulfing())
      return false;
   
   // Additional confirmation: Price should be in upper 30% of BB range
   double bbRange = bbUpper - bbLower;
   double pricePosition = (price - bbLower) / bbRange;
   if(pricePosition < 0.7)
      return false;
   
   // RSI should be falling from overbought
   double rsiPrev = GetRSI(1);
   if(rsiPrev == EMPTY_VALUE || rsi >= rsiPrev)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only trade on new bar formation
   if(!IsNewBar())
   {
      ManageTrailingStop(); // Still manage trailing stops on every tick
      return;
   }
   
   // Check if we have reached maximum positions
   if(CountPositions() >= MaxPositions)
      return;
   
   // Check time filter
   if(UseTimeFilter && !IsTradingTimeAllowed())
      return;
   
   // Check volatility filter
   if(!IsVolatilityAcceptable())
   {
      Print("Volatility too low for trading");
      return;
   }
   
   // Check spread
   if(!IsSpreadAcceptable(MaxSpreadPoints))
   {
      Print("Spread too wide: ", symbolInfo.Spread() * symbolInfo.Point());
      return;
   }
   
   // Get current price
   double price = symbolInfo.Bid();
   
   // Calculate indicators
   double ema = GetEMA();
   double rsi = GetRSI();
   double bbUpper, bbMiddle, bbLower;
   
   if(ema == EMPTY_VALUE || rsi == EMPTY_VALUE || !GetBollingerBands(bbUpper, bbMiddle, bbLower))
   {
      Print("Failed to get indicator values");
      return;
   }
   
   // Check MTF trend confirmation
   bool uptrendMTF = IsUptrendMTF();
   
   // Calculate lot size
   double lotSize = Lots;
   if(Lots <= 0)
   {
      lotSize = CalculateLotSize(RiskPercent, StopLoss);
      Print("Calculated lot size: ", lotSize);
   }
   
   // Look for buy signal
   if(uptrendMTF && ValidateBuySignal(price, ema, rsi, bbUpper, bbLower))
   {
      if(OpenBuyOrder(lotSize, StopLoss, TakeProfit))
      {
         Print("BUY signal executed:");
         Print("Price: ", price, " EMA: ", ema, " RSI: ", rsi);
         Print("BB Upper: ", bbUpper, " BB Lower: ", bbLower);
      }
   }
   // Look for sell signal  
   else if(!uptrendMTF && ValidateSellSignal(price, ema, rsi, bbUpper, bbLower))
   {
      if(OpenSellOrder(lotSize, StopLoss, TakeProfit))
      {
         Print("SELL signal executed:");
         Print("Price: ", price, " EMA: ", ema, " RSI: ", rsi);
         Print("BB Upper: ", bbUpper, " BB Lower: ", bbLower);
      }
   }
}

//+------------------------------------------------------------------+
//| Timer function for additional management                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   // This can be used for additional periodic checks
   // Set timer in OnInit() if needed: EventSetTimer(60); // 60 seconds
}

//+------------------------------------------------------------------+
//| Handle trade events                                             |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Log trade results for analysis
   static datetime lastTradeTime = 0;
   datetime currentTime = TimeCurrent();
   
   if(currentTime != lastTradeTime)
   {
      lastTradeTime = currentTime;
      
      // You can add trade logging or notification logic here
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      Print("Trade event - Equity: ", equity, " Balance: ", balance);
   }
}