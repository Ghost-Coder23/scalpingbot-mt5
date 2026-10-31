# ScalpingBot v3.0 (MetaTrader 5)

An Expert Advisor that scalps on the **M5 chart**. Instead of one fixed recipe, it first works out **what kind of market it is in** (trending or sideways), then looks for a matching setup and **scores** it. It only trades when enough checks agree, and it protects the account with several safety limits.

> **Status:** v3.0 was written without access to MetaTrader. Compile it, check for errors, and run it in the Strategy Tester and on a demo account before trusting it with real money. Nothing here is a promise of profit.

---

## What it can do

| Ability | What it means |
|---|---|
| **Regime detection** | Uses ADX to decide: TREND, RANGE or NEUTRAL, and switches its logic. |
| **Signal scoring** | 5 checks per direction. It needs 4 of 5 (5 of 5 in NEUTRAL) before it trades. |
| **Higher-timeframe bias** | Looks at an EMA on M15 so it doesn't fight the bigger move. |
| **ATR-based stops** | Stop loss and take profit scale with current volatility, so it adapts to any instrument. |
| **Risk-based lot size** | Sizes each trade so a stop-out loses about `RiskPercent` of the balance. |
| **Break-even + trailing** | Moves the stop to break-even, then trails it behind price. |
| **Time stop** | Closes a trade that goes nowhere after `MaxHoldBars` candles. |
| **Spread / volatility filters** | Skips trades when the spread is too big compared with ATR. |
| **Daily loss limit** | Stops for the day after losing `MaxDailyLossPct` of the balance. |
| **Loss-streak cooldown** | Pauses after `MaxConsecLosses` losses in a row. |
| **Margin check** | Won't open a trade that needs too much of the free margin. |
| **On-chart dashboard** | Shows regime, scores, ATR, spread, today's P/L and why it is waiting. |

## What it does NOT do

- No machine learning or AI model (see the roadmap below).
- No news filter.
- No grid, martingale or hedging. It uses one trade at a time by default.
- It does not guarantee profit and has no proven edge. Test it yourself.

---

## How it decides (every new M5 candle)

The bot only decides when a candle has **closed**, and reads everything from closed candles.

1. **Safety gates first.** It does nothing if: a position is already open, trading is not allowed, the time filter blocks it, the spread or volatility is bad, the daily loss limit is hit, or it is cooling down after a losing streak.
2. **Regime** from ADX:
   - `ADX >= 25` is **TREND**.
   - `ADX <= 20` is **RANGE**.
   - In between is **NEUTRAL** (treated like a trend but needs one extra point).
3. **Score** both BUY and SELL, one point per check:

| # | Check | BUY in TREND / NEUTRAL | BUY in RANGE |
|---|---|---|---|
| 1 | **HTF** higher timeframe | M15 trend is up | M15 trend is up or flat |
| 2 | **LOC** location | Price pulled back to the EMA and closed above it | Price in the bottom 25% of the Bollinger Bands |
| 3 | **RSI** momentum | RSI dipped to 50 or lower and is turning up | RSI was at 35 or lower and is turning up |
| 4 | **CANDLE** | Bullish engulfing or hammer | Bullish engulfing or hammer |
| 5 | **VOL** | Signal candle's tick volume is at least average | Same |

SELL is the mirror image (down trend, price rejected at the EMA or top 25% of the bands, RSI turning down, bearish engulfing or shooting star).

4. **Trade** if one side reaches the needed score and beats the other side.

## Exits and risk

- **Stop loss:** ATR x `SLAtrMult` (default 1.5).
- **Take profit:** ATR x `TPAtrMult` (default 2.5).
- **Break-even:** once profit reaches ATR x `BETriggerAtr` (default 1.0), the stop moves to the entry price plus `BELockPoints`.
- **Trailing:** after that, the stop trails ATR x `TrailAtr` behind price and never moves backwards.
- **Time stop:** closed after `MaxHoldBars` candles (default 24, which is 2 hours on M5).
- **Lot size:** `Lots = 0` means size by risk (`RiskPercent` of balance divided by the stop distance, calculated by MT5 itself). Set `Lots` above 0 for a fixed size. If the broker's smallest lot would risk more than twice your limit, the trade is skipped (turn off with `AllowMinLotOverRisk`).

---

## Installation

