//+------------------------------------------------------------------+
//| GangplankPP/Levels.mqh — swing, cluster, major TP, chart draw    |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_LEVELS_MQH
#define GANGPLANKPP_LEVELS_MQH

#include "Types.mqh"

void GppTemplateClear(SGppTemplate &tpl)
  {
   ZeroMemory(tpl);
  }

bool GppIsSwingHigh(const double &high[], const int i, const int n, const int bars)
  {
   if(bars < 1 || i < bars || i >= n - bars)
      return false;
   for(int k = 1; k <= bars; k++)
      if(high[i] <= high[i - k] || high[i] <= high[i + k])
         return false;
   return true;
  }

bool GppIsSwingLow(const double &low[], const int i, const int n, const int bars)
  {
   if(bars < 1 || i < bars || i >= n - bars)
      return false;
   for(int k = 1; k <= bars; k++)
      if(low[i] >= low[i - k] || low[i] >= low[i + k])
         return false;
   return true;
  }

double GppSwingReaction(const double &high[], const double &low[],
                        const int idx, const bool isHigh, const int bars)
  {
   const int from = idx - 1;
   if(from < 0 || bars <= 0)
      return 0.0;
   const int to = MathMax(0, idx - bars);
   double ext = isHigh ? low[from] : high[from];
   for(int i = from; i >= to; i--)
     {
      if(isHigh)
        {
         if(low[i] < ext)
            ext = low[i];
        }
      else
        {
         if(high[i] > ext)
            ext = high[i];
        }
     }
   return isHigh ? (high[idx] - ext) : (ext - low[idx]);
  }

int GppCollectSwings(const double &high[],
                     const double &low[],
                     const datetime &time[],
                     const int rates,
                     const int pivotBars,
                     SGppSwing &out[],
                     const int maxOut)
  {
   ArrayResize(out, 0);
   if(rates < pivotBars * 2 + 3 || pivotBars < 1)
      return 0;

   const int newest = pivotBars + 1; // confirmed swings only — skip forming D1 bar
   const int oldest = rates - 1 - pivotBars;
   if(oldest <= newest)
      return 0;

   int n = 0;
   for(int i = oldest; i >= newest; i--)
     {
      const bool sh = GppIsSwingHigh(high, i, rates, pivotBars);
      const bool sl = GppIsSwingLow(low, i, rates, pivotBars);
      if(sh && sl)
         continue;
      if(!sh && !sl)
         continue;
      if(n >= maxOut)
         break;
      const int sz = ArraySize(out);
      ArrayResize(out, sz + 1);
      out[sz].time     = time[i];
      out[sz].price    = sh ? high[i] : low[i];
      out[sz].isHigh   = sh;
      out[sz].reaction = GppSwingReaction(high, low, i, sh, MathMax(pivotBars * 10, 20));
      n++;
     }
   return n;
  }

bool GppFindPriorOppositeSwing(const SGppSwing &swings[],
                               const int count,
                               const datetime beforeTime,
                               const double breakPrice,
                               const bool wantLow,
                               double &price,
                               datetime &when)
  {
   price = 0.0;
   when  = 0;
   int best = -1;
   for(int i = 0; i < count; i++)
     {
      if(swings[i].time >= beforeTime)
         continue;
      if(wantLow)
        {
         if(swings[i].isHigh)
            continue;
         if(swings[i].price >= breakPrice)
            continue;
        }
      else
        {
         if(!swings[i].isHigh)
            continue;
         if(swings[i].price <= breakPrice)
            continue;
        }
      if(best < 0 || swings[i].time > swings[best].time)
         best = i;
     }
   if(best < 0)
      return false;
   price = swings[best].price;
   when  = swings[best].time;
   return true;
  }

bool GppSwingInBox(const SGppSwing &sw, const datetime t0, const datetime t1,
                   const double lo, const double hi, const bool wantLow)
  {
   if(sw.time <= t0 || sw.time >= t1)
      return false;
   if(sw.price <= lo || sw.price >= hi)
      return false;
   if(wantLow && sw.isHigh)
      return false;
   if(!wantLow && !sw.isHigh)
      return false;
   return true;
  }

