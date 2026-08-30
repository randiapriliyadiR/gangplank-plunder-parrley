//+------------------------------------------------------------------+
//| GangplankPP/Plan.mqh — dual ladder + shared major TP             |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_PLAN_MQH
#define GANGPLANKPP_PLAN_MQH

#include "Types.mqh"
#include "Levels.mqh"
#include "Risk.mqh"

void GppClampSlSwing(const SGppTemplate &tpl,
                     const SGppCfg &cfg,
                     const bool isBuy,
                     const int otherIdx,
                     const double breakPrice,
                     double &slSwing)
  {
   if(slSwing <= 0.0)
      return;
   const double maxDist = tpl.atr * MathMax(0.5, cfg.maxSlAtr);
   if(isBuy)
     {
      if(tpl.range.valid)
         slSwing = MathMax(slSwing, tpl.range.support);
      slSwing = MathMax(slSwing, breakPrice - maxDist);
      if(otherIdx >= 0 && otherIdx < tpl.levelCount && !tpl.levels[otherIdx].isHigh)
         slSwing = MathMax(slSwing, tpl.levels[otherIdx].price);
     }
   else
     {
      if(tpl.range.valid)
         slSwing = MathMin(slSwing, tpl.range.resist);
      slSwing = MathMin(slSwing, breakPrice + maxDist);
      if(otherIdx >= 0 && otherIdx < tpl.levelCount && tpl.levels[otherIdx].isHigh)
         slSwing = MathMin(slSwing, tpl.levels[otherIdx].price);
     }
  }

bool GppLookupSl(const SGppTemplate &tpl,
                 const SGppCfg &cfg,
                 const int breakIdx,
                 const int otherIdx,
                 const bool isBuy,
                 double &slSwing,
                 datetime &slTime)
  {
   slSwing = 0.0;
   slTime  = 0;
   if(breakIdx < 0 || breakIdx >= tpl.levelCount)
      return false;
   if(otherIdx < 0 || otherIdx >= tpl.levelCount)
      return false;

   const double breakPrice = tpl.levels[breakIdx].price;
   SGppSwing raw[];
   ArrayResize(raw, tpl.swingCount);
   for(int i = 0; i < tpl.swingCount; i++)
      raw[i] = tpl.swings[i];

   // Inner swing in range box (video) — nearest pullback, not deep history.
   if(GppFindSwingInBox(raw, tpl.swingCount,
                        tpl.levels[otherIdx].anchorTime,
                        tpl.levels[breakIdx].anchorTime,
                        tpl.levels[otherIdx].price,
                        tpl.levels[breakIdx].price,
                        isBuy, false, slSwing, slTime))
     {
      GppClampSlSwing(tpl, cfg, isBuy, otherIdx, breakPrice, slSwing);
      return (slSwing > 0.0);
     }

   // Box boundary fallback — never use distant prior swing outside the range.
   if(isBuy)
     {
      if(!tpl.levels[otherIdx].isHigh)
         slSwing = tpl.levels[otherIdx].price;
      else if(tpl.range.valid)
         slSwing = tpl.range.support;
      else
         slSwing = breakPrice - tpl.buffer * 4.0;
     }
   else
     {
      if(tpl.levels[otherIdx].isHigh)
         slSwing = tpl.levels[otherIdx].price;
      else if(tpl.range.valid)
         slSwing = tpl.range.resist;
      else
         slSwing = breakPrice + tpl.buffer * 4.0;
     }
   slTime = tpl.levels[otherIdx].anchorTime;
   GppClampSlSwing(tpl, cfg, isBuy, otherIdx, breakPrice, slSwing);
   return (slSwing > 0.0);
  }

bool GppAddSlot(SGppPlan &plan, const SGppSlot &slot)
  {
   if(!slot.valid)
      return false;
   if(plan.count >= GPP_MAX_SLOTS)
      return false;
   plan.slots[plan.count++] = slot;
   return true;
  }

