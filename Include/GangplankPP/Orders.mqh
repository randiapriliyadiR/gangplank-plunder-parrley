//+------------------------------------------------------------------+
//| GangplankPP/Orders.mqh — Buy/Sell Stop sync                      |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_ORDERS_MQH
#define GANGPLANKPP_ORDERS_MQH

#include <Trade/Trade.mqh>
#include "Types.mqh"
#include "Plan.mqh"
#include "Risk.mqh"

CTrade g_gppTrade;

ENUM_ORDER_TYPE_FILLING GppFilling(const string symbol)
  {
   const long mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if((mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

void GppOrdersInit(const ulong deviation)
  {
   g_gppTrade.SetDeviationInPoints((uint)deviation);
   g_gppTrade.SetTypeFilling(GppFilling(_Symbol));
  }

bool GppNear(const double a, const double b, const double point)
  {
   const double eps = (point > 0.0 ? point * 2.0 : 1e-6);
   return (MathAbs(a - b) <= eps);
  }

bool GppPendingAllowed(const SGppSlot &slot, const double ask, const double bid)
  {
   if(slot.lots <= 0.0 || slot.entry <= 0.0 || slot.sl <= 0.0)
      return false;
   if(slot.isBuy)
      return (slot.entry > ask);
   return (slot.entry < bid);
  }

ulong GppFindPendingTicket(const string symbol, const ulong magic, const string comment)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      if(OrderGetString(ORDER_COMMENT) != comment)
         continue;
      return ticket;
     }
   return 0;
  }

bool GppHasPositionComment(const string symbol, const ulong magic, const string comment)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      if(PositionGetString(POSITION_COMMENT) == comment)
         return true;
     }
   return false;
  }

bool GppPlacePending(const SGppCfg &cfg, const SGppSlot &slot, const double lots, const string comment)
  {
   g_gppTrade.SetExpertMagicNumber((uint)cfg.magic);
   g_gppTrade.SetTypeFilling(GppFilling(cfg.symbol));
   const bool ok = slot.isBuy
                   ? g_gppTrade.BuyStop(lots, slot.entry, cfg.symbol, slot.sl, slot.tp,
                                        ORDER_TIME_GTC, 0, comment)
                   : g_gppTrade.SellStop(lots, slot.entry, cfg.symbol, slot.sl, slot.tp,
                                         ORDER_TIME_GTC, 0, comment);
   if(!ok)
      Print("GPP: pending fail ", comment, " lots=", lots, " ",
            g_gppTrade.ResultRetcode(), " ", g_gppTrade.ResultRetcodeDescription());
   return ok;
  }

bool GppModifyPending(const ulong ticket, const SGppSlot &slot, const double lots, const double point)
  {
   if(!OrderSelect(ticket))
      return false;
   const double curPx  = OrderGetDouble(ORDER_PRICE_OPEN);
   const double curSl  = OrderGetDouble(ORDER_SL);
   const double curTp  = OrderGetDouble(ORDER_TP);
   const double curVol = OrderGetDouble(ORDER_VOLUME_CURRENT);
   if(GppNear(curPx, slot.entry, point) &&
      GppNear(curSl, slot.sl, point) &&
      GppNear(curTp, slot.tp, point) &&
      MathAbs(curVol - lots) < 1e-8)
      return true;

   if(MathAbs(curVol - lots) >= 1e-8)
     {
      g_gppTrade.OrderDelete(ticket);
      return false;
     }
   return g_gppTrade.OrderModify(ticket, slot.entry, slot.sl, slot.tp, ORDER_TIME_GTC, 0);
  }

void GppDeleteStalePendings(const SGppCfg &cfg, const SGppPlan &plan)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != cfg.magic)
         continue;
      const string cmt = OrderGetString(ORDER_COMMENT);
      bool isBuy;
      int ladder;
      if(!GppParseComment(cmt, isBuy, ladder))
        {
         g_gppTrade.OrderDelete(ticket);
         continue;
        }
      if(GppFindSlot(plan, isBuy, ladder) < 0)
         g_gppTrade.OrderDelete(ticket);
     }
  }