bool GppFindSwingInBox(const SGppSwing &swings[],
                       const int count,
                       const datetime otherTime,
                       const datetime breakTime,
                       const double otherPrice,
                       const double breakPrice,
                       const bool wantLow,
                       const bool deeper,
                       double &price,
                       datetime &when)
  {
   price = 0.0;
   when  = 0;
   const datetime t0 = (otherTime < breakTime ? otherTime : breakTime);
   const datetime t1 = (otherTime < breakTime ? breakTime : otherTime);
   const double lo = MathMin(otherPrice, breakPrice);
   const double hi = MathMax(otherPrice, breakPrice);
   if(t1 <= t0 || hi <= lo)
      return false;

   int idx[];
   ArrayResize(idx, 0);
   for(int i = 0; i < count; i++)
     {
      if(!GppSwingInBox(swings[i], t0, t1, lo, hi, wantLow))
         continue;
      if(swings[i].time >= breakTime)
         continue;
      const int sz = ArraySize(idx);
      ArrayResize(idx, sz + 1);
      idx[sz] = i;
     }

   if(ArraySize(idx) == 0)
     {
      for(int i = 0; i < count; i++)
        {
         if(swings[i].time >= breakTime)
            continue;
         if(swings[i].price <= lo || swings[i].price >= hi)
            continue;
         if(wantLow && swings[i].isHigh)
            continue;
         if(!wantLow && !swings[i].isHigh)
            continue;
         const int sz = ArraySize(idx);
         ArrayResize(idx, sz + 1);
         idx[sz] = i;
        }
     }

   const int n = ArraySize(idx);
   if(n == 0)
      return false;

   for(int a = 0; a < n - 1; a++)
     {
      for(int b = a + 1; b < n; b++)
        {
         if(swings[idx[b]].time > swings[idx[a]].time)
           {
            const int tmp = idx[a];
            idx[a] = idx[b];
            idx[b] = tmp;
           }
        }
     }

   const int pick = (deeper && n >= 2) ? 1 : 0;
   price = swings[idx[pick]].price;
   when  = swings[idx[pick]].time;
   return true;
  }

void GppCopySwingsToTemplate(const SGppSwing &src[], SGppTemplate &tpl)
  {
   tpl.swingCount = MathMin(ArraySize(src), GPP_MAX_SWINGS);
   for(int i = 0; i < tpl.swingCount; i++)
      tpl.swings[i] = src[i];
  }

void GppSortLevelsByPrice(SGppTemplate &tpl)
  {
   for(int i = 0; i < tpl.levelCount - 1; i++)
     {
      for(int j = i + 1; j < tpl.levelCount; j++)
        {
         if(tpl.levels[j].price < tpl.levels[i].price)
           {
            SGppLevel tmp = tpl.levels[i];
            tpl.levels[i] = tpl.levels[j];
            tpl.levels[j] = tmp;
           }
        }
     }
  }

void GppKeepNearestLevels(SGppTemplate &tpl, const double price, const int nEach)
  {
   if(nEach <= 0 || tpl.levelCount <= 0)
      return;

   int below[];
   int above[];
   ArrayResize(below, 0);
   ArrayResize(above, 0);

   for(int i = tpl.levelCount - 1; i >= 0; i--)
     {
      if(tpl.levels[i].price >= price)
         continue;
      const int sz = ArraySize(below);
      ArrayResize(below, sz + 1);
      below[sz] = i;
      if(ArraySize(below) >= nEach)
         break;
     }

   for(int i = 0; i < tpl.levelCount; i++)
     {
      if(tpl.levels[i].price <= price)
         continue;
      const int sz = ArraySize(above);
      ArrayResize(above, sz + 1);
      above[sz] = i;
      if(ArraySize(above) >= nEach)
         break;
     }

   SGppLevel keep[];
   ArrayResize(keep, 0);
   for(int i = ArraySize(below) - 1; i >= 0; i--)
     {
      const int sz = ArraySize(keep);
      ArrayResize(keep, sz + 1);
      keep[sz] = tpl.levels[below[i]];
     }
   for(int i = 0; i < ArraySize(above); i++)
     {
      const int sz = ArraySize(keep);
      ArrayResize(keep, sz + 1);
      keep[sz] = tpl.levels[above[i]];
     }

   tpl.levelCount = ArraySize(keep);
   for(int i = 0; i < tpl.levelCount; i++)
      tpl.levels[i] = keep[i];
  }

