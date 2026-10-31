//+------------------------------------------------------------------+
//|                                                  ScalpingBot.mqh |
//|   Helper library for ScalpingBot v3.0                            |
//|   Indicators, regime detection, signal scoring, risk limits,     |
//|   order placement and position management.                       |
//+------------------------------------------------------------------+
#property copyright "ScalpingBot"

#include <Trade\Trade.mqh>

#define BOT_VERSION     "3.0"
#define TRAIL_STEP_ATR  0.10   // minimum SL improvement (in ATR) before we modify an order

//--- market regime
enum ENUM_REGIME
{
   REGIME_RANGE   = 0,   // sideways market  -> mean-reversion logic
   REGIME_NEUTRAL = 1,   // in between       -> trend logic, stricter score
   REGIME_TREND   = 2    // trending market  -> pullback logic
};

//--- all settings in one place (filled from the inputs in OnInit)
struct SBotConfig
{
   ENUM_TIMEFRAMES tf;
   ENUM_TIMEFRAMES htf;
   // position and risk
   double lots;
   double riskPercent;
   bool   allowMinLotOverRisk;
   int    maxPositions;
   long   magic;
   int    deviation;
   double maxMarginUsePct;
   // stop loss / take profit
   bool   useFixedSLTP;
   double slAtrMult;
   double tpAtrMult;
   int    fixedSLPoints;
   int    fixedTPPoints;
   // indicators
   int    emaPeriod;
   int    rsiPeriod;
   int    bbPeriod;
   double bbDev;
   int    atrPeriod;
   int    adxPeriod;
   int    htfEmaPeriod;
   // regime
   double adxTrend;
   double adxRange;
   // scoring
   int    minScore;
   double rsiOversold;
   double rsiOverbought;
   double rsiPullback;
   bool   useVolume;
   int    volLookback;
   // filters
   double maxSpreadAtrFrac;
   int    maxSpreadPoints;
   int    minAtrPoints;
   bool   useTimeFilter;
   int    startHour;
   int    endHour;
   // safety
   double maxDailyLossPct;
   int    maxConsecLosses;
   int    cooldownBars;
   int    maxHoldBars;
   // trade management
   bool   useBreakEven;
   double beTriggerAtr;
   int    beLockPoints;
   bool   useTrail;
   double trailAtr;
   // display
   bool   showDashboard;
   bool   verbose;
};

//--- everything the bot needs to know about the last CLOSED candles
struct SMarket
{
   double ema1;
   double rsi1, rsi2;
   double bbU1, bbM1, bbL1;
   double atr1;
   double adx1;
   double htfEma1, htfEma2, htfClose1;
   double o1, h1, l1, c1;      // last closed candle
   double o2, h2, l2, c2;      // the candle before it
   long   vol1;                // tick volume of last closed candle
   double volAvg;              // average tick volume of the candles before it
};

//--- result of scoring both directions
struct SScore
{
   int    buy;
   int    sell;
   int    needed;
   string buyWhy;
   string sellWhy;
};

//--- globals
SBotConfig cfg;
CTrade     trade;

int      emaHandle    = INVALID_HANDLE;
int      rsiHandle    = INVALID_HANDLE;
int      bbHandle     = INVALID_HANDLE;
int      atrHandle    = INVALID_HANDLE;
int      adxHandle    = INVALID_HANDLE;
int      htfEmaHandle = INVALID_HANDLE;

double   g_atr        = 0.0;        // ATR of the last closed candle
datetime g_lastBar    = 0;
string   g_status     = "Starting";
double   g_todayPnL   = 0.0;
int      g_streak     = 0;

