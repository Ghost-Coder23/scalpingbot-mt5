//+------------------------------------------------------------------+
//|  EASniper.mq5   v1.00                                            |
//|  Supply/demand zone signal advisor + optional auto-trading.      |
//|                                                                  |
//|  SETUP                                                           |
//|  1. Copy to MQL5/Experts, open in MetaEditor, press Compile.     |
//|  2. Attach to ONE chart per symbol (e.g. XAUUSD M5).             |
//|  3. Keep InpAutoTrade = false first. It then only advises.       |
//|  4. Telegram: Tools > Options > Expert Advisors > allow WebRequest|
//|     for https://api.telegram.org and fill token + chat id.       |
//|  5. Read the stats panel (top-left): it replays the chart        |
//|     history with these rules and says if there is an edge.       |
//|                                                                  |
//|  PRESETS (inputs)                                                |
//|  Scalp : chart M5,  InpHTF=H1, InpRR=1.5, InpMaxHoldBars=48      |
//|  Swing : chart H1,  InpHTF=D1, InpRR=2.5, InpMaxHoldBars=120     |
//+------------------------------------------------------------------+
#property copyright "EASniper"
#property version   "1.00"
#property description "Zones + scored signals + exit rules + stats panel + alerts"

#include <Trade\Trade.mqh>

#define PFX "EAS_"

//--- inputs
input group "=== Signal rules ==="
input int             InpWarmupBars   = 5000;      // History bars to replay
input int             InpATRPeriod    = 14;        // ATR period
input int             InpATRSlow      = 100;       // Slow ATR (market calm/busy check)
input double          InpImpulseATR   = 1.3;       // Impulse candle size (x ATR) that creates a zone
input int             InpBreakLookback= 5;         // Impulse must break the last N bars' high/low
input double          InpReactATR     = 1.0;       // Bounce size (x ATR) that counts as a reaction
input int             InpMaxZoneAge   = 1500;      // Zone expires after N bars
input ENUM_TIMEFRAMES InpHTF          = PERIOD_H1; // Big-picture timeframe for trend
input int             InpHTFEma       = 50;        // EMA period on that big timeframe
input bool            InpRequireTrend = true;      // Only trade with the big trend
input int             InpMinScore     = 7;         // Minimum score (out of 10) to show a signal
input int             InpMinGapBars   = 3;         // Min bars between signals

input group "=== Stop / target / exit ==="
input double          InpSLBufferATR  = 0.2;       // Stop buffer beyond the zone (x ATR)
input double          InpMinRiskATR   = 0.5;       // Smallest allowed stop (x ATR)
input double          InpMaxRiskATR   = 3.0;       // Skip signal if stop wider than this (x ATR)
input double          InpRR           = 1.5;       // Target = RR x risk
input bool            InpSoftExit     = true;      // Exit if big trend turns against the trade
input int             InpMaxHoldBars  = 48;        // Time stop (bars)

input group "=== Session (server time) ==="
input bool            InpUseSession   = false;     // Only signal inside session hours
input int             InpSessStart    = 7;         // Start hour
input int             InpSessEnd      = 20;        // End hour

input group "=== Alerts ==="
input bool            InpAlertPopup   = true;      // Pop-up + sound
input bool            InpAlertPush    = false;     // Push to phone (set MetaQuotes ID in terminal)
input bool            InpAlertTelegram= false;     // Telegram message
input string          InpTgToken      = "";        // Telegram bot token
input string          InpTgChat       = "";        // Telegram chat id

input group "=== Auto-trading (OFF by default) ==="
input bool            InpAutoTrade    = false;     // Place real orders
input double          InpRiskPct      = 1.0;       // Risk per trade (% of equity)
input double          InpDailyLossPct = 3.0;       // Stop opening trades after this daily loss (%)
input int             InpMaxSpreadPts = 0;         // Skip if spread above this (points). 0 = off
input long            InpMagic        = 770011;    // Magic number