double GppLevelStrength(const SGppLevel &lv)
  {
   return ((double)lv.hits * 10.0 + lv.reaction);
  }

void GppPruneCloseLevels(SGppTemplate &tpl, const double minSep)
  {
   if(minSep <= 0.0 || tpl.levelCount < 2)
      return;
   bool changed = true;
   while(changed)
     {
      changed = false;
      for(int i = 1; i < tpl.levelCount; i++)
        {
         if(tpl.levels[i].price - tpl.levels[i - 1].price >= minSep)
            continue;
         const int drop = (GppLevelStrength(tpl.levels[i]) < GppLevelStrength(tpl.levels[i - 1]))
                          ? i : i - 1;
         for(int k = drop; k < tpl.levelCount - 1; k++)
            tpl.levels[k] = tpl.levels[k + 1];
         tpl.levelCount--;
         changed = true;
         break;
        }
     }
  }

void GppClusterOneSide(SGppTemplate &tpl, const double tol, const double minReaction, const bool wantHigh)
  {
   bool used[];
   ArrayResize(used, tpl.swingCount);
   ArrayInitialize(used, false);

   for(int i = 0; i < tpl.swingCount; i++)
     {
      if(used[i])
         continue;
      if(tpl.swings[i].isHigh != wantHigh)
         continue;
      if(minReaction > 0.0 && tpl.swings[i].reaction < minReaction)
         continue;

      int members[];
      ArrayResize(members, 1);
      members[0] = i;
      used[i] = true;

      double extreme = tpl.swings[i].price;
      bool grew = true;
      while(grew)
        {
         grew = false;
         for(int k = 0; k < tpl.swingCount; k++)
           {
            if(used[k])
               continue;
            if(tpl.swings[k].isHigh != wantHigh)
               continue;
            if(MathAbs(tpl.swings[k].price - extreme) > tol)
               continue;
            used[k] = true;
            const int sz = ArraySize(members);
            ArrayResize(members, sz + 1);
            members[sz] = k;
            if(wantHigh)
              {
               if(tpl.swings[k].price > extreme)
                 {
                  extreme = tpl.swings[k].price;
                  grew = true;
                 }
              }
            else if(tpl.swings[k].price < extreme)
              {
               extreme = tpl.swings[k].price;
               grew = true;
              }
            else
               grew = true;
           }
        }

      int best = members[0];
      for(int m = 1; m < ArraySize(members); m++)
        {
         const int idx = members[m];
         const bool moreExtreme = wantHigh
                                  ? (tpl.swings[idx].price > tpl.swings[best].price)
                                  : (tpl.swings[idx].price < tpl.swings[best].price);
         const bool samePx = (MathAbs(tpl.swings[idx].price - tpl.swings[best].price) < 1e-9);
         if(moreExtreme || (samePx && tpl.swings[idx].reaction > tpl.swings[best].reaction))
            best = idx;
        }

      if(tpl.levelCount >= GPP_MAX_LEVELS)
         break;

      SGppLevel lv;
      ZeroMemory(lv);
      lv.price       = tpl.swings[best].price;
      lv.anchorTime  = tpl.swings[best].time;
      lv.anchorPrice = tpl.swings[best].price;
      lv.isHigh      = wantHigh;
      lv.hits        = ArraySize(members);
      lv.reaction    = tpl.swings[best].reaction;
      tpl.levels[tpl.levelCount++] = lv;
     }
  }

void GppClusterLevels(SGppTemplate &tpl, const double tol, const double minReaction)
  {
   tpl.levelCount = 0;
   if(tol <= 0.0 || tpl.swingCount <= 0)
      return;

   GppClusterOneSide(tpl, tol, minReaction, true);
   GppClusterOneSide(tpl, tol, minReaction, false);
   GppSortLevelsByPrice(tpl);
  }