1. In MT5, open **File > Open Data Folder**.
2. Put **both** `ScalpingBot.mq5` and `ScalpingBot.mqh` in the **same folder**, for example `MQL5/Experts/ScalpingBot/`.
3. Open `ScalpingBot.mq5` in MetaEditor and press **F7** (Compile). You should see 0 errors.
4. In MT5, open a chart of your instrument, set it to **M5**, and drag the EA onto it.
5. Turn on **AutoTrading** (Ctrl+E) and allow algo trading in the EA's properties.

Use a **different Magic number** for each chart you run it on if you want separate safety limits for each.

## Key settings

| Setting | Default | Meaning |
|---|---|---|
| `InpLots` | 0.0 | Fixed lots. 0 means size by risk. |
| `InpRiskPercent` | 1.0 | % of balance risked per trade. |
| `InpSLAtrMult` / `InpTPAtrMult` | 1.5 / 2.5 | Stop and target in ATR units. |
| `InpMinScore` | 4 | Points needed out of 5. |
| `InpAdxTrend` / `InpAdxRange` | 25 / 20 | Regime thresholds. |
| `InpMaxSpreadAtrFrac` | 0.25 | Skip if spread is above 25% of ATR. |
| `InpMaxDailyLossPct` | 3.0 | Stop for the day after this loss. |
| `InpMaxConsecLosses` / `InpCooldownBars` | 3 / 12 | Pause length after a losing streak. |
| `InpMaxHoldBars` | 24 | Time stop in candles. |
| `InpUseTimeFilter` | false | Off by default, since synthetic indices trade around the clock. |
| `InpVerbose` | false | Log every bar's decision to the Experts tab. |

All other settings are listed with comments at the top of `ScalpingBot.mq5`. The defaults are **starting points**, not proven values.

## Testing it properly

1. **Strategy Tester** (Ctrl+R): choose your synthetic instrument, M5, "Every tick" or "Every tick based on real ticks", at least a few months, and use your real account's deposit size.
2. Set `InpVerbose = true` for one run and read the Experts log to see *why* it traded or didn't.
3. Look at profit factor, drawdown, number of trades and average trade, not only net profit.
4. Optimize only a few settings at a time (`InpMinScore`, `InpSLAtrMult`, `InpTPAtrMult`, `InpAdxTrend`) and check the result on a period you did **not** optimize on.
5. Then run it on a **demo account** for a few weeks before going live with small risk.

## Troubleshooting

| Problem | Try |
|---|---|
| It doesn't trade | Read the **Status** line on the dashboard. It tells you which gate is blocking. Common cause: spread too large for `InpMaxSpreadAtrFrac`. |
| "Smallest lot would risk..." in the log | Your balance is small for this instrument. Raise `InpRiskPercent` or set `InpAllowMinLotOverRisk = true` (understand the risk first). |
| "Invalid stops" | The broker's minimum stop distance is larger than your SL/TP. Use larger ATR multipliers. |
| Order failed with a filling error | Check the symbol's allowed filling modes with your broker. |
| Compile error about `ScalpingBot.mqh` | The two files must be in the same folder. |

---

## Roadmap: Level 3 (machine learning)

Planned, not built yet:

1. Export M5 history and the same indicator values the bot uses to a CSV file.
2. Label each candle by what happened next: did price hit take-profit before stop-loss?
3. Train a model in Python (for example gradient boosting) using time-ordered train/test splits.
4. Export it to **ONNX** and load it in the EA with MT5's built-in ONNX support.
5. Use the model's probability as an **extra check** on top of the existing rules, and keep all safety limits.

## Changelog

**v3.0**
- Decisions now use **closed candles** (v2.0 read the candle that had just opened).
- Replaced the contradictory entry rules with regime-based rules and a scoring system.
- Removed the forex-only pip multiplier; works with any instrument's point size.
- ATR-based SL/TP, trailing and break-even; risk-based sizing via `OrderCalcProfit`.
- Added daily loss limit, loss-streak cooldown, time stop, margin check and dashboard.
- Time filter is now optional and off by default.
- Fixed the include name mismatch (`ScalpingBot.mqh`).
- Volume check is now real (tick volume) instead of a stub.

**v2.0**: first version with EMA/RSI/Bollinger/engulfing entries.

## Disclaimer

Trading leveraged products carries a high risk of loss. This software is provided for education and research, without warranty. You are responsible for testing it and for any result of using it.