input group "=== Display / verdict ==="
input int             InpDrawTrades   = 8;         // Past trades to draw
input int             InpMaxZonesShown= 10;        // Zones to draw
input color           InpDemandClr    = clrSeaGreen;
input color           InpSupplyClr    = clrIndianRed;
input int             InpMinTradesProof = 30;      // Trades needed before verdict means anything
input double          InpMinPF        = 1.3;       // Profit factor needed for "edge"
input double          InpTargetWin    = 70.0;      // Your win-rate target (%), shown on panel

//--- types
struct SZone
{
   int    dir;          // +1 demand, -1 supply
   double lo, hi;
   int    startIdx;
   int    touches;
   int    bounces;
   bool   inside;
   bool   pend;
   double pendATR;
};

struct SSignal
{
   int    dir;
   int    score;
   double entry, sl, tp, risk;
   string reason;
};

struct STrade
{
   int    dir;
   int    openIdx;
   double entry, sl, tp, risk;
   int    score;
   bool   real;
};

struct SDone
{
   int      dir;
   datetime t0, t1;
   double   entry, sl, tp, exitPrice, r;
};

//--- engine state
datetime g_time[];
double   g_open[], g_high[], g_low[], g_close[], g_atr[], g_atrS[], g_ema[];
int      g_trend[];
int      g_nb = 0;

double   g_prevClose = 0, g_atrV = 0, g_atrSV = 0, g_emaV = 0, g_alpha = 0;
int      g_ratio = 1, g_emaPeriod = 50, g_minBars = 150;

SZone    g_zones[];
int      g_zn = 0;

STrade   g_open_t;
bool     g_hasOpen = false;
int      g_lastSigIdx = -1000;
string   g_lastReason = "none yet";

SDone    g_done[];

int      g_nTrades = 0, g_nWins = 0, g_streak = 0, g_maxStreak = 0;
double   g_sumWin = 0, g_sumLoss = 0;

datetime g_lastProc = 0, g_lastBar = 0;
bool     g_warm = false, g_live = false, g_draw = true;
double   g_costPrice = 0;

int      g_dayKey = 0;
double   g_dayStartEq = 0;

CTrade   trade;

//+------------------------------------------------------------------+
void ResetEngine()
{
   g_nb = 0;
   ArrayResize(g_time,0); ArrayResize(g_open,0); ArrayResize(g_high,0); ArrayResize(g_low,0);
   ArrayResize(g_close,0); ArrayResize(g_atr,0); ArrayResize(g_atrS,0); ArrayResize(g_ema,0);
   ArrayResize(g_trend,0);
   ArrayResize(g_zones,0); g_zn = 0;
   ArrayResize(g_done,0);
   g_hasOpen = false; g_lastSigIdx = -1000; g_lastReason = "none yet";
   g_nTrades = 0; g_nWins = 0; g_streak = 0; g_maxStreak = 0; g_sumWin = 0; g_sumLoss = 0;
   g_prevClose = 0; g_atrV = 0; g_atrSV = 0; g_emaV = 0;
}

//+------------------------------------------------------------------+
bool SessionOK(datetime t)
{
   if(!InpUseSession) return true;
   MqlDateTime d;
   TimeToStruct(t, d);
   if(InpSessStart <= InpSessEnd) return (d.hour >= InpSessStart && d.hour < InpSessEnd);
   return (d.hour >= InpSessStart || d.hour < InpSessEnd);
}

string TFName()
{
   return StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
}

string P(double v) { return DoubleToString(v, _Digits); }

