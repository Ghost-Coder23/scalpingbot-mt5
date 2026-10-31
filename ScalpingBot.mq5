//+------------------------------------------------------------------+
//|                                                  ScalpingBot.mq5 |
//|   v3.0 - regime-aware, score-based scalping EA                   |
//|   Put ScalpingBot.mq5 and ScalpingBot.mqh in the SAME folder.    |
//+------------------------------------------------------------------+
#property copyright   "ScalpingBot"
#property version     "3.00"
#property description "Regime-aware scalping EA: trend/range detection, signal scoring,"
#property description "ATR-based risk, break-even + trailing, daily loss and streak limits."

#include "ScalpingBot.mqh"

//--- Position & risk -------------------------------------------------
input group "=== Position & Risk ==="
input double InpLots                = 0.0;     // Fixed lot size (0 = size by risk %)
input double InpRiskPercent         = 1.0;     // Risk per trade, % of balance (used when Lots = 0)
input bool   InpAllowMinLotOverRisk = false;   // Trade even if the smallest lot risks > 2x the limit
input int    InpMaxPositions        = 1;       // Max open positions for this EA
input long   InpMagic               = 20260101;// Magic number (use a different one per chart)
input int    InpDeviation           = 30;      // Max slippage in points
input double InpMaxMarginUsePct     = 50.0;    // Skip trade if it needs more than this % of free margin

//--- Stop loss / take profit -----------------------------------------
input group "=== Stop Loss / Take Profit ==="
input bool   InpUseFixedSLTP        = false;   // false = ATR based, true = fixed points
input double InpSLAtrMult           = 1.5;     // Stop loss = ATR x this
input double InpTPAtrMult           = 2.5;     // Take profit = ATR x this
input int    InpFixedSLPoints       = 500;     // Fixed SL in points (only if fixed mode)
input int    InpFixedTPPoints       = 800;     // Fixed TP in points (only if fixed mode)

//--- Indicators -------------------------------------------------------
input group "=== Indicators ==="
input ENUM_TIMEFRAMES InpHigherTF   = PERIOD_M15; // Higher timeframe for trend bias
input int    InpEMAPeriod           = 20;      // EMA period (chart timeframe)
input int    InpRSIPeriod           = 14;      // RSI period
input int    InpBBPeriod            = 20;      // Bollinger Bands period
input double InpBBDeviation         = 2.0;     // Bollinger Bands deviation
input int    InpATRPeriod           = 14;      // ATR period
input int    InpADXPeriod           = 14;      // ADX period
input int    InpHTFEmaPeriod        = 20;      // EMA period on the higher timeframe

//--- Regime -----------------------------------------------------------
input group "=== Market Regime (ADX) ==="
input double InpAdxTrend            = 25.0;    // ADX at or above = TREND market
input double InpAdxRange            = 20.0;    // ADX at or below = RANGE market

//--- Scoring ----------------------------------------------------------
input group "=== Signal Scoring ==="
input int    InpMinScore            = 4;       // Points needed out of 5 (+1 in NEUTRAL regime)
input double InpRsiOversold         = 35.0;    // Range mode: RSI buy zone
input double InpRsiOverbought       = 65.0;    // Range mode: RSI sell zone
input double InpRsiPullback         = 50.0;    // Trend mode: RSI must have dipped to this (sells use 100 - this)
input bool   InpUseVolume           = true;    // Use tick-volume check (off = counts as passed)
input int    InpVolLookback         = 10;      // Candles used for average volume

//--- Filters ----------------------------------------------------------
input group "=== Filters ==="
input double InpMaxSpreadAtrFrac    = 0.25;    // Skip if spread > this fraction of ATR (0 = off)
input int    InpMaxSpreadPoints     = 0;       // Skip if spread > this many points (0 = off)
input int    InpMinAtrPoints        = 0;       // Skip if ATR < this many points (0 = off)
input bool   InpUseTimeFilter       = false;   // Only trade inside the hours below
input int    InpStartHour           = 0;       // Start hour (broker server time)
input int    InpEndHour             = 24;      // End hour (broker server time)

//--- Safety -----------------------------------------------------------
input group "=== Safety Limits ==="
input double InpMaxDailyLossPct     = 3.0;     // Stop for the day after losing this % (0 = off)
input int    InpMaxConsecLosses     = 3;       // Pause after this many losses in a row (0 = off)
input int    InpCooldownBars        = 12;      // How many candles to pause
input int    InpMaxHoldBars         = 24;      // Close a trade older than this many candles (0 = off)

//--- Trade management -------------------------------------------------
input group "=== Trade Management ==="
input bool   InpUseBreakEven        = true;    // Move SL to break-even once in profit
input double InpBETriggerAtr        = 1.0;     // ...when profit reaches ATR x this
input int    InpBELockPoints        = 5;       // ...and lock this many points of profit
input bool   InpUseTrail            = true;    // ATR trailing stop after the trigger
input double InpTrailAtr            = 1.0;     // Trail distance = ATR x this

//--- Display ----------------------------------------------------------
input group "=== Display ==="
input bool   InpShowDashboard       = true;    // Show status panel on the chart
input bool   InpVerbose             = false;   // Print every bar's decision to the Experts log

