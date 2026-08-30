# Prop two-phase risk Implementation Plan

> **For agentic workers:** implement task-by-task; checkboxes for tracking.

**Goal:** After prop +10% PASS, cut risk and pause entries near daily DD so full-curve prop ON does not FAIL.

**Architecture:** Config + `g_prop` hold after-pass risk and daily buffer; `GppActiveRiskPct` used in sizing; OnTick skips new arms when buffer pauses.

**Tech Stack:** MQL5 EA, MT5 Strategy Tester Model 4, lab export scripts.

## Global Constraints

- Version bump to 1.14
- ASCII labels in stands.json
- Model 4 real ticks for lab prop stand

---

### Task 1: Types + PropFirm helpers

- [ ] Add `propRiskAfterPass`, `propDailyBufferPct` to `SGppCfg` / defaults
- [ ] Extend `SGppProp`; implement `GppActiveRiskPct`, `GppPropAllowNewEntries`; cancel pendings on PASS continue; declare helpers in Types.mqh

### Task 2: Wire EA + Plan sizing

- [ ] Inputs + FillCfg + version 1.14
- [ ] `GppSizeSlots` uses `GppActiveRiskPct`
- [ ] OnTick: if !AllowNewEntries cancel pendings / skip sync; still manage opens

### Task 3: Preset, backtest, lab

- [ ] Update `.set` (HaltOnTarget=false for full prop lab; after-pass 0.4; buffer 0.4)
- [ ] Model 4 prop ON full run; export `prop_h4_100k`; README; push