//+------------------------------------------------------------------+
string UrlEncode(string s)
{
   uchar ch[];
   int n = StringToCharArray(s, ch, 0, WHOLE_ARRAY, CP_UTF8);
   string out = "";
   for(int i = 0; i < n - 1; i++)
   {
      uchar c = ch[i];
      if((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.')
         out += CharToString(c);
      else
         out += StringFormat("%%%02X", c);
   }
   return out;
}

void SendTelegram(string text)
{
   if(InpTgToken == "" || InpTgChat == "") return;
   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + InpTgChat + "&text=" + UrlEncode(text);
   char post[], res[];
   string rh;
   int n = StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   ArrayResize(post, n);
   ResetLastError();
   int code = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, post, res, rh);
   if(code != 200)
      Print("EASniper: Telegram failed. HTTP ", code, " error ", GetLastError(), " (allow the URL in Tools>Options>Expert Advisors)");
}

void Notify(string msg)
{
   if(MQLInfoInteger(MQL_TESTER)) { Print(msg); return; }
   Print(msg);
   if(InpAlertPopup)    Alert(msg);
   if(InpAlertPush)     SendNotification(msg);
   if(InpAlertTelegram) SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| Real trading helpers                                             |
//+------------------------------------------------------------------+
bool HavePosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void CloseRealPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(tk);
   }
}

bool DailyLossHit()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int key = dt.year * 10000 + dt.mon * 100 + dt.day;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(key != g_dayKey) { g_dayKey = key; g_dayStartEq = eq; }
   return (eq <= g_dayStartEq * (1.0 - InpDailyLossPct / 100.0));
}

double CalcLots(double riskPrice)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickVal <= 0) return 0;
   double lossPerLot = riskPrice / tickSize * tickVal;
   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lossPerLot <= 0) return 0;
   double lots = riskMoney / lossPerLot;
   if(step > 0) lots = MathFloor(lots / step) * step;
   if(lots < vmin)
   {
      if(vmin * lossPerLot > riskMoney * 2.0)
      {
         Print("EASniper: skipped trade. Smallest lot would risk ", DoubleToString(vmin * lossPerLot, 2),
               " but allowed risk is ", DoubleToString(riskMoney, 2));
         return 0;
      }
      lots = vmin;
   }
   if(lots > vmax) lots = vmax;
   return NormalizeDouble(lots, 3);
}

bool TryOpenReal(const SSignal &sg)
{
   if(!InpAutoTrade) return false;
   if(HavePosition()) return false;
   if(DailyLossHit()) { Print("EASniper: daily loss limit reached, no new trades today."); return false; }
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPts > 0 && sp > InpMaxSpreadPts) { Print("EASniper: spread too wide, skipped."); return false; }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = NormalizeDouble(sg.sl, _Digits);
   double tp  = NormalizeDouble(sg.tp, _Digits);
   double price = (sg.dir == 1) ? ask : bid;
   if(sg.dir == 1  && sl >= price) return false;
   if(sg.dir == -1 && sl <= price) return false;
   double lots = CalcLots(MathAbs(price - sl));
   if(lots <= 0) return false;
   bool ok;
   if(sg.dir == 1) ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "EASniper");
   else            ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "EASniper");
   if(!ok) Print("EASniper: order failed: ", trade.ResultRetcodeDescription());
   return ok;
}

//+------------------------------------------------------------------+
//| Zones                                                            |
//+------------------------------------------------------------------+
void RemoveZone(int k)
{
   for(int m = k; m < g_zn - 1; m++) g_zones[m] = g_zones[m + 1];
   g_zn--;
   ArrayResize(g_zones, g_zn);
}

void AddZone(int dir, double lo, double hi, int startIdx, double a)
{
   double h = hi - lo;
   double minH = 0.25 * a, maxH = 1.5 * a;
   if(h < minH) { if(dir == 1) hi = lo + minH; else lo = hi - minH; }
   if(h > maxH) { if(dir == 1) hi = lo + maxH; else lo = hi - maxH; }
   for(int k = 0; k < g_zn; k++)
   {
      if(g_zones[k].dir != dir) continue;
      if(!(hi < g_zones[k].lo || lo > g_zones[k].hi)) return;   // overlaps an active zone
   }
   if(g_zn >= 60) RemoveZone(0);
   ArrayResize(g_zones, g_zn + 1);
   g_zones[g_zn].dir = dir;
   g_zones[g_zn].lo = lo;
   g_zones[g_zn].hi = hi;
   g_zones[g_zn].startIdx = startIdx;
   g_zones[g_zn].touches = 0;
   g_zones[g_zn].bounces = 0;
   g_zones[g_zn].inside = false;
   g_zones[g_zn].pend = false;
   g_zones[g_zn].pendATR = a;
   g_zn++;
}

