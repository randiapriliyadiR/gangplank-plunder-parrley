//+------------------------------------------------------------------+
//| GangplankPP/Manage.mqh — Fixed / BEP / TrailLadder               |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_MANAGE_MQH
#define GANGPLANKPP_MANAGE_MQH

#include "Orders.mqh"

bool GppMoreSafe(const bool isBuy, const double curSl, const double newSl)
  {
   if(newSl <= 0.0)
      return false;
   if(curSl <= 0.0)
      return true;
   if(isBuy)
      return (newSl > curSl + 1e-9);
   return (newSl < curSl - 1e-9);
  }

bool GppHasFilledLadder(const SGppCfg &cfg, const bool isBuy, const int ladder)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != cfg.magic)
         continue;
      bool buy;
      int lad;
      if(!GppParseComment(PositionGetString(POSITION_COMMENT), buy, lad))
         continue;
      if(buy == isBuy && lad == ladder)
         return true;
     }
   return false;
  }

void GppModifyPositionsLadder(const SGppCfg &cfg,
                              const bool isBuy,
                              const int ladder,
                              const double newSl,
                              const bool toBreakeven)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != cfg.magic)
         continue;

      bool buy;
      int lad;
      if(!GppParseComment(PositionGetString(POSITION_COMMENT), buy, lad))
         continue;
      if(buy != isBuy || lad != ladder)
         continue;

      const double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      const double curSl = PositionGetDouble(POSITION_SL);
      const double curTp = PositionGetDouble(POSITION_TP);

      double sl = toBreakeven ? open : newSl;
      if(!GppMoreSafe(isBuy, curSl, sl))
         continue;

      double tp = curTp;
      GppAdjustStops(cfg.symbol, isBuy, open, sl, tp);
      if(!GppMoreSafe(isBuy, curSl, sl))
         continue;

      g_gppTrade.SetExpertMagicNumber((uint)cfg.magic);
      if(!g_gppTrade.PositionModify(ticket, sl, curTp))
         Print("GPP: manage fail ", PositionGetString(POSITION_COMMENT), " ",
               g_gppTrade.ResultRetcodeDescription());
     }
  }

void GppManageOpen(const SGppCfg &cfg, const SGppPlan &plan)
  {
   // Enforce is called from OnTick only when book changes — keep Manage light
   if(cfg.slMode == GPP_SL_FIXED)
      return;

   if(GppCountPositions(cfg.symbol, cfg.magic) <= 0)
      return;

   // For each direction, find highest filled ladder; move lower ladders
   for(int dir = 0; dir < 2; dir++)
     {
      const bool isBuy = (dir == 0);
      int maxFilled = 0;
      for(int lad = 1; lad <= cfg.maxLadder + 2; lad++)
        {
         if(GppHasFilledLadder(cfg, isBuy, lad))
            maxFilled = lad;
        }
      if(maxFilled <= 1)
         continue;

      const int trigger = maxFilled; // newest filled rung
      const int idx = GppFindSlot(plan, isBuy, trigger);
      double trailSl = 0.0;
      if(idx >= 0)
         trailSl = plan.slots[idx].sl;

      for(int lower = 1; lower < trigger; lower++)
        {
         if(cfg.slMode == GPP_SL_BEP)
            GppModifyPositionsLadder(cfg, isBuy, lower, 0.0, true);
         else if(cfg.slMode == GPP_SL_TRAIL && trailSl > 0.0)
            GppModifyPositionsLadder(cfg, isBuy, lower, trailSl, false);
        }
     }
  }

#endif
//+------------------------------------------------------------------+