bool GppFindRange(const SGppTemplate &tpl, const double price, const double minWidth, SGppRange &rg)
  {
   ZeroMemory(rg);
   int sup = -1;
   int res = -1;
   for(int i = 0; i < tpl.levelCount; i++)
     {
      const double p = tpl.levels[i].price;
      if(p < price)
        {
         if(sup < 0 || p > tpl.levels[sup].price)
            sup = i;
        }
      else if(p > price)
        {
         if(res < 0 || p < tpl.levels[res].price)
            res = i;
        }
     }
   if(sup < 0 || res < 0)
      return false;

   while(tpl.levels[res].price - tpl.levels[sup].price < minWidth)
     {
      int nextSup = -1;
      int nextRes = -1;
      for(int i = 0; i < tpl.levelCount; i++)
        {
         if(i < sup && (nextSup < 0 || tpl.levels[i].price > tpl.levels[nextSup].price))
            nextSup = i;
         if(i > res && (nextRes < 0 || tpl.levels[i].price < tpl.levels[nextRes].price))
            nextRes = i;
        }
      if(nextSup < 0 && nextRes < 0)
         break;
      const double dS = (nextSup >= 0 ? tpl.levels[sup].price - tpl.levels[nextSup].price : 1.0e100);
      const double dR = (nextRes >= 0 ? tpl.levels[nextRes].price - tpl.levels[res].price : 1.0e100);
      if(dR <= dS && nextRes >= 0)
         res = nextRes;
      else if(nextSup >= 0)
         sup = nextSup;
      else
         break;
     }

   rg.valid   = true;
   rg.supIdx  = sup;
   rg.resIdx  = res;
   rg.support = tpl.levels[sup].price;
   rg.resist  = tpl.levels[res].price;
   return true;
  }

int GppLevelsAbove(const SGppTemplate &tpl, const double price, int &idx[])
  {
   ArrayResize(idx, 0);
   for(int i = 0; i < tpl.levelCount; i++)
     {
      if(tpl.levels[i].price <= price)
         continue;
      const int sz = ArraySize(idx);
      ArrayResize(idx, sz + 1);
      idx[sz] = i;
     }
   return ArraySize(idx);
  }

int GppLevelsBelow(const SGppTemplate &tpl, const double price, int &idx[])
  {
   ArrayResize(idx, 0);
   for(int i = tpl.levelCount - 1; i >= 0; i--)
     {
      if(tpl.levels[i].price >= price)
         continue;
      const int sz = ArraySize(idx);
      ArrayResize(idx, sz + 1);
      idx[sz] = i;
     }
   return ArraySize(idx);
  }

int GppLevelsResistAbove(const SGppTemplate &tpl, const double price, int &idx[])
  {
   ArrayResize(idx, 0);
   for(int i = 0; i < tpl.levelCount; i++)
     {
      if(!tpl.levels[i].isHigh)
         continue;
      if(tpl.levels[i].price <= price)
         continue;
      const int sz = ArraySize(idx);
      ArrayResize(idx, sz + 1);
      idx[sz] = i;
     }
   return ArraySize(idx);
  }

int GppLevelsSupportBelow(const SGppTemplate &tpl, const double price, int &idx[])
  {
   ArrayResize(idx, 0);
   for(int i = tpl.levelCount - 1; i >= 0; i--)
     {
      if(tpl.levels[i].isHigh)
         continue;
      if(tpl.levels[i].price >= price)
         continue;
      const int sz = ArraySize(idx);
      ArrayResize(idx, sz + 1);
      idx[sz] = i;
     }
   return ArraySize(idx);
  }

double GppMajorBeyond(const SGppTemplate &tpl, const double from, const bool up)
  {
   double best = 0.0;
   double bestR = -1.0;
   bool found = false;
   for(int i = 0; i < tpl.levelCount; i++)
     {
      const double p = tpl.levels[i].price;
      if(up)
        {
         if(p <= from)
            continue;
        }
      else
        {
         if(p >= from)
            continue;
        }
      if(!found || tpl.levels[i].reaction > bestR ||
         (tpl.levels[i].reaction == bestR &&
          ((up && p > best) || (!up && p < best))))
        {
         best = p;
         bestR = tpl.levels[i].reaction;
         found = true;
        }
     }
   if(!found)
     {
      // farthest level beyond from
      for(int i = 0; i < tpl.levelCount; i++)
        {
         const double p = tpl.levels[i].price;
         if(up && p > from && (!found || p > best))
           {
            best = p;
            found = true;
           }
         if(!up && p < from && (!found || p < best))
           {
            best = p;
            found = true;
           }
        }
     }
   return (found ? best : 0.0);
  }