bool GppFillSlot(const SGppCfg &cfg,
                 const SGppTemplate &tpl,
                 const bool isBuy,
                 const int ladder,
                 const int breakIdx,
                 const int otherIdx,
                 const double sharedTp,
                 SGppSlot &slot)
  {
   ZeroMemory(slot);
   if(breakIdx < 0 || breakIdx >= tpl.levelCount)
      return false;
   if(sharedTp <= 0.0)
      return false;

   const SGppLevel brk = tpl.levels[breakIdx];
   double slSwing = 0.0;
   datetime slTime = 0;
   if(!GppLookupSl(tpl, cfg, breakIdx, otherIdx, isBuy, slSwing, slTime))
      return false;

   const double buf = tpl.buffer;
   double entry = isBuy ? (brk.price + buf) : (brk.price - buf);
   double sl    = isBuy ? (slSwing - buf) : (slSwing + buf);
   double tp    = sharedTp;

   if(isBuy)
     {
      if(sl >= entry)
         return false;
      if(tp <= entry)
         return false;
     }
   else
     {
      if(sl <= entry)
         return false;
      if(tp >= entry)
         return false;
     }

   GppAdjustStops(cfg.symbol, isBuy, entry, sl, tp);

   slot.valid       = true;
   slot.isBuy       = isBuy;
   slot.ladder      = ladder;
   slot.entry       = GppNormalizePrice(cfg.symbol, entry);
   slot.sl          = sl;
   slot.tp          = tp;
   slot.slSwing     = slSwing;
   slot.slSwingTime = slTime;
   slot.breakPrice  = brk.price;
   slot.breakTime   = brk.anchorTime;
   slot.comment     = GppComment(isBuy, ladder);
   slot.lots        = 0.0;
   return true;
  }

bool GppSkipFirstRung(const SGppCfg &cfg,
                      const SGppTemplate &tpl,
                      const bool isBuy,
                      const int ladder,
                      const double bid)
  {
   if(ladder != 1 || !tpl.range.valid)
      return false;
   const double tol = tpl.atr * cfg.clusterATR;
   if(isBuy)
      return (bid >= tpl.range.resist - tol);
   return (bid <= tpl.range.support + tol);
  }

void GppSizeSlots(const SGppCfg &cfg, SGppPlan &plan)
  {
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   for(int i = 0; i < plan.count; i++)
     {
      double lots = GppLotsForRisk(cfg.symbol, equity, cfg.riskPct,
                                   plan.slots[i].entry, plan.slots[i].sl);
      if(plan.slots[i].ladder > 1 && cfg.lotDecay > 0.0)
         lots = GppNormalizeLots(cfg.symbol,
                                 lots * MathPow(cfg.lotDecay, plan.slots[i].ladder - 1));
      plan.slots[i].lots = lots;
     }
  }

bool GppIdxInArray(const int &arr[], const int idx)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == idx)
         return true;
   return false;
  }

void GppBuildPlan(const SGppCfg &cfg, const SGppTemplate &tpl, const double bid, SGppPlan &plan)
  {
   ZeroMemory(plan);
   if(!tpl.valid || !tpl.range.valid)
      return;
   if(!GppIsSeasonMonth(cfg, TimeCurrent()))
      return;

   int above[];
   int below[];
   GppLevelsResistAbove(tpl, bid, above);
   GppLevelsSupportBelow(tpl, bid, below);

   // Range box anchors: break atas = buy at resist, break bawah = sell at support.
   if(tpl.range.resIdx >= 0 && !GppIdxInArray(above, tpl.range.resIdx))
     {
      const int sz = ArraySize(above);
      ArrayResize(above, sz + 1);
      for(int i = sz; i > 0; i--)
         above[i] = above[i - 1];
      above[0] = tpl.range.resIdx;
     }
   if(tpl.range.supIdx >= 0 && !GppIdxInArray(below, tpl.range.supIdx))
     {
      const int sz = ArraySize(below);
      ArrayResize(below, sz + 1);
      for(int i = sz; i > 0; i--)
         below[i] = below[i - 1];
      below[0] = tpl.range.supIdx;
     }

   const int maxL = MathMax(1, cfg.maxLadder);

   for(int k = 0; k < ArraySize(above) && k < maxL; k++)
     {
      if(tpl.tpBuy <= 0.0)
         break;
      if(GppSkipFirstRung(cfg, tpl, true, k + 1, bid))
         continue;
      const int otherIdx = (k == 0 ? tpl.range.supIdx : above[k - 1]);
      SGppSlot slot;
      if(!GppFillSlot(cfg, tpl, true, k + 1, above[k], otherIdx, tpl.tpBuy, slot))
         continue;
      GppAddSlot(plan, slot);
     }

   for(int k = 0; k < ArraySize(below) && k < maxL; k++)
     {
      if(tpl.tpSell <= 0.0)
         break;
      if(GppSkipFirstRung(cfg, tpl, false, k + 1, bid))
         continue;
      const int otherIdx = (k == 0 ? tpl.range.resIdx : below[k - 1]);
      SGppSlot slot;
      if(!GppFillSlot(cfg, tpl, false, k + 1, below[k], otherIdx, tpl.tpSell, slot))
         continue;
      GppAddSlot(plan, slot);
     }

   GppSizeSlots(cfg, plan);
  }

