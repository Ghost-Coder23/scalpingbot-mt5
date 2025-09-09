# ScalpingBot v2.0 - Complete Documentation

## Table of Contents
1. [System Requirements](#system-requirements)
2. [Installation Guide](#installation-guide)
3. [Compilation Instructions](#compilation-instructions)
4. [Bot Overview](#bot-overview)
5. [Trading Strategy](#trading-strategy)
6. [Parameter Settings](#parameter-settings)
7. [Risk Management](#risk-management)
8. [Backtesting Guide](#backtesting-guide)
9. [Live Trading Setup](#live-trading-setup)
10. [Troubleshooting](#troubleshooting)
11. [Performance Optimization](#performance-optimization)
12. [Important Disclaimers](#important-disclaimers)

---

## System Requirements

### Minimum Requirements:
- **MetaTrader 5** (build 3560 or later)
- **Windows 10** or later / **macOS** / **Linux** with Wine
- **4 GB RAM** minimum
- **Stable internet connection** (low latency preferred for scalping)
- **VPS recommended** for 24/7 operation

### Broker Requirements:
- **ECN/STP broker** preferred for tight spreads
- **Maximum spread**: 2-3 points for major pairs
- **Execution speed**: Under 50ms
- **No scalping restrictions**
- **Micro lots supported** (0.01 minimum)

---

## Installation Guide

### Step 1: Download Files
You need two files:
1. `ImprovedScalpingBot.mqh` (header file)
2. `ImprovedScalpingBot.mq5` (main EA file)

### Step 2: File Placement
1. **Open MT5**
2. **Press F4** or go to **Tools → MetaQuotes Language Editor**
3. **Navigate to file locations**:
   - Place `ImprovedScalpingBot.mqh` in: `MQL5/Include/` folder
   - Place `ImprovedScalpingBot.mq5` in: `MQL5/Experts/` folder

### Step 3: File Structure
```
MT5 Data Folder/
├── MQL5/
│   ├── Experts/
│   │   └── ImprovedScalpingBot.mq5
│   └── Include/
│       └── ImprovedScalpingBot.mqh
```

---

## Compilation Instructions

### Method 1: Using MetaEditor
1. **Open MetaEditor** (F4 in MT5)
2. **Open** `ImprovedScalpingBot.mq5`
3. **Click Compile** button (F7) or go to **File → Compile**
4. **Check for errors** in the "Errors" tab
5. **Successful compilation** shows "0 error(s), 0 warning(s)"

### Method 2: Using MT5 Navigator
1. **Open MT5**
2. **Go to Navigator** (Ctrl+N)
3. **Right-click** on "Expert Advisors"
4. **Select "Refresh"**
5. **ImprovedScalpingBot** should appear in the list

### Compilation Checklist:
- ✅ Both files in correct folders
- ✅ No syntax errors
- ✅ EA appears in Navigator
- ✅ Version shows as "2.00"

---

## Bot Overview

### Core Functionality
The ScalpingBot is designed for short-term trading on the M5 timeframe, using:
- **Multiple technical indicators** for signal generation
- **Risk management** with dynamic position sizing
- **Multi-timeframe analysis** for trend confirmation
- **Advanced filters** to avoid bad market conditions

### Key Features:
- **Automated Trading**: Fully automated buy/sell decisions
- **Risk Control**: Customizable risk per trade
- **Spread Protection**: Avoids trading during high spreads
- **Time Filtering**: Trades only during optimal hours
- **Trailing Stops**: Locks in profits automatically
- **Position Management**: Limits maximum open positions

---

## Trading Strategy

### Entry Conditions

#### BUY Signal Requirements:
1. **Higher Timeframe Trend**: 15-min SMA trending up
2. **Price Position**: Above 20-period EMA on M5
3. **RSI Oversold**: RSI < 35 (recovering)
4. **Bollinger Bands**: Price in lower 20% of BB range
5. **Pattern Confirmation**: Bullish engulfing candlestick
6. **Volume**: Optional volume confirmation

#### SELL Signal Requirements:
1. **Higher Timeframe Trend**: 15-min SMA trending down
2. **Price Position**: Below 20-period EMA on M5
3. **RSI Overbought**: RSI > 65 (declining)
4. **Bollinger Bands**: Price in upper 20% of BB range
5. **Pattern Confirmation**: Bearish engulfing candlestick
6. **Volume**: Optional volume confirmation

### Exit Strategy:
- **Take Profit**: Fixed points (default 40)
- **Stop Loss**: Fixed points (default 20)
- **Trailing Stop**: Optional dynamic exit
- **Risk Ratio**: 1:2 (Risk 20, Profit 40)

---

## Parameter Settings

### Trading Parameters
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `Lots` | 0.01 | 0-100 | Fixed lot size (0 = auto) |
| `RiskPercent` | 1.0 | 0.1-5.0 | Risk per trade (% of account) |
| `StopLoss` | 20 | 10-100 | Stop loss in points |
| `TakeProfit` | 40 | 20-200 | Take profit in points |
| `MaxSpreadPoints` | 3.0 | 1.0-10.0 | Maximum allowed spread |

### Indicator Settings
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `RSIPeriod` | 14 | 5-30 | RSI calculation period |
| `EMAPeriod` | 20 | 10-50 | EMA calculation period |
| `BBPeriod` | 20 | 10-50 | Bollinger Bands period |

### Risk Management
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `MaxPositions` | 1 | 1-5 | Maximum open positions |
| `UseTrailingStop` | true | true/false | Enable trailing stops |
| `TrailingStop` | 15 | 5-50 | Trailing stop distance |
| `TrailingStep` | 5 | 1-20 | Trailing step size |

### Advanced Filters
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `UseTimeFilter` | true | true/false | Enable time-based filtering |
| `UseATRFilter` | true | true/false | Enable volatility filtering |
| `ATRPeriod` | 14 | 5-30 | ATR calculation period |
| `ATRMultiplier` | 1.5 | 1.0-3.0 | ATR volatility threshold |

---

## Risk Management

### Position Sizing Methods

#### Fixed Lot Size:
- Set `Lots` to desired value (e.g., 0.01)
- Simple but doesn't adjust to account size

#### Dynamic Risk-Based Sizing:
- Set `Lots = 0` to enable auto-calculation
- Set `RiskPercent` to desired risk per trade
- Automatically adjusts lot size based on:
  - Account balance
  - Stop loss distance
  - Symbol specifications

### Risk Calculation Example:
```
Account Balance: $10,000
Risk Percent: 1%
Stop Loss: 20 points
Risk Amount: $100
Calculated Lot Size: ~0.05 lots (varies by symbol)
```

### Safety Features:
- **Maximum positions limit** prevents over-exposure
- **Spread filtering** avoids high-cost trades
- **Stop level validation** ensures valid SL/TP
- **Trailing stops** protect profits
- **Time filters** avoid volatile news periods

---

## Backtesting Guide

### Preparation Steps:
1. **Open Strategy Tester** (Ctrl+R in MT5)
2. **Select Expert Advisor**: ImprovedScalpingBot
3. **Choose Symbol**: Major pairs (EUR/USD, GBP/USD, USD/JPY)
4. **Set Timeframe**: M5 (required)
5. **Select Period**: At least 3 months of data

### Recommended Settings:
- **Model**: Every tick (most accurate)
- **Optimization**: Genetic algorithm
- **Execution delay**: 50ms (realistic)
- **Initial deposit**: $10,000 minimum

### Key Metrics to Monitor:
- **Total Net Profit**: Should be positive
- **Profit Factor**: > 1.2 (good), > 1.5 (excellent)
- **Maximum Drawdown**: < 20%
- **Win Rate**: > 40% for scalping
- **Average Trade**: Positive
- **Sharpe Ratio**: > 1.0

### Optimization Parameters:
Focus on optimizing these parameters:
1. `StopLoss` (10-30)
2. `TakeProfit` (30-60)
3. `RSIPeriod` (10-20)
4. `EMAPeriod` (15-30)
5. `RiskPercent` (0.5-2.0)

---

## Live Trading Setup

### Pre-Launch Checklist:
- ✅ Backtesting completed with positive results
- ✅ Demo testing for at least 1 week
- ✅ VPS setup for 24/7 operation
- ✅ Broker conditions verified
- ✅ Risk parameters set conservatively
- ✅ Emergency stop procedures prepared

### Step-by-Step Live Setup:

#### 1. Prepare Trading Account:
- **Fund account** with sufficient capital
- **Verify leverage** settings
- **Check trading hours** and restrictions
- **Test execution speed**

#### 2. Install on VPS (Recommended):
- **Choose reliable VPS** provider
- **Install MT5** on VPS
- **Configure network** settings
- **Set up remote access**

#### 3. Load Expert Advisor:
- **Drag EA** to desired chart
- **Select timeframe**: M5
- **Configure parameters** conservatively
- **Enable auto-trading** (Ctrl+E)

#### 4. Initial Settings for Live:
```
Lots = 0.01 (start small)
RiskPercent = 0.5% (conservative)
MaxPositions = 1
UseTrailingStop = true
UseTimeFilter = true
```

#### 5. Monitor Initial Trades:
- **Watch first 10 trades** closely
- **Check execution quality**
- **Monitor drawdown**
- **Verify logging functions**

---

## Troubleshooting

### Common Issues and Solutions:

#### 1. EA Not Trading
**Symptoms**: No trades opened despite signals
**Solutions**:
- Check if auto-trading is enabled (Ctrl+E)
- Verify spread is within MaxSpreadPoints
- Ensure sufficient account balance
- Check time filter settings
- Verify broker allows EAs

#### 2. Compilation Errors
**Symptoms**: Red errors in MetaEditor
**Solutions**:
- Check file locations (MQL5/Experts/ and MQL5/Include/)
- Verify MT5 version is updated
- Check for typos in file names
- Restart MetaEditor

#### 3. Invalid Stops Error
**Symptoms**: "Invalid stops" in expert log
**Solutions**:
- Increase StopLoss/TakeProfit values
- Check broker's minimum stop level
- Verify point calculations for symbol
- Use larger values for exotic pairs

#### 4. No Historical Data
**Symptoms**: Indicators showing empty values
**Solutions**:
- Download more historical data (F2 in MT5)
- Wait for indicator initialization
- Check internet connection
- Restart MT5

#### 5. High Drawdown
**Symptoms**: Account equity dropping rapidly
**Solutions**:
- Reduce RiskPercent immediately
- Increase StopLoss values
- Limit MaxPositions to 1
- Enable trailing stops
- Consider pausing EA during news

### Error Codes Reference:
- **Error 10016**: Invalid stops (adjust SL/TP)
- **Error 10018**: Market closed (check trading hours)
- **Error 10019**: No money (insufficient funds)
- **Error 10020**: Prices changed (normal in fast markets)
- **Error 130**: Invalid stops (broker-specific)

---

## Performance Optimization

### Regular Maintenance:

#### Weekly Tasks:
- **Review trade history** and performance metrics
- **Check for any error messages** in expert log
- **Monitor drawdown** and profit factor
- **Update economic calendar** for news filtering

#### Monthly Tasks:
- **Analyze performance** by currency pair
- **Optimize parameters** if necessary
- **Update MT5** and EA versions
- **Review broker conditions** and spreads

#### Quarterly Tasks:
- **Full backtest** with recent data
- **Compare with benchmark** performance
- **Adjust risk parameters** based on results
- **Consider strategy modifications**

### Performance Metrics to Track:
- **Monthly Return**: Target 5-15%
- **Maximum Drawdown**: Keep below 20%
- **Profit Factor**: Maintain above 1.3
- **Win Rate**: Aim for 45-60%
- **Average Trade Duration**: 30-120 minutes

### Optimization Tips:
1. **Test different timeframes** (M1, M5, M15)
2. **Optimize for specific currency pairs**
3. **Adjust for different market conditions**
4. **Use walk-forward analysis**
5. **Consider seasonal patterns**

---

## Important Disclaimers

### Risk Warnings:
⚠️ **Trading involves substantial risk of loss**
⚠️ **Past performance does not guarantee future results**
⚠️ **Scalping carries higher risk due to frequency**
⚠️ **Leverage amplifies both profits and losses**
⚠️ **Market conditions can change rapidly**

### Recommendations:
- **Never risk more than you can afford to lose**
- **Start with demo trading for at least 2 weeks**
- **Use conservative risk settings initially**
- **Monitor performance regularly**
- **Have a clear exit strategy**
- **Keep detailed trading records**
- **Consider professional advice**

### Legal Notice:
This Expert Advisor is provided for educational and research purposes. The creators are not responsible for any financial losses incurred through its use. Users should thoroughly test the system and understand the risks before live trading.

### Support and Updates:
- **Documentation**: Keep this guide for reference
- **Backtesting**: Always test before live implementation
- **Community**: Share experiences responsibly
- **Updates**: Check for EA improvements regularly

---

## Quick Start Checklist

### For Beginners:
- [ ] Install MT5 and open demo account
- [ ] Download and compile EA files
- [ ] Run 3-month backtest on EUR/USD M5
- [ ] Test on demo for 1 week minimum
- [ ] Start live with 0.01 lots and 0.5% risk
- [ ] Monitor closely for first week
- [ ] Gradually increase size if profitable

### For Experienced Traders:
- [ ] Optimize parameters for your preferred pairs
- [ ] Set up on VPS for 24/7 operation
- [ ] Implement advanced risk management
- [ ] Use multiple instances on different pairs
- [ ] Set up performance monitoring
- [ ] Regular strategy review and updates

Remember: **Patience and discipline are key to successful algorithmic trading!**