bool GppBudgetAllows(const SGppCfg &cfg, const SGppSlot &slot, const bool dualArmIdle)
  {
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double cap = equity * cfg.budgetPct / 100.0;
   const double add = GppOrderRiskMoney(cfg.symbol, slot.lots, slot.entry, slot.sl);
   if(dualArmIdle && cfg.oneDirection)
     {
      const double half = cap * 0.5;
      const double dirUsed = GppRiskUsedDirection(cfg.symbol, cfg.magic, slot.isBuy);
      return (dirUsed + add <= half + 1e-6);
     }
   const double used = GppRiskUsed(cfg.symbol, cfg.magic);
   return (used + add <= cap + 1e-6);
  }

void GppSyncSlotLegs(const SGppCfg &cfg, const SGppSlot &slot, const double point,
                     const double ask, const double bid)
  {
   double parts[];
   const int n = GppSplitLots(cfg.symbol, slot.lots, cfg.maxLotPerOrder, parts);
   if(n <= 0)
      return;

   g_gppTrade.SetExpertMagicNumber((uint)cfg.magic);
   const int dirCap = MathMax(4, cfg.maxPending / 2);

   for(int leg = 1; leg <= n; leg++)
     {
      const string cmt = GppCommentLeg(slot.isBuy, slot.ladder, leg);
      const double lots = parts[leg - 1];
      if(GppHasPositionComment(cfg.symbol, cfg.magic, cmt))
         continue;

      const ulong ticket = GppFindPendingTicket(cfg.symbol, cfg.magic, cmt);
      if(!GppPendingAllowed(slot, ask, bid))
        {
         if(ticket > 0)
            g_gppTrade.OrderDelete(ticket);
         continue;
        }

      if(ticket > 0)
        {
         if(!GppModifyPending(ticket, slot, lots, point))
           {
            if(GppFindPendingTicket(cfg.symbol, cfg.magic, cmt) == 0)
              {
               if(GppCountDirectionPendings(cfg.symbol, cfg.magic, slot.isBuy) >= dirCap)
                  continue;
               if(GppCountPendings(cfg.symbol, cfg.magic) >= cfg.maxPending)
                  continue;
               GppPlacePending(cfg, slot, lots, cmt);
              }
           }
        }
      else
        {
         if(GppCountDirectionPendings(cfg.symbol, cfg.magic, slot.isBuy) >= dirCap)
            continue;
         if(GppCountPendings(cfg.symbol, cfg.magic) >= cfg.maxPending)
            continue;
         GppPlacePending(cfg, slot, lots, cmt);
        }
     }

   for(int extra = n + 1; extra <= 20; extra++)
     {
      const string cmt = GppCommentLeg(slot.isBuy, slot.ladder, extra);
      const ulong ticket = GppFindPendingTicket(cfg.symbol, cfg.magic, cmt);
      if(ticket == 0)
         break;
      g_gppTrade.OrderDelete(ticket);
     }

   const ulong old = GppFindPendingTicket(cfg.symbol, cfg.magic, slot.comment);
   if(old > 0 && n > 1)
      g_gppTrade.OrderDelete(old);
  }

void GppCancelAllPendings(const SGppCfg &cfg)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != cfg.magic)
         continue;
      g_gppTrade.SetExpertMagicNumber((uint)cfg.magic);
      g_gppTrade.OrderDelete(ticket);
     }
  }

bool GppHasDirectionPosition(const SGppCfg &cfg, const bool wantBuy)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != cfg.magic)
         continue;
      const long type = PositionGetInteger(POSITION_TYPE);
      if(wantBuy && type == POSITION_TYPE_BUY)
         return true;
      if(!wantBuy && type == POSITION_TYPE_SELL)
         return true;
     }
   return false;
  }