void UpdateZones(int j)
{
   for(int k = g_zn - 1; k >= 0; k--)
   {
      if(j <= g_zones[k].startIdx) continue;
      if(j - g_zones[k].startIdx > InpMaxZoneAge) { RemoveZone(k); continue; }
      double lo = g_zones[k].lo, hi = g_zones[k].hi;
      bool inNow = (g_low[j] <= hi && g_high[j] >= lo);
      if(inNow && !g_zones[k].inside)
      {
         g_zones[k].touches++;
         g_zones[k].pend = true;
         g_zones[k].pendATR = g_atr[j];
      }
      g_zones[k].inside = inNow;
      if(g_zones[k].dir == 1)
      {
         if(g_close[j] < lo) { RemoveZone(k); continue; }                 // broken
         if(g_zones[k].pend && g_high[j] - hi >= InpReactATR * g_zones[k].pendATR)
         { g_zones[k].bounces++; g_zones[k].pend = false; }
      }
      else
      {
         if(g_close[j] > hi) { RemoveZone(k); continue; }                 // broken
         if(g_zones[k].pend && lo - g_low[j] >= InpReactATR * g_zones[k].pendATR)
         { g_zones[k].bounces++; g_zones[k].pend = false; }
      }
   }
}

void CreateZones(int j)
{
   if(j < InpBreakLookback + 2) return;
   double a = g_atr[j];
   if(a <= 0) return;
   double body = g_close[j] - g_open[j];
   if(body >= InpImpulseATR * a)
   {
      double hh = -DBL_MAX;
      for(int i = j - InpBreakLookback; i < j; i++) if(g_high[i] > hh) hh = g_high[i];
      if(g_close[j] > hh)
         AddZone(1, g_low[j - 1], MathMax(g_open[j - 1], g_close[j - 1]), j, a);
   }
   else if(-body >= InpImpulseATR * a)
   {
      double ll = DBL_MAX;
      for(int i = j - InpBreakLookback; i < j; i++) if(g_low[i] < ll) ll = g_low[i];
      if(g_close[j] < ll)
         AddZone(-1, MathMin(g_open[j - 1], g_close[j - 1]), g_high[j - 1], j, a);
   }
}

