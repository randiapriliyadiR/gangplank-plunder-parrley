# Gangplank Plunder Parrrley

<p align="center">
  <img src="media/gangplank.jpg" alt="Gangplank Plunder Parrrley — break the barrels, take the gold" width="520" />
</p>

> *"Parrrley? I'd rather plunder."*  
> An MT5 Expert Advisor named after Gangplank — Major Trend S/R ladders, shared yellow TP, Fixed / BEP / TrailLadder, plus an optional prop-firm challenge.

## Trade lab (GitHub Pages)

**URL:** [randiapriliyadir.github.io/gangplank-plunder-parrley](https://randiapriliyadir.github.io/gangplank-plunder-parrley/)

Interactive backtest explorer on **Exness Pro** ticks (`XAUUSD_ExnessPro`). Lab deposit: **$100,000**.

| Stand | Mode | Net | PF | Equity DD | WR | Trades |
|---|---|---:|---:|---:|---:|---:|
| **Prop H4** | Prop ON, 1%→0.35%, real ticks | **+$6,131** | **1.42** | **5.7%** | 53% | **32** |
| Fixed D1 | Full run, no prop halt | +$160,732 | 2.91 | 27.1% | 71% | 14 |
| BEP D1 | Break-even on next rung | +$126,320 | 2.67 | 36.0% | 62% | 13 |
| Trail D1 | Trail to next rung SL | +$122,359 | 2.57 | 37.2% | 62% | 13 |

Lab **Prop** = Model 4 **prop rules ON** full curve: phase-2 risk after +target, daily buffer flatten (0.75%), no daily/max FAIL in sample. Peak ~+9.3% before buffer on real ticks; classic **+10% PASS** still shown on OHLC halt preset. Preset: [`Presets/GPP_XAU_H4_PropPass.set`](Presets/GPP_XAU_H4_PropPass.set).

## What it is

**Gangplank Plunder Parrrley** places **Buy Stop / Sell Stop** ladders on automatic support/resistance (range-box). Idle = both sides armed; after one side fills, focus that direction. Shared major TP (yellow).

Default template: **H4** (best equity stand). Optional **prop challenge**: race +target vs daily/max equity DD, then halt.

## Prop firm preset

| Setting | Value |
|---|---|
| File | `Presets/GPP_XAU_H4_PropPass.set` |
| Template TF | **H4** |
| Risk / trade | **1%** (`OrderCalcProfit` lots) |
| Budget | 15% |
| Daily DD | **3%** from day-start equity |
| Max DD | **10%** from challenge-start equity |
| Target | **+10%** (phase-2 risk after hit if HaltOnTarget=false) |
| After PASS risk | **0.35%** |
| Daily buffer | **0.75%** room → flatten + pause (1× dayStart roll) |
| SL mode | Fixed |
| Verified | Model 4 full prop ON: **no FAIL**; OHLC halt PASS 2023.03.13 |

Load: attach EA → Inputs → **Load** → pick the `.set`.

## Install (MT5)

1. Clone/copy this folder under `MQL5/Experts/Gangplank Plunder Parrrley/`.
2. Compile `Gangplank Plunder Parrrley.mq5` (F7) or use shipped `.ex5`.
3. Attach to **XAUUSD*** on **H4** (or any chart; template TF is an input). Enable Algo Trading.
4. For prop rules: load `Presets/GPP_XAU_H4_PropPass.set`.

## Inputs (friendly names)

| Group | What you touch |
|---|---|
| Symbol / template | Filter, TF, swing lookback, cluster, near zones |
| Major Trend | Max ladder, season, one-direction, lock template |
| Risk / SL | Risk %, budget, **Fixed / BEP / TrailLadder**, max SL ATR |
| Prop firm challenge | Enable race, daily %, max %, target % |

## Disclaimer

Past backtests are not a promise of future profit. Lab Prop H4 uses **Every tick based on real ticks** with prop guards. Use money you can afford to risk. This is research software, not financial advice.

## Author

**Randi Apriliyadi** — [github.com/randiapriliyadiR](https://github.com/randiapriliyadiR)