//+------------------------------------------------------------------+
//| Setup / teardown                                                 |
//+------------------------------------------------------------------+
bool ValidateConfig()
{
   string err = "";

   if(cfg.lots <= 0.0 && cfg.riskPercent <= 0.0)
      err = "Set Lots > 0 or RiskPercent > 0";
   else if(cfg.maxPositions < 1)
      err = "MaxPositions must be at least 1";
   else if(cfg.minScore < 1 || cfg.minScore > 5)
      err = "MinScore must be between 1 and 5";
   else if(!cfg.useFixedSLTP && (cfg.slAtrMult <= 0.0 || cfg.tpAtrMult <= 0.0))
      err = "SLAtrMult and TPAtrMult must be above 0";
   else if(cfg.useFixedSLTP && (cfg.fixedSLPoints <= 0 || cfg.fixedTPPoints <= 0))
      err = "Fixed SL/TP points must be above 0";
   else if(cfg.adxRange > cfg.adxTrend)
      err = "AdxRange must not be above AdxTrend";
   else if(cfg.volLookback < 3)
      err = "VolLookback must be at least 3";
   else if(PeriodSeconds(cfg.htf) <= PeriodSeconds(cfg.tf))
      err = "Higher timeframe must be larger than the chart timeframe";

   if(err != "")
   {
      Print("ScalpingBot input error: ", err);
      return false;
   }

   if(cfg.lots <= 0.0 && cfg.riskPercent > 5.0)
      Print("ScalpingBot warning: RiskPercent above 5% is very aggressive");

   return true;
}

