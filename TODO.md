# ScalpingBot Development TODO

## Done (v3.0 code written)
- [x] Decide on closed candles only
- [x] Regime detection (ADX) with trend / range / neutral logic
- [x] 5-point signal scoring
- [x] ATR-based SL/TP, break-even, trailing, time stop
- [x] Risk-based lot sizing, margin check
- [x] Daily loss limit and loss-streak cooldown
- [x] Dashboard and verbose logging
- [x] README

## Next (needs MetaTrader)
- [ ] Compile in MetaEditor and fix any errors
- [ ] Backtest on the Welltrade synthetic instrument(s), every tick
- [ ] Read the verbose log and check trades match the rules
- [ ] Tune MinScore, SL/TP multipliers, ADX thresholds (then test on unseen data)
- [ ] Demo trade for a few weeks
- [ ] Check spread vs ATR on each instrument and adjust InpMaxSpreadAtrFrac

## Level 3 (later)
- [ ] Export features + labels to CSV
- [ ] Train and validate a model in Python
- [ ] Export to ONNX and add as an extra check in the EA