void GppCancelDirectionPendings(const SGppCfg &cfg, const bool cancelBuys)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != cfg.magic)
         continue;
      const long type = OrderGetInteger(ORDER_TYPE);
      const bool isBuy = (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT
                          || type == ORDER_TYPE_BUY_STOP_LIMIT);
      if(cancelBuys != isBuy)
         continue;
      g_gppTrade.SetExpertMagicNumber((uint)cfg.magic);
      g_gppTrade.OrderDelete(ticket);
     }
  }

int GppCloseDirectionPositions(const SGppCfg &cfg, const bool closeBuys)
  {
   int closed = 0;
   g_gppTrade.SetExpertMagicNumber((uint)cfg.magic);
   g_gppTrade.SetTypeFilling(GppFilling(cfg.symbol));
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != cfg.magic)
         continue;
      const long type = PositionGetInteger(POSITION_TYPE);
      const bool isBuy = (type == POSITION_TYPE_BUY);
      if(closeBuys != isBuy)
         continue;
      if(g_gppTrade.PositionClose(ticket))
         closed++;
      else
         Print("GPP: close opposite fail ", ticket, " ",
               g_gppTrade.ResultRetcodeDescription());
     }
   return closed;
  }

// Idle: buy+sell armed from range. After fill: same direction only (no hedge).
void GppEnforceOneDirection(const SGppCfg &cfg)
  {
   if(!cfg.oneDirection)
      return;

   int buyPos = 0, sellPos = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != cfg.symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != cfg.magic)
         continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buyPos++;
      else
         sellPos++;
     }

   // Pending only — both directions stay armed until a position opens.
   if(buyPos == 0 && sellPos == 0)
      return;

   if(buyPos > 0)
     {
      if(sellPos > 0)
         GppCloseDirectionPositions(cfg, false);
      GppCancelDirectionPendings(cfg, false);
      return;
     }

   if(sellPos > 0)
      GppCancelDirectionPendings(cfg, true);
  }

void GppSyncPendings(const SGppCfg &cfg, const SGppPlan &plan)
  {
   if(!GppSpreadOk(cfg))
     {
      GppCancelAllPendings(cfg);
      return;
     }

   if(!GppIsSeasonMonth(cfg, TimeCurrent()))
     {
      GppCancelAllPendings(cfg);
      return;
     }

   GppEnforceOneDirection(cfg);

   const double ask = SymbolInfoDouble(cfg.symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(cfg.symbol, SYMBOL_BID);
   const double point = SymbolInfoDouble(cfg.symbol, SYMBOL_POINT);

   GppDeleteStalePendings(cfg, plan);

   if(GppCountPositions(cfg.symbol, cfg.magic) >= cfg.maxPos)
      return;

   const bool hasBuy  = GppHasDirectionPosition(cfg, true);
   const bool hasSell = GppHasDirectionPosition(cfg, false);
   const bool dualArm = cfg.oneDirection && !hasBuy && !hasSell;
   const int maxL = MathMax(1, cfg.maxLadder);

   // Interleave buy/sell — idle arms both sides from range box.
   for(int rung = 1; rung <= maxL; rung++)
     {
      for(int side = 0; side < 2; side++)
        {
         const bool isBuy = (side == 0);
         if(cfg.oneDirection)
           {
            if(hasBuy && !isBuy)
               continue;
            if(hasSell && isBuy)
               continue;
           }
         const int idx = GppFindSlot(plan, isBuy, rung);
         if(idx < 0)
            continue;
         if(!plan.slots[idx].valid || plan.slots[idx].lots <= 0.0)
            continue;
         if(!GppBudgetAllows(cfg, plan.slots[idx], dualArm))
            continue;
         GppSyncSlotLegs(cfg, plan.slots[idx], point, ask, bid);
        }
     }
  }

#endif
//+------------------------------------------------------------------+