void ReleaseBot()
{
   if(emaHandle    != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(rsiHandle    != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(bbHandle     != INVALID_HANDLE) IndicatorRelease(bbHandle);
   if(atrHandle    != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(adxHandle    != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(htfEmaHandle != INVALID_HANDLE) IndicatorRelease(htfEmaHandle);
   emaHandle = rsiHandle = bbHandle = atrHandle = adxHandle = htfEmaHandle = INVALID_HANDLE;
}

bool InitBot()
{
   emaHandle    = iMA(_Symbol, cfg.tf,  cfg.emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle    = iRSI(_Symbol, cfg.tf, cfg.rsiPeriod, PRICE_CLOSE);
   bbHandle     = iBands(_Symbol, cfg.tf, cfg.bbPeriod, 0, cfg.bbDev, PRICE_CLOSE);
   atrHandle    = iATR(_Symbol, cfg.tf, cfg.atrPeriod);
   adxHandle    = iADX(_Symbol, cfg.tf, cfg.adxPeriod);
   htfEmaHandle = iMA(_Symbol, cfg.htf, cfg.htfEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(emaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || bbHandle == INVALID_HANDLE ||
      atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE || htfEmaHandle == INVALID_HANDLE)
   {
      Print("ScalpingBot: failed to create indicator handles. Error ", GetLastError());
      ReleaseBot();
      return false;
   }

   trade.SetExpertMagicNumber((ulong)cfg.magic);
   trade.SetDeviationInPoints((ulong)cfg.deviation);
   trade.SetTypeFillingBySymbol(_Symbol);
   return true;
}

//+------------------------------------------------------------------+
//| Market data                                                      |
//+------------------------------------------------------------------+
double Buf(const int handle, const int buffer, const int shift)
{
   double b[1];
   if(CopyBuffer(handle, buffer, shift, 1, b) != 1)
      return EMPTY_VALUE;
   return b[0];
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, cfg.tf, 0);
   if(t == 0)
      return false;
   if(t != g_lastBar)
   {
      g_lastBar = t;
      return true;
   }
   return false;
}

// Reads everything from CLOSED candles only (shift 1 and 2).
bool ReadMarket(SMarket &m)
{
   m.ema1    = Buf(emaHandle, 0, 1);
   m.rsi1    = Buf(rsiHandle, 0, 1);
   m.rsi2    = Buf(rsiHandle, 0, 2);
   m.bbM1    = Buf(bbHandle,  0, 1);
   m.bbU1    = Buf(bbHandle,  1, 1);
   m.bbL1    = Buf(bbHandle,  2, 1);
   m.atr1    = Buf(atrHandle, 0, 1);
   m.adx1    = Buf(adxHandle, 0, 1);
   m.htfEma1 = Buf(htfEmaHandle, 0, 1);
   m.htfEma2 = Buf(htfEmaHandle, 0, 2);

   if(m.ema1 == EMPTY_VALUE || m.rsi1 == EMPTY_VALUE || m.rsi2 == EMPTY_VALUE ||
      m.bbM1 == EMPTY_VALUE || m.bbU1 == EMPTY_VALUE || m.bbL1 == EMPTY_VALUE ||
      m.atr1 == EMPTY_VALUE || m.adx1 == EMPTY_VALUE ||
      m.htfEma1 == EMPTY_VALUE || m.htfEma2 == EMPTY_VALUE)
      return false;

   if(m.atr1 <= 0.0)
      return false;

   m.htfClose1 = iClose(_Symbol, cfg.htf, 1);
   if(m.htfClose1 <= 0.0)
      return false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int need = cfg.volLookback + 3;
   if(CopyRates(_Symbol, cfg.tf, 0, need, r) < need)
      return false;

   m.o1 = r[1].open;  m.h1 = r[1].high;  m.l1 = r[1].low;  m.c1 = r[1].close;
   m.o2 = r[2].open;  m.h2 = r[2].high;  m.l2 = r[2].low;  m.c2 = r[2].close;
   m.vol1 = r[1].tick_volume;

   double sum = 0.0;
   for(int i = 2; i < 2 + cfg.volLookback; i++)
      sum += (double)r[i].tick_volume;
   m.volAvg = sum / cfg.volLookback;

   return true;
}

//+------------------------------------------------------------------+
//| Regime and trend                                                 |
//+------------------------------------------------------------------+
string RegimeName(const ENUM_REGIME regime)
{
   if(regime == REGIME_TREND)
      return "TREND";
   if(regime == REGIME_RANGE)
      return "RANGE";
   return "NEUTRAL";
}

ENUM_REGIME GetRegime(const SMarket &m)
{
   if(m.adx1 >= cfg.adxTrend)
      return REGIME_TREND;
   if(m.adx1 <= cfg.adxRange)
      return REGIME_RANGE;
   return REGIME_NEUTRAL;
}

// +1 = higher timeframe going up, -1 = going down, 0 = flat / unclear
int HtfDirection(const SMarket &m)
{
   double slope = m.htfEma1 - m.htfEma2;
   double flat  = 0.02 * m.atr1;

   if(m.htfClose1 > m.htfEma1 && slope > flat)
      return 1;
   if(m.htfClose1 < m.htfEma1 && slope < -flat)
      return -1;
   return 0;
}

double BBPosition(const SMarket &m)
{
   double range = m.bbU1 - m.bbL1;
   if(range <= 0.0)
      return 0.5;
   return (m.c1 - m.bbL1) / range;   // 0 = lower band, 1 = upper band
}

//+------------------------------------------------------------------+
//| Candle patterns (on the last closed candle)                      |
//+------------------------------------------------------------------+
bool BullishEngulfing(const SMarket &m)
{
   return (m.c2 < m.o2) && (m.c1 > m.o1) && (m.c1 >= m.o2) && (m.o1 <= m.c2);
}

bool BearishEngulfing(const SMarket &m)
{
   return (m.c2 > m.o2) && (m.c1 < m.o1) && (m.c1 <= m.o2) && (m.o1 >= m.c2);
}

bool Hammer(const SMarket &m)
{
   double range = m.h1 - m.l1;
   if(range <= 0.0)
      return false;
   double body      = MathAbs(m.c1 - m.o1);
   double lowerWick = MathMin(m.o1, m.c1) - m.l1;
   return (lowerWick >= 2.0 * body) && (lowerWick >= 0.55 * range) && (m.c1 >= m.l1 + 0.6 * range);
}

bool ShootingStar(const SMarket &m)
{
   double range = m.h1 - m.l1;
   if(range <= 0.0)
      return false;
   double body      = MathAbs(m.c1 - m.o1);
   double upperWick = m.h1 - MathMax(m.o1, m.c1);
   return (upperWick >= 2.0 * body) && (upperWick >= 0.55 * range) && (m.c1 <= m.h1 - 0.6 * range);
}

//+------------------------------------------------------------------+
//| Signal scoring: 5 checks per direction, one point each           |
//|  1 HTF   higher timeframe agrees                                 |
//|  2 LOC   price is in the right place for this regime             |
//|  3 RSI   momentum is turning our way                             |
//|  4 CANDLE reversal candle (engulfing / hammer / shooting star)   |
//|  5 VOL   signal candle has at least average activity             |
//+------------------------------------------------------------------+
void ScoreSignals(const SMarket &m, const ENUM_REGIME regime, SScore &s)
{
   bool   trendLogic = (regime != REGIME_RANGE);
   int    htf        = HtfDirection(m);
   double bbPos      = BBPosition(m);
   double zone       = 0.25 * m.atr1;
   bool   volOK      = (!cfg.useVolume) || ((double)m.vol1 >= m.volAvg);

   // ---- BUY ----
   bool bHtf = trendLogic ? (htf == 1) : (htf >= 0);
   bool bLoc = trendLogic ? (m.l1 <= m.ema1 + zone && m.c1 > m.ema1)
                          : (bbPos <= 0.25);
   bool bRsi = trendLogic ? (m.rsi2 <= cfg.rsiPullback && m.rsi1 > m.rsi2)
                          : (m.rsi2 <= cfg.rsiOversold && m.rsi1 > m.rsi2);
   bool bCan = BullishEngulfing(m) || Hammer(m);

   s.buy = (bHtf ? 1 : 0) + (bLoc ? 1 : 0) + (bRsi ? 1 : 0) + (bCan ? 1 : 0) + (volOK ? 1 : 0);
   s.buyWhy = StringFormat("HTF%s LOC%s RSI%s CANDLE%s VOL%s",
                           bHtf ? "+" : "-", bLoc ? "+" : "-", bRsi ? "+" : "-",
                           bCan ? "+" : "-", volOK ? "+" : "-");

   // ---- SELL ----
   bool sHtf = trendLogic ? (htf == -1) : (htf <= 0);
   bool sLoc = trendLogic ? (m.h1 >= m.ema1 - zone && m.c1 < m.ema1)
                          : (bbPos >= 0.75);
   bool sRsi = trendLogic ? (m.rsi2 >= (100.0 - cfg.rsiPullback) && m.rsi1 < m.rsi2)
                          : (m.rsi2 >= cfg.rsiOverbought && m.rsi1 < m.rsi2);
   bool sCan = BearishEngulfing(m) || ShootingStar(m);

   s.sell = (sHtf ? 1 : 0) + (sLoc ? 1 : 0) + (sRsi ? 1 : 0) + (sCan ? 1 : 0) + (volOK ? 1 : 0);
   s.sellWhy = StringFormat("HTF%s LOC%s RSI%s CANDLE%s VOL%s",
                            sHtf ? "+" : "-", sLoc ? "+" : "-", sRsi ? "+" : "-",
                            sCan ? "+" : "-", volOK ? "+" : "-");

   // the in-between regime is the least reliable, so ask for one extra point
   s.needed = cfg.minScore + ((regime == REGIME_NEUTRAL) ? 1 : 0);
   if(s.needed > 5)
      s.needed = 5;
}

// +1 = buy, -1 = sell, 0 = do nothing
int Decide(const SScore &s)
{
   if(s.buy >= s.needed && s.buy > s.sell)
      return 1;
   if(s.sell >= s.needed && s.sell > s.buy)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Gates: situations where the bot must NOT open a trade            |
//+------------------------------------------------------------------+
bool TradingEnvironmentOK()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))   return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))    return false;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return false;
   return true;
}

bool TimeAllowed()
{
   if(cfg.startHour == cfg.endHour)
      return true;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);   // broker server time
   int h = t.hour;

   if(cfg.startHour < cfg.endHour)
      return (h >= cfg.startHour && h < cfg.endHour);
   return (h >= cfg.startHour || h < cfg.endHour);   // window wraps past midnight
}