double GppComputeBuffer(const SGppCfg &cfg, const double atr, const double spread)
  {
   double buf = atr * cfg.breakBufferATR;
   const double point = SymbolInfoDouble(cfg.symbol, SYMBOL_POINT);
   if(cfg.breakBufferPoints > 0 && point > 0.0)
     {
      const double byPts = (double)cfg.breakBufferPoints * point;
      if(byPts > buf)
         buf = byPts;
     }
   const double bySpread = spread * 3.0;
   if(bySpread > buf)
      buf = bySpread;
   if(buf <= 0.0 && point > 0.0)
      buf = 10.0 * point;
   return buf;
  }

bool GppBuildTemplate(const SGppCfg &cfg,
                      const double &high[],
                      const double &low[],
                      const datetime &time[],
                      const int rates,
                      const double atr,
                      const double midPrice,
                      const double spread,
                      SGppTemplate &tpl)
  {
   GppTemplateClear(tpl);
   if(atr <= 0.0 || rates < 20)
      return false;

   SGppSwing raw[];
   if(GppCollectSwings(high, low, time, rates, cfg.pivotBars, raw, GPP_MAX_SWINGS) < 2)
      return false;

   GppCopySwingsToTemplate(raw, tpl);
   tpl.atr    = atr;
   tpl.buffer = GppComputeBuffer(cfg, atr, spread);

   const double minReac = atr * cfg.minReactionATR;
   const double tol     = atr * cfg.clusterATR;
   const double minSep  = atr * cfg.minLevelSepATR;
   GppClusterLevels(tpl, tol, minReac);
   GppPruneCloseLevels(tpl, minSep);
   GppKeepNearestLevels(tpl, midPrice, cfg.nearLevels);
   if(tpl.levelCount < 2)
      return false;

   const double minWidth = MathMax(minSep, atr * 0.8);
   if(!GppFindRange(tpl, midPrice, minWidth, tpl.range))
      return false;

   // Shared major TP: strongest level beyond the last ladder rung zone
   int above[];
   int below[];
   GppLevelsResistAbove(tpl, midPrice, above);
   GppLevelsSupportBelow(tpl, midPrice, below);
   const int maxL = MathMax(1, cfg.maxLadder);
   double buyBeyond = midPrice;
   double sellBeyond = midPrice;
   if(ArraySize(above) > 0)
     {
      const int last = MathMin(ArraySize(above), maxL) - 1;
      buyBeyond = tpl.levels[above[last]].price;
     }
   if(ArraySize(below) > 0)
     {
      const int last = MathMin(ArraySize(below), maxL) - 1;
      sellBeyond = tpl.levels[below[last]].price;
     }

   tpl.tpBuy  = GppMajorBeyond(tpl, buyBeyond, true);
   tpl.tpSell = GppMajorBeyond(tpl, sellBeyond, false);

   // Fallback: if no major beyond ladder, use next level after last rung
   if(tpl.tpBuy <= 0.0 && ArraySize(above) > maxL)
      tpl.tpBuy = tpl.levels[above[maxL]].price;
   if(tpl.tpSell <= 0.0 && ArraySize(below) > maxL)
      tpl.tpSell = tpl.levels[below[maxL]].price;

   tpl.lockBar   = iTime(cfg.symbol, cfg.tf, 1);
   tpl.lockPrice = midPrice;
   tpl.valid = true;
   return true;
  }

void GppDeleteChart(const string prefix)
  {
   const int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      const string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
     }
  }

void GppDrawTemplate(const SGppCfg &cfg, const SGppTemplate &tpl)
  {
   const string prefix = "GPP_";
   if(!cfg.drawTemplate || !tpl.valid)
     {
      GppDeleteChart(prefix);
      return;
     }
   // Skip heavy chart objects in non-visual tester (huge tick volume)
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;

   GppDeleteChart(prefix);

   const datetime t1 = iTime(cfg.symbol, cfg.tf, MathMin(cfg.lookback - 1, 80));
   const datetime t2 = iTime(cfg.symbol, cfg.tf, 0);
   if(t1 == 0 || t2 == 0)
      return;

   for(int i = 0; i < tpl.levelCount; i++)
     {
      const string n = prefix + "L" + IntegerToString(i);
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, tpl.levels[i].price);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }

   if(tpl.tpBuy > 0.0)
     {
      const string n = prefix + "TPB";
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, tpl.tpBuy);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }
   if(tpl.tpSell > 0.0)
     {
      const string n = prefix + "TPS";
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, tpl.tpSell);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }

   if(tpl.range.valid)
     {
      const string box = prefix + "RANGE";
      ObjectCreate(0, box, OBJ_RECTANGLE, 0, t1, tpl.range.support, t2, tpl.range.resist);
      ObjectSetInteger(0, box, OBJPROP_COLOR, clrDarkSlateGray);
      ObjectSetInteger(0, box, OBJPROP_FILL, true);
      ObjectSetInteger(0, box, OBJPROP_BGCOLOR, C'28,36,48');
      ObjectSetInteger(0, box, OBJPROP_BACK, true);
      ObjectSetInteger(0, box, OBJPROP_SELECTABLE, false);
     }
   ChartRedraw(0);
  }