//+------------------------------------------------------------------+
//| Signal scoring (uses only closed bars, no look-ahead)            |
//+------------------------------------------------------------------+
bool EvalSignal(int j, SSignal &sg)
{
   sg.score = -1;
   double a = g_atr[j];
   if(a <= 0) return false;
   double o = g_open[j], h = g_high[j], l = g_low[j], c = g_close[j];
   double rng = h - l;
   double vr = (g_atrS[j] > 0) ? a / g_atrS[j] : 1.0;
   bool   volOK = (vr >= 0.6 && vr <= 1.4);
   bool   sessOK = SessionOK(g_time[j]);
   string reg = (vr < 0.6) ? "quiet" : ((vr > 1.4) ? "busy" : "normal");

   for(int k = 0; k < g_zn; k++)
   {
      SZone z = g_zones[k];
      if(z.startIdx >= j) continue;
      int dir = z.dir;
      bool touch, rej;
      double wick;
      if(dir == 1)
      {
         touch = (l <= z.hi && l >= z.lo - 0.3 * a);
         rej   = (touch && c > z.hi && c > o);
         wick  = MathMin(o, c) - l;
      }
      else
      {
         touch = (h >= z.lo && h <= z.hi + 0.3 * a);
         rej   = (touch && c < z.lo && c < o);
         wick  = h - MathMax(o, c);
      }
      if(!rej) continue;

      int sc = 3;                                   // clean rejection of a zone
      bool trendOK = (g_trend[j] == dir);
      if(trendOK) sc += 2;                          // big trend agrees
      else if(InpRequireTrend) continue;
      bool wickOK = (rng > 0 && wick / rng >= 0.35);
      if(wickOK) sc++;                              // strong rejection wick
      int tchNow = z.touches + (z.inside ? 0 : 1);
      if(tchNow <= 2) sc++;                         // fresh zone
      if(z.bounces >= 1) sc++;                      // zone has reacted before
      if(volOK) sc++;                               // market not quiet/spiky
      if(sessOK) sc++;                              // inside session

      double entry = c, sl, risk;
      if(dir == 1) { sl = z.lo - InpSLBufferATR * a; risk = entry - sl; }
      else         { sl = z.hi + InpSLBufferATR * a; risk = sl - entry; }
      if(risk < InpMinRiskATR * a)
      {
         risk = InpMinRiskATR * a;
         sl = (dir == 1) ? entry - risk : entry + risk;
      }
      if(risk > InpMaxRiskATR * a) continue;
      double tp = (dir == 1) ? entry + InpRR * risk : entry - InpRR * risk;

      if(sc > sg.score)
      {
         sg.dir = dir; sg.score = sc; sg.entry = entry; sg.sl = sl; sg.tp = tp; sg.risk = risk;
         sg.reason = StringFormat("%s at %s zone (touch %d, %d bounces) | big trend %s | market %s | wick %s | session %s | score %d/10",
                                  (dir == 1 ? "BUY" : "SELL"), (dir == 1 ? "demand" : "supply"),
                                  tchNow, z.bounces, (trendOK ? "agrees" : "against"), reg,
                                  (wickOK ? "strong" : "weak"), (sessOK ? "ok" : "off"), sc);
      }
   }
   return (sg.score >= InpMinScore);
}

//+------------------------------------------------------------------+
//| Virtual trade book (this is what the stats panel measures)       |
//+------------------------------------------------------------------+
void OpenVirtual(int j, const SSignal &sg)
{
   g_hasOpen = true;
   g_open_t.dir = sg.dir; g_open_t.openIdx = j; g_open_t.entry = sg.entry;
   g_open_t.sl = sg.sl; g_open_t.tp = sg.tp; g_open_t.risk = sg.risk; g_open_t.score = sg.score;
   g_open_t.real = false;
   g_lastSigIdx = j;
   g_lastReason = sg.reason;
   if(g_live)
   {
      if(InpAutoTrade) g_open_t.real = TryOpenReal(sg);
      Notify(StringFormat("%s %s %s | entry %s | SL %s | TP %s | %s",
             _Symbol, TFName(), (sg.dir == 1 ? "BUY" : "SELL"), P(sg.entry), P(sg.sl), P(sg.tp), sg.reason));
   }
}

void CloseTrade(int j, double exitPrice, string why)
{
   double cost = (g_open_t.risk > 0) ? g_costPrice / g_open_t.risk : 0;
   double R = g_open_t.dir * (exitPrice - g_open_t.entry) / g_open_t.risk - cost;

   g_nTrades++;
   if(R > 0) { g_nWins++; g_sumWin += R; g_streak = 0; }
   else      { g_sumLoss += -R; g_streak++; if(g_streak > g_maxStreak) g_maxStreak = g_streak; }

   int m = ArraySize(g_done);
   if(m >= 30)
   {
      for(int i = 1; i < m; i++) g_done[i - 1] = g_done[i];
      m--;
      ArrayResize(g_done, m);
   }
   ArrayResize(g_done, m + 1);
   g_done[m].dir = g_open_t.dir;
   g_done[m].t0 = g_time[g_open_t.openIdx];
   g_done[m].t1 = g_time[j];
   g_done[m].entry = g_open_t.entry;
   g_done[m].sl = g_open_t.sl;
   g_done[m].tp = g_open_t.tp;
   g_done[m].exitPrice = exitPrice;
   g_done[m].r = R;

   if(g_live)
   {
      if(g_open_t.real) CloseRealPosition();
      Notify(StringFormat("%s %s EXIT %s | %s | result %.2fR", _Symbol, TFName(),
             (g_open_t.dir == 1 ? "BUY" : "SELL"), why, R));
   }
   g_hasOpen = false;
}