int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == cfg.magic)
         n++;
   }
   return n;
}

datetime DayStart()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   d.hour = 0;
   d.min  = 0;
   d.sec  = 0;
   return StructToTime(d);
}

// Looks at this EA's closed deals (same magic number): today's result and the current losing streak.
void ReadHistoryStats(double &todayPnL, int &streak, datetime &lastLossTime)
{
   todayPnL     = 0.0;
   streak       = 0;
   lastLossTime = 0;

   if(!HistorySelect(TimeCurrent() - 7 * 86400, TimeCurrent() + 60))
      return;

   datetime dayStart   = DayStart();
   bool     streakOpen = true;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)   // newest first
   {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0)
         continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != cfg.magic)
         continue;

      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue;

      double pnl = HistoryDealGetDouble(tk, DEAL_PROFIT)
                 + HistoryDealGetDouble(tk, DEAL_SWAP)
                 + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      datetime t = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);

      if(t >= dayStart)
         todayPnL += pnl;

      if(streakOpen)
      {
         if(pnl < 0.0)
         {
            streak++;
            if(lastLossTime == 0)
               lastLossTime = t;
         }
         else
            streakOpen = false;
      }
   }
}

// Returns a reason text if a safety limit blocks trading, or "" if all is fine.
string RiskLimitReason()
{
   datetime lastLoss = 0;
   ReadHistoryStats(g_todayPnL, g_streak, lastLoss);

   if(cfg.maxDailyLossPct > 0.0 && g_todayPnL < 0.0)
   {
      double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - g_todayPnL;
      if(MathAbs(g_todayPnL) >= startBalance * cfg.maxDailyLossPct / 100.0)
         return "Daily loss limit reached - done for today";
   }

   if(cfg.maxConsecLosses > 0 && g_streak >= cfg.maxConsecLosses && lastLoss > 0)
   {
      datetime until = lastLoss + (datetime)(cfg.cooldownBars * PeriodSeconds(cfg.tf));
      if(TimeCurrent() < until)
         return "Cooling down after a losing streak";
   }
   return "";
}