int GppLevelsSelfTest(void)
  {
   int fail = 0;
   SGppSwing sw[];
   ArrayResize(sw, 4);
   sw[0].time = 100; sw[0].price = 4140.0; sw[0].isHigh = false; sw[0].reaction = 20;
   sw[1].time = 150; sw[1].price = 4264.0; sw[1].isHigh = false; sw[1].reaction = 15;
   sw[2].time = 200; sw[2].price = 4385.0; sw[2].isHigh = true;  sw[2].reaction = 18;
   sw[3].time = 250; sw[3].price = 4748.0; sw[3].isHigh = true;  sw[3].reaction = 40;

   double px = 0.0;
   datetime t = 0;
   if(!GppFindPriorOppositeSwing(sw, 4, 200, 4385.0, true, px, t))
     { Print("GPP selftest: missing prior swing"); fail++; }
   else if(MathAbs(px - 4264.0) > 1e-9)
     { Print("GPP selftest: SL swing want 4264 got ", px); fail++; }

   SGppTemplate tpl;
   GppTemplateClear(tpl);
   GppCopySwingsToTemplate(sw, tpl);
   GppClusterLevels(tpl, 5.0, 0.0);
   if(tpl.levelCount < 2)
     { Print("GPP selftest: cluster too small ", tpl.levelCount); fail++; }

   SGppRange rg;
   if(!GppFindRange(tpl, 4300.0, 10.0, rg) || !rg.valid)
     { Print("GPP selftest: range fail"); fail++; }

   const double maj = GppMajorBeyond(tpl, 4385.0, true);
   if(MathAbs(maj - 4748.0) > 1e-9)
     { Print("GPP selftest: major TP want 4748 got ", maj); fail++; }

   SGppSwing box[];
   ArrayResize(box, 5);
   box[0].time = 50;  box[0].price = 1930.0; box[0].isHigh = true;  box[0].reaction = 40;
   box[1].time = 100; box[1].price = 1768.0; box[1].isHigh = false; box[1].reaction = 20;
   box[2].time = 120; box[2].price = 1775.0; box[2].isHigh = false; box[2].reaction = 12;
   box[3].time = 150; box[3].price = 1786.0; box[3].isHigh = false; box[3].reaction = 15;
   box[4].time = 200; box[4].price = 1798.0; box[4].isHigh = true;  box[4].reaction = 18;
   px = 0.0;
   t  = 0;
   if(!GppFindSwingInBox(box, 5, 100, 200, 1768.0, 1798.0, true, true, px, t))
     { Print("GPP selftest: missing inner swing"); fail++; }
   else if(MathAbs(px - 1775.0) > 1e-9)
     { Print("GPP selftest: major inner SL want 1775 got ", px); fail++; }

   SGppTemplate tight;
   GppTemplateClear(tight);
   tight.levelCount = 3;
   tight.levels[0].price = 1848; tight.levels[0].hits = 1; tight.levels[0].reaction = 5;
   tight.levels[1].price = 1855; tight.levels[1].hits = 1; tight.levels[1].reaction = 4;
   tight.levels[2].price = 1862; tight.levels[2].hits = 2; tight.levels[2].reaction = 8;
   GppPruneCloseLevels(tight, 20.0);
   if(tight.levelCount != 1)
     { Print("GPP selftest: dempet prune want 1 got ", tight.levelCount); fail++; }

   return fail;
  }

#endif
//+------------------------------------------------------------------+