void ManageOpen(int j)
{
   if(!g_hasOpen || j <= g_open_t.openIdx) return;
   bool slHit, tpHit;
   if(g_open_t.dir == 1) { slHit = (g_low[j] <= g_open_t.sl);  tpHit = (g_high[j] >= g_open_t.tp); }
   else                  { slHit = (g_high[j] >= g_open_t.sl); tpHit = (g_low[j] <= g_open_t.tp); }
   if(slHit)                                           CloseTrade(j, g_open_t.sl, "stop loss hit");
   else if(tpHit)                                      CloseTrade(j, g_open_t.tp, "target hit");
   else if(InpSoftExit && g_trend[j] == -g_open_t.dir) CloseTrade(j, g_close[j], "big trend turned against the trade");
   else if(j - g_open_t.openIdx >= InpMaxHoldBars)     CloseTrade(j, g_close[j], "time stop");
}

//+------------------------------------------------------------------+
//| One closed bar goes through the whole engine                     |
//+------------------------------------------------------------------+
void ProcessBar(const MqlRates &r)
{
   int j = g_nb;
   ArrayResize(g_time, j + 1, 4096);  ArrayResize(g_open, j + 1, 4096);
   ArrayResize(g_high, j + 1, 4096);  ArrayResize(g_low, j + 1, 4096);
   ArrayResize(g_close, j + 1, 4096); ArrayResize(g_atr, j + 1, 4096);
   ArrayResize(g_atrS, j + 1, 4096);  ArrayResize(g_ema, j + 1, 4096);
   ArrayResize(g_trend, j + 1, 4096);
   g_time[j] = r.time; g_open[j] = r.open; g_high[j] = r.high; g_low[j] = r.low; g_close[j] = r.close;

   if(j == 0)
   {
      double tr0 = r.high - r.low;
      g_atrV = tr0; g_atrSV = tr0; g_emaV = r.close;
   }
   else
   {
      double tr = MathMax(r.high - r.low, MathMax(MathAbs(r.high - g_prevClose), MathAbs(r.low - g_prevClose)));
      double p1 = MathMin(j + 1, InpATRPeriod);
      double p2 = MathMin(j + 1, InpATRSlow);
      g_atrV  = (g_atrV  * (p1 - 1.0) + tr) / p1;
      g_atrSV = (g_atrSV * (p2 - 1.0) + tr) / p2;
      g_emaV += g_alpha * (r.close - g_emaV);
   }
   g_prevClose = r.close;
   g_atr[j] = g_atrV; g_atrS[j] = g_atrSV; g_ema[j] = g_emaV;

   int td = 0;
   if(j >= g_ratio)
   {
      double pe = g_ema[j - g_ratio];
      if(r.close > g_emaV && g_emaV > pe) td = 1;
      else if(r.close < g_emaV && g_emaV < pe) td = -1;
   }
   g_trend[j] = td;
   g_nb = j + 1;

   if(j < g_minBars) return;

   ManageOpen(j);

   SSignal sg;
   if(EvalSignal(j, sg))
   {
      if(g_hasOpen && g_open_t.dir == -sg.dir) CloseTrade(j, g_close[j], "opposite signal");
      if(!g_hasOpen && (j - g_lastSigIdx) >= InpMinGapBars) OpenVirtual(j, sg);
   }

   UpdateZones(j);
   CreateZones(j);
}