string CheckGates(const SMarket &m)
{
   if(CountPositions() >= cfg.maxPositions)
      return "Max positions reached";
   if(!TradingEnvironmentOK())
      return "Trading not allowed (check AutoTrading and symbol)";
   if(cfg.useTimeFilter && !TimeAllowed())
      return "Outside trading hours";
   if(cfg.minAtrPoints > 0 && m.atr1 < cfg.minAtrPoints * _Point)
      return "Volatility (ATR) too low";

   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(cfg.maxSpreadPoints > 0 && spread > cfg.maxSpreadPoints * _Point)
      return "Spread above MaxSpreadPoints";
   if(cfg.maxSpreadAtrFrac > 0.0 && spread > cfg.maxSpreadAtrFrac * m.atr1)
      return "Spread too big compared with ATR";

   return RiskLimitReason();
}

//+------------------------------------------------------------------+
//| Position sizing and order placement                              |
//+------------------------------------------------------------------+
double CalcLots(const ENUM_ORDER_TYPE type, const double price, const double sl)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = minLot;

   double lots = cfg.lots;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * cfg.riskPercent / 100.0;
   double lossPerLot = 0.0;

   if(cfg.lots <= 0.0)
   {
      double profit = 0.0;
      if(!OrderCalcProfit(type, _Symbol, 1.0, price, sl, profit) || profit == 0.0)
      {
         Print("ScalpingBot: could not calculate risk per lot. Error ", GetLastError());
         return 0.0;
      }
      lossPerLot = MathAbs(profit);
      lots = riskMoney / lossPerLot;
   }

   lots = MathFloor(lots / step + 1e-9) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   lots = NormalizeDouble(lots, digits);

   // the smallest allowed lot may risk more than we wanted - don't do that silently
   if(cfg.lots <= 0.0 && !cfg.allowMinLotOverRisk && lots * lossPerLot > riskMoney * 2.0)
   {
      Print("ScalpingBot: skipped trade. Smallest lot would risk ", DoubleToString(lots * lossPerLot, 2),
            " but the limit is ", DoubleToString(riskMoney, 2),
            ". Raise RiskPercent or set AllowMinLotOverRisk=true.");
      return 0.0;
   }
   return lots;
}

bool MarginOK(const ENUM_ORDER_TYPE type, const double lots, const double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin))
      return false;
   return margin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * cfg.maxMarginUsePct / 100.0;
}