//+------------------------------------------------------------------+
int OnInit()
{
   cfg.tf                  = _Period;
   cfg.htf                 = InpHigherTF;

   cfg.lots                = InpLots;
   cfg.riskPercent         = InpRiskPercent;
   cfg.allowMinLotOverRisk = InpAllowMinLotOverRisk;
   cfg.maxPositions        = InpMaxPositions;
   cfg.magic               = InpMagic;
   cfg.deviation           = InpDeviation;
   cfg.maxMarginUsePct     = InpMaxMarginUsePct;

   cfg.useFixedSLTP        = InpUseFixedSLTP;
   cfg.slAtrMult           = InpSLAtrMult;
   cfg.tpAtrMult           = InpTPAtrMult;
   cfg.fixedSLPoints       = InpFixedSLPoints;
   cfg.fixedTPPoints       = InpFixedTPPoints;

   cfg.emaPeriod           = InpEMAPeriod;
   cfg.rsiPeriod           = InpRSIPeriod;
   cfg.bbPeriod            = InpBBPeriod;
   cfg.bbDev               = InpBBDeviation;
   cfg.atrPeriod           = InpATRPeriod;
   cfg.adxPeriod           = InpADXPeriod;
   cfg.htfEmaPeriod        = InpHTFEmaPeriod;

   cfg.adxTrend            = InpAdxTrend;
   cfg.adxRange            = InpAdxRange;

   cfg.minScore            = InpMinScore;
   cfg.rsiOversold         = InpRsiOversold;
   cfg.rsiOverbought       = InpRsiOverbought;
   cfg.rsiPullback         = InpRsiPullback;
   cfg.useVolume           = InpUseVolume;
   cfg.volLookback         = InpVolLookback;

   cfg.maxSpreadAtrFrac    = InpMaxSpreadAtrFrac;
   cfg.maxSpreadPoints     = InpMaxSpreadPoints;
   cfg.minAtrPoints        = InpMinAtrPoints;
   cfg.useTimeFilter       = InpUseTimeFilter;
   cfg.startHour           = InpStartHour;
   cfg.endHour             = InpEndHour;

   cfg.maxDailyLossPct     = InpMaxDailyLossPct;
   cfg.maxConsecLosses     = InpMaxConsecLosses;
   cfg.cooldownBars        = InpCooldownBars;
   cfg.maxHoldBars         = InpMaxHoldBars;

   cfg.useBreakEven        = InpUseBreakEven;
   cfg.beTriggerAtr        = InpBETriggerAtr;
   cfg.beLockPoints        = InpBELockPoints;
   cfg.useTrail            = InpUseTrail;
   cfg.trailAtr            = InpTrailAtr;

   cfg.showDashboard       = InpShowDashboard;
   cfg.verbose             = InpVerbose;

   if(!ValidateConfig())
      return INIT_PARAMETERS_INCORRECT;
   if(!InitBot())
      return INIT_FAILED;

   if(cfg.tf != PERIOD_M5)
      Print("ScalpingBot: designed for M5 - you are on ", EnumToString(cfg.tf), ". Defaults may need retuning.");

   Print("ScalpingBot v", BOT_VERSION, " started on ", _Symbol, " ", EnumToString(cfg.tf),
         " | higher TF ", EnumToString(cfg.htf), " | magic ", cfg.magic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ReleaseBot();
   Comment("");
   Print("ScalpingBot stopped. Reason code: ", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Between candles we only look after the trade that is already open.
   if(!IsNewBar())
   {
      if(g_atr > 0.0)
         ManagePositions(g_atr);
      return;
   }

   // A new candle just opened: decide using the candles that are now CLOSED.
   SMarket m;
   if(!ReadMarket(m))
   {
      g_lastBar = 0;   // indicators not ready yet - try again on the next tick
      return;
   }

   g_atr = m.atr1;
   ManagePositions(g_atr);

   ENUM_REGIME regime = GetRegime(m);
   SScore s;
   ScoreSignals(m, regime, s);

   string blocked = CheckGates(m);
   int signal = (blocked == "") ? Decide(s) : 0;

   if(signal == 1)
   {
      string note = "regime " + RegimeName(regime) + " | score " + IntegerToString(s.buy) + "/5 | " + s.buyWhy;
      g_status = OpenTrade(true, m.atr1, note) ? "BUY opened" : "BUY signal, order not placed";
   }
   else if(signal == -1)
   {
      string note = "regime " + RegimeName(regime) + " | score " + IntegerToString(s.sell) + "/5 | " + s.sellWhy;
      g_status = OpenTrade(false, m.atr1, note) ? "SELL opened" : "SELL signal, order not placed";
   }
   else
      g_status = (blocked != "") ? blocked : "Waiting for a setup";

   if(cfg.verbose)
      Print("Bar | ", RegimeName(regime), " | BUY ", s.buy, " (", s.buyWhy, ") | SELL ", s.sell,
            " (", s.sellWhy, ") | need ", s.needed, " | ", g_status);

   if(cfg.showDashboard)
      ShowDashboard(m, regime, s);
}
//+------------------------------------------------------------------+