int ProcessRange(datetime stopTime)
{
   MqlRates rr[];
   datetime from = g_lastProc + 1;
   int got = CopyRates(_Symbol, _Period, from, stopTime - 1, rr);
   if(got <= 0) return 0;
   for(int i = 0; i < got; i++)
   {
      ProcessBar(rr[i]);
      g_lastProc = rr[i].time;
   }
   return got;
}

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void PanelLine(int idx, string text, color clr)
{
   string nm = PFX + "P" + IntegerToString(idx);
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 18 + idx * 16);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
}

void DrawArrow(string nm, datetime t, double price, int code, color clr)
{
   ObjectCreate(0, nm, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}

void DrawSeg(string nm, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE st)
{
   ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}

void Redraw()
{
   if(g_nb < 2) return;
   ObjectsDeleteAll(0, PFX + "Z");
   ObjectsDeleteAll(0, PFX + "M");
   ObjectsDeleteAll(0, PFX + "L");
   int last = g_nb - 1;
   datetime tEnd = g_time[last] + (datetime)(30 * PeriodSeconds());

   //--- zones (newest N)
   int firstZ = MathMax(0, g_zn - InpMaxZonesShown);
   int nd = 0, ns = 0;
   for(int k = 0; k < g_zn; k++) { if(g_zones[k].dir == 1) nd++; else ns++; }
   for(int k = firstZ; k < g_zn; k++)
   {
      int s = MathMax(0, g_zones[k].startIdx - 1);
      string nm = PFX + "Z" + IntegerToString(k);
      color zc = (g_zones[k].dir == 1) ? InpDemandClr : InpSupplyClr;
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_time[s], g_zones[k].hi, tEnd, g_zones[k].lo);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, zc);
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      string tn = PFX + "ZT" + IntegerToString(k);
      ObjectCreate(0, tn, OBJ_TEXT, 0, g_time[s], g_zones[k].hi);
      ObjectSetString(0, tn, OBJPROP_TEXT, StringFormat("%s  touched %d  bounced %d",
                      (g_zones[k].dir == 1 ? "DEMAND" : "SUPPLY"), g_zones[k].touches, g_zones[k].bounces));
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, zc);
      ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
   }

   //--- past trades
   int nDone = ArraySize(g_done);
   int firstD = MathMax(0, nDone - InpDrawTrades);
   for(int i = firstD; i < nDone; i++)
   {
      string id = IntegerToString(i);
      DrawArrow(PFX + "MA" + id, g_done[i].t0, g_done[i].entry, (g_done[i].dir == 1 ? 233 : 234),
                (g_done[i].dir == 1 ? clrDodgerBlue : clrOrangeRed));
      DrawArrow(PFX + "MX" + id, g_done[i].t1, g_done[i].exitPrice, 251, (g_done[i].r > 0 ? clrLime : clrRed));
      DrawSeg(PFX + "LS" + id, g_done[i].t0, g_done[i].t1, g_done[i].sl, clrTomato, STYLE_DOT);
      DrawSeg(PFX + "LT" + id, g_done[i].t0, g_done[i].t1, g_done[i].tp, clrLimeGreen, STYLE_DOT);
   }

   //--- open trade
   if(g_hasOpen)
   {
      datetime t0 = g_time[g_open_t.openIdx];
      DrawArrow(PFX + "MAopen", t0, g_open_t.entry, (g_open_t.dir == 1 ? 233 : 234),
                (g_open_t.dir == 1 ? clrDodgerBlue : clrOrangeRed));
      DrawSeg(PFX + "LEopen", t0, tEnd, g_open_t.entry, clrSilver, STYLE_SOLID);
      DrawSeg(PFX + "LSopen", t0, tEnd, g_open_t.sl, clrTomato, STYLE_SOLID);
      DrawSeg(PFX + "LTopen", t0, tEnd, g_open_t.tp, clrLimeGreen, STYLE_SOLID);
   }

   //--- panel
   int td = g_trend[last];
   double vr = (g_atrS[last] > 0) ? g_atr[last] / g_atrS[last] : 1.0;
   string reg = (vr < 0.6) ? "quiet" : ((vr > 1.4) ? "busy" : "normal");
   PanelLine(0, StringFormat("EASniper v1  |  %s %s  |  mode: %s", _Symbol, TFName(), (InpAutoTrade ? "AUTO-TRADE" : "ADVISE ONLY")), clrWhite);
   PanelLine(1, StringFormat("Big trend (%s): %s   Market: %s   Zones: %d demand / %d supply",
             StringSubstr(EnumToString(InpHTF), 7), (td == 1 ? "UP" : (td == -1 ? "DOWN" : "FLAT")), reg, nd, ns), clrSilver);
   if(g_hasOpen)
      PanelLine(2, StringFormat("OPEN %s  entry %s  SL %s  TP %s  | EXIT if SL/TP hit, big trend flips, opposite signal, or %d bars pass",
                (g_open_t.dir == 1 ? "BUY" : "SELL"), P(g_open_t.entry), P(g_open_t.sl), P(g_open_t.tp), InpMaxHoldBars), clrYellow);
   else
      PanelLine(2, "No open signal. Waiting for a zone touch with score >= " + IntegerToString(InpMinScore), clrSilver);
   PanelLine(3, "Last signal: " + g_lastReason, clrSilver);

   double winPct = (g_nTrades > 0) ? 100.0 * g_nWins / g_nTrades : 0;
   double pf = (g_sumLoss > 0) ? g_sumWin / g_sumLoss : (g_sumWin > 0 ? 99.0 : 0.0);
   PanelLine(4, StringFormat("History replay: %d trades | win %.1f%% (your target %.0f%%) | profit factor %.2f | worst losing streak %d",
             g_nTrades, winPct, InpTargetWin, pf, g_maxStreak), clrWhite);
   if(g_nTrades < InpMinTradesProof)
      PanelLine(5, StringFormat("VERDICT: UNPROVEN - only %d trades (need %d). Do not trust yet.", g_nTrades, InpMinTradesProof), clrOrange);
   else if(pf >= InpMinPF)
      PanelLine(5, "VERDICT: edge visible on this history. Still confirm on unseen data / demo.", clrLime);
   else
      PanelLine(5, "VERDICT: NO EDGE on this history. Do not trade these signals.", clrTomato);
   ChartRedraw();
}