int GppFindSlot(const SGppPlan &plan, const bool isBuy, const int ladder)
  {
   for(int i = 0; i < plan.count; i++)
     {
      if(!plan.slots[i].valid)
         continue;
      if(plan.slots[i].isBuy == isBuy && plan.slots[i].ladder == ladder)
         return i;
     }
   return -1;
  }

int GppPlanSelfTest(void)
  {
   int fail = 0;
   SGppCfg cfg;
   GppCfgInit(cfg);
   cfg.symbol = "XAUUSD";

   SGppTemplate tpl;
   GppTemplateClear(tpl);
   tpl.valid = true;
   tpl.atr = 10.0;
   tpl.buffer = 1.0;
   tpl.tpBuy = 4748.0;
   tpl.tpSell = 4000.0;
   tpl.swingCount = 5;
   tpl.swings[0].time = 50;  tpl.swings[0].price = 1930; tpl.swings[0].isHigh = true;
   tpl.swings[1].time = 100; tpl.swings[1].price = 1768; tpl.swings[1].isHigh = false;
   tpl.swings[2].time = 120; tpl.swings[2].price = 1775; tpl.swings[2].isHigh = false;
   tpl.swings[3].time = 150; tpl.swings[3].price = 1786; tpl.swings[3].isHigh = false;
   tpl.swings[4].time = 200; tpl.swings[4].price = 1798; tpl.swings[4].isHigh = true;
   tpl.levelCount = 4;
   tpl.levels[0].price = 1768; tpl.levels[0].anchorTime = 100; tpl.levels[0].isHigh = false;
   tpl.levels[1].price = 1798; tpl.levels[1].anchorTime = 200; tpl.levels[1].isHigh = true;
   tpl.levels[2].price = 1810; tpl.levels[2].anchorTime = 300; tpl.levels[2].isHigh = true;
   tpl.levels[3].price = 1850; tpl.levels[3].anchorTime = 400; tpl.levels[3].isHigh = true;
   tpl.range.valid = true;
   tpl.range.support = 1768;
   tpl.range.resist  = 1798;
   tpl.range.supIdx  = 0;
   tpl.range.resIdx  = 1;

   SGppSlot slot;
   if(!GppFillSlot(cfg, tpl, true, 1, 1, 0, tpl.tpBuy, slot))
     { Print("GPP plan selftest: fill buy failed"); fail++; }
   else if(MathAbs(slot.slSwing - 1786.0) > 1e-9)
     { Print("GPP plan selftest: nearest box SL want 1786 got ", slot.slSwing); fail++; }
   else if(slot.sl >= slot.entry)
     { Print("GPP plan selftest: buy SL must be below entry"); fail++; }
   else if(slot.sl < 1768.0 - 2.0)
     { Print("GPP plan selftest: buy SL below range support ", slot.sl); fail++; }
   else if(MathAbs(slot.entry - 1799.0) > 1.0)
     { Print("GPP plan selftest: buy entry want ~1799 got ", slot.entry); fail++; }

   return fail;
  }

#endif
//+------------------------------------------------------------------+
