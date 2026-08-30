# Gangplank Plunder Parrrley

<p align="center">
  <img src="media/gangplank.jpg" alt="Gangplank Plunder Parrrley — break the barrels, take the gold" width="520" />
</p>

> *"Parrrley? I'd rather plunder."*  
> An MT5 Expert Advisor named after Gangplank — Major Trend S/R ladders, shared yellow TP, and Fixed / BEP / TrailLadder management.

## Trade lab (GitHub Pages)

**URL:** [randiapriliyadir.github.io/gangplank-plunder-parrley](https://randiapriliyadir.github.io/gangplank-plunder-parrley/)

Interactive backtest explorer on **Exness Pro real ticks** (`XAUUSD_ExnessPro`, Model 4). Lab deposit: **$100,000**.

| Stand | SL mode | Net | Return | PF | Equity DD | WR | Trades |
|---|---|---:|---:|---:|---:|---:|---:|
| **Best (Fixed)** | Fixed | **+$160,732** | **+161%** | **2.91** | **27.1%** | **71%** | **14** |
| BEP | Break-even on next rung | +$126,320 | +126% | 2.67 | 36.0% | 62% | 13 |
| Trail | Trail to next rung SL | +$122,359 | +122% | 2.57 | 37.2% | 62% | 13 |

Same template on all three: D1 Major Trend, dual-arm idle, one-direction after fill, cluster 0.8 ATR, min sep 1.0 ATR, max SL 2.5 ATR, ladder 3.

## What it is

**Gangplank Plunder Parrrley** places **Buy Stop / Sell Stop** ladders on automatic D1 support/resistance zones (range-box style). Idle = both sides armed from the current range; after one side fills, focus that direction only. Each direction shares one major take-profit (yellow).

No indicators or candlestick filters — only price boundaries, like the Major Trend playbook (blue entries, yellow TP).

## Best verified stand — v1.06 Fixed

| Setting | Value |
|---|---|
| Symbol | **XAUUSD_ExnessPro** (Exness Pro ticks) |
| Chart / template TF | **D1** |
| Max ladder / side | **3** |
| Near levels | 3 support + 3 resistance |
| Cluster / min sep | **0.80 / 1.0** ATR |
| Max SL distance | **2.5** ATR from break |
| Risk / trade | **2%** equity |
| Lot decay | 0.85 per higher rung |
| Budget | 30% (50/50 while dual-arm idle) |
| One direction | ON after fill |
| Lock template | ON (no S/R repaint while booked) |
| SL mode | **Fixed** |
| Season filter | Off (all months) |
| Deposit | **$100,000** |
| Range | 2021.01.01 → 2025.07.31 |
| Model | **Every tick based on real ticks** |

### SL mode takeaway

| Mode | Net | PF | DD | WR | N |
|---|---:|---:|---:|---:|---:|
| **Fixed (shipped)** | **+$161k** | **2.91** | **27%** | **71%** | **14** |
| BEP | +$126k | 2.67 | 36% | 62% | 13 |
| TrailLadder | +$122k | 2.57 | 37% | 62% | 13 |

**Fixed wins.** Moving SL to BE / next-rung SL on gold D1 often cuts winners before the shared major TP.

## Install (MT5)

1. Clone/copy this folder under `MQL5/Experts/Gangplank Plunder Parrrley/`.
2. **Quick start:** attach the shipped `Gangplank Plunder Parrrley.ex5`. Refresh Navigator if needed.
3. **From source:** open `Gangplank Plunder Parrrley.mq5` in MetaEditor → Compile (F7).
4. Attach to **XAUUSD** (or any symbol containing `XAUUSD`, e.g. `XAUUSD_ExnessPro`) on **D1**. Enable Algo Trading.

## Inputs (friendly names)

| Group | What you touch |
|---|---|
| Symbol / template | Filter, D1 swing lookback, cluster, min level sep, near zones |
| Major Trend | Max ladder, season months, one-direction, lock template |
| Risk / SL | Risk %, lot decay, budget, **Fixed / BEP / TrailLadder**, max SL ATR |

## Disclaimer

Past backtests are not a promise of future profit. Only **14** trades in ~4.5 years — high PF, small sample. Equity DD near **27%** occurred on the published Fixed stand. Use money you can afford to risk. This is research software, not financial advice.

## Author

**Randi Apriliyadi**  
Repository: [github.com/randiapriliyadiR/gangplank-plunder-parrley](https://github.com/randiapriliyadiR/gangplank-plunder-parrley)