//+------------------------------------------------------------------+
bool DoWarm()
{
   int avail = Bars(_Symbol, _Period);
   if(avail < 200) return false;
   int n = MathMin(InpWarmupBars, avail - 2);
   datetime from = iTime(_Symbol, _Period, n);
   datetime t0   = iTime(_Symbol, _Period, 0);
   if(from == 0 || t0 == 0) return false;
   ResetEngine();
   g_live = false;
   g_lastProc = from - 1;
   int got = ProcessRange(t0);
   if(got <= 0) return false;
   g_lastBar = t0;
   g_live = true;
   g_warm = true;
   if(g_nb < g_minBars)
      Print("EASniper: only ", g_nb, " bars loaded, need ", g_minBars, ". Scroll the chart back or lower InpHTFEma/InpHTF.");
   if(g_draw) Redraw();
   return true;
}

int OnInit()
{
   g_ratio = (int)MathMax(1, PeriodSeconds(InpHTF) / PeriodSeconds(_Period));
   g_emaPeriod = InpHTFEma * g_ratio;
   g_alpha = 2.0 / (g_emaPeriod + 1.0);
   g_minBars = (int)MathMax(InpATRSlow + 5, MathMin(g_emaPeriod, 3000));
   trade.SetExpertMagicNumber(InpMagic);
   g_draw = ((!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)) && !MQLInfoInteger(MQL_OPTIMIZATION));
   g_costPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   ObjectsDeleteAll(0, PFX);
   DoWarm();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX);
}

void OnTick()
{
   if(!g_warm) { DoWarm(); return; }
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0 || t0 == g_lastBar) return;
   g_lastBar = t0;
   g_costPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   ProcessRange(t0);
   if(g_draw) Redraw();
}
//+------------------------------------------------------------------+
