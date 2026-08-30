# Prop two-phase risk + daily buffer

**Goal:** Pass +10% challenge, then keep prop rules ON for the full backtest without FAIL daily 3% / max 10%.

## Behavior

1. **Phase 1 (pre-target):** size with `InpRiskPct` (default 1%).
2. **Phase 2 (after +target logged, HaltOnTarget=false):** size with `InpPropRiskAfterPass` (default 0.35%). Cancel open pendings once on PASS so next arm uses lower risk.
3. **Daily buffer:** if remaining room to daily floor < `InpPropDailyBufferPct` (default 0.75%), flatten positions + cancel pendings. Once per day, roll `dayStartEq` to post-flatten equity (rescue) so the run can continue without terminal daily FAIL.
4. Max DD floor remains startEquity × (1 − 10%). Challenge PASS with HaltOnTarget=true unchanged for strict preset.

## Success / findings (Model 4)

- Prop ON full curve: **RUNNING to end**, no daily/max FAIL; equity DD ~5.7%.
- Real-ticks peak before buffer ~+9.3% (does not always print +10% PASS). OHLC halt preset still shows classic PASS.