bool OpenTrade(const bool isBuy, const double atr, const string note)
{
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = isBuy ? ask : bid;

   double slDist, tpDist;
   if(cfg.useFixedSLTP)
   {
      slDist = cfg.fixedSLPoints * _Point;
      tpDist = cfg.fixedTPPoints * _Point;
   }
   else
   {
      slDist = atr * cfg.slAtrMult;
      tpDist = atr * cfg.tpAtrMult;
   }

   // never closer than the broker allows (plus the spread as a cushion)
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + (ask - bid);
   slDist = MathMax(slDist, minDist);
   tpDist = MathMax(tpDist, minDist);

   double sl = NormalizeDouble(isBuy ? price - slDist : price + slDist, _Digits);
   double tp = NormalizeDouble(isBuy ? price + tpDist : price - tpDist, _Digits);

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lots = CalcLots(type, price, sl);
   if(lots <= 0.0)
      return false;

   if(!MarginOK(type, lots, price))
   {
      Print("ScalpingBot: not enough free margin for ", DoubleToString(lots, 2), " lots");
      return false;
   }

   bool ok = isBuy ? trade.Buy(lots, _Symbol, price, sl, tp, "ScalpBot")
                   : trade.Sell(lots, _Symbol, price, sl, tp, "ScalpBot");

   if(ok)
      Print("ScalpingBot ", (isBuy ? "BUY" : "SELL"), " opened | lots ", DoubleToString(lots, 2),
            " | SL ", DoubleToString(sl, _Digits), " TP ", DoubleToString(tp, _Digits), " | ", note);
   else
      Print("ScalpingBot: order failed. Code ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());

   return ok;
}

//+------------------------------------------------------------------+
//| Open position management: time stop, break-even, ATR trailing    |
//+------------------------------------------------------------------+
void ManagePositions(const double atr)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != cfg.magic)
         continue;

      bool     isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      double   tp     = PositionGetDouble(POSITION_TP);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);

      // 1) time stop: a scalp that goes nowhere is closed
      if(cfg.maxHoldBars > 0 && (long)(TimeCurrent() - opened) >= (long)cfg.maxHoldBars * PeriodSeconds(cfg.tf))
      {
         if(trade.PositionClose(ticket))
            Print("ScalpingBot: position closed by time stop");
         continue;
      }

      double price      = isBuy ? bid : ask;
      double profitDist = isBuy ? (price - open) : (open - price);
      double newSL      = sl;

      if(profitDist >= cfg.beTriggerAtr * atr)
      {
         // 2) break-even (+ a few points to cover costs)
         if(cfg.useBreakEven)
         {
            double be = isBuy ? open + cfg.beLockPoints * _Point : open - cfg.beLockPoints * _Point;
            if(isBuy ? (be > newSL) : (newSL == 0.0 || be < newSL))
               newSL = be;
         }
         // 3) ATR trailing stop
         if(cfg.useTrail)
         {
            double t = isBuy ? price - cfg.trailAtr * atr : price + cfg.trailAtr * atr;
            if(isBuy ? (t > newSL) : (newSL == 0.0 || t < newSL))
               newSL = t;
         }
      }

      newSL = NormalizeDouble(newSL, _Digits);
      if(newSL == 0.0 || newSL == sl)
         continue;
      // the first move out of the loss zone is always allowed; after that,
      // only move the stop when it improves by a meaningful step
      bool slOnLossSide = (sl == 0.0) || (isBuy ? (sl < open) : (sl > open));
      if(!slOnLossSide && MathAbs(newSL - sl) < TRAIL_STEP_ATR * atr)
         continue;

      bool valid = isBuy ? (newSL < price - minDist && (sl == 0.0 || newSL > sl))
                         : (newSL > price + minDist && (sl == 0.0 || newSL < sl));
      if(!valid)
         continue;

      if(trade.PositionModify(ticket, newSL, tp) && cfg.verbose)
         Print("ScalpingBot: stop moved to ", DoubleToString(newSL, _Digits));
   }
}

//+------------------------------------------------------------------+
//| On-chart status panel                                            |
//+------------------------------------------------------------------+
void ShowDashboard(const SMarket &m, const ENUM_REGIME regime, const SScore &s)
{
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;

   int    htf    = HtfDirection(m);
   string htfTxt = (htf > 0) ? "UP" : ((htf < 0) ? "DOWN" : "FLAT");
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string txt = "ScalpingBot v" + BOT_VERSION + "  |  " + _Symbol + "  " + EnumToString(cfg.tf) + "\n";
   txt += "Regime: " + RegimeName(regime) + "  (ADX " + DoubleToString(m.adx1, 1) + ")\n";
   txt += "Higher timeframe: " + htfTxt + "\n";
   txt += "Score  BUY " + IntegerToString(s.buy) + "/5   SELL " + IntegerToString(s.sell) +
          "/5   (needs " + IntegerToString(s.needed) + ")\n";
   txt += "ATR " + DoubleToString(m.atr1, _Digits) + "   Spread " + DoubleToString(spread, _Digits) + "\n";
   txt += "Today P/L " + DoubleToString(g_todayPnL, 2) + "   Loss streak " + IntegerToString(g_streak) + "\n";
   txt += "Status: " + g_status + "\n";
   Comment(txt);
}
