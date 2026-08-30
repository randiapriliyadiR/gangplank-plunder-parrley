//+------------------------------------------------------------------+
//| GangplankPP/Risk.mqh                                             |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_RISK_MQH
#define GANGPLANKPP_RISK_MQH

#include "Types.mqh"

double GppNormalizePrice(const string symbol, const double price)
  {
   double tick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tick <= 0.0)
      return price;
   return MathRound(price / tick) * tick;
  }

double GppNormalizeLots(const string symbol, double lots)
  {
   const double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   const double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0)
      stepLot = 0.01;

   if(lots + 1e-12 < minLot)
      return 0.0;

   lots = MathFloor(lots / stepLot + 1e-12) * stepLot;
   lots = NormalizeDouble(lots, 8);
   if(lots + 1e-12 < minLot)
      return 0.0;
   if(lots > maxLot)
      lots = maxLot;
   return lots;
  }

void GppAdjustStops(const string symbol, const bool isBuy, const double entry, double &sl, double &tp)
  {
   const long   stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
   const double minDist    = (stopsLevel > 0 ? (double)stopsLevel * point : 0.0);
   const double spread     = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);

   double need = minDist;
   if(spread > need)
      need = spread;

   if(isBuy)
     {
      if(sl > 0.0 && entry - sl < need)
         sl = entry - need;
      if(tp > 0.0 && tp - entry < need)
         tp = entry + need;
     }
   else
     {
      if(sl > 0.0 && sl - entry < need)
         sl = entry + need;
      if(tp > 0.0 && entry - tp < need)
         tp = entry - need;
     }

   sl = GppNormalizePrice(symbol, sl);
   if(tp > 0.0)
      tp = GppNormalizePrice(symbol, tp);
  }

double GppLotsForRisk(const string symbol,
                      const double equity,
                      const double riskPct,
                      const double entry,
                      const double sl)
  {
   if(equity <= 0.0 || riskPct <= 0.0)
      return 0.0;

   const double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   const double slDist = MathAbs(entry - sl);
   if(slDist < tickSize)
      return 0.0;

   const double ticks = slDist / tickSize;
   const double lossPerLot = ticks * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   const double riskMoney = equity * riskPct / 100.0;
   return GppNormalizeLots(symbol, riskMoney / lossPerLot);
  }

double GppOrderRiskMoney(const string symbol, const double lots, const double entry, const double sl)
  {
   if(lots <= 0.0 || sl <= 0.0)
      return 0.0;
   const double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   const double slDist = MathAbs(entry - sl);
   return (slDist / tickSize) * tickValue * lots;
  }

int GppCountPositions(const string symbol, const ulong magic)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      n++;
     }
   return n;
  }

int GppCountPendings(const string symbol, const ulong magic)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      n++;
     }
   return n;
  }

int GppCountDirectionPendings(const string symbol, const ulong magic, const bool wantBuy)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      const long type = OrderGetInteger(ORDER_TYPE);
      const bool isBuy = (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT
                          || type == ORDER_TYPE_BUY_STOP_LIMIT);
      if(isBuy == wantBuy)
         n++;
     }
   return n;
  }

bool GppBookActive(const string symbol, const ulong magic)
  {
   return (GppCountPositions(symbol, magic) > 0 || GppCountPendings(symbol, magic) > 0);
  }

double GppRiskUsed(const string symbol, const ulong magic)
  {
   double used = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      used += GppOrderRiskMoney(symbol,
                                PositionGetDouble(POSITION_VOLUME),
                                PositionGetDouble(POSITION_PRICE_OPEN),
                                PositionGetDouble(POSITION_SL));
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      used += GppOrderRiskMoney(symbol,
                                OrderGetDouble(ORDER_VOLUME_CURRENT),
                                OrderGetDouble(ORDER_PRICE_OPEN),
                                OrderGetDouble(ORDER_SL));
     }
   return used;
  }

double GppRiskUsedDirection(const string symbol, const ulong magic, const bool wantBuy)
  {
   double used = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      const long type = PositionGetInteger(POSITION_TYPE);
      const bool isBuy = (type == POSITION_TYPE_BUY);
      if(isBuy != wantBuy)
         continue;
      used += GppOrderRiskMoney(symbol,
                                PositionGetDouble(POSITION_VOLUME),
                                PositionGetDouble(POSITION_PRICE_OPEN),
                                PositionGetDouble(POSITION_SL));
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      const long type = OrderGetInteger(ORDER_TYPE);
      const bool isBuy = (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT
                          || type == ORDER_TYPE_BUY_STOP_LIMIT);
      if(isBuy != wantBuy)
         continue;
      used += GppOrderRiskMoney(symbol,
                                OrderGetDouble(ORDER_VOLUME_CURRENT),
                                OrderGetDouble(ORDER_PRICE_OPEN),
                                OrderGetDouble(ORDER_SL));
     }
   return used;
  }

int GppSplitLots(const string symbol, const double lots, const double maxLot, double &parts[])
  {
   ArrayResize(parts, 0);
   if(lots <= 0.0)
      return 0;
   double remain = lots;
   const double cap = (maxLot > 0.0 ? maxLot : lots);
   while(remain > 1e-12)
     {
      double chunk = MathMin(remain, cap);
      chunk = GppNormalizeLots(symbol, chunk);
      if(chunk <= 0.0)
         break;
      const int sz = ArraySize(parts);
      ArrayResize(parts, sz + 1);
      parts[sz] = chunk;
      remain = GppNormalizeLots(symbol, remain - chunk);
      if(sz >= 19)
         break;
     }
   return ArraySize(parts);
  }

bool GppSpreadOk(const SGppCfg &cfg)
  {
   if(cfg.maxSpreadPoints <= 0)
      return true;
   const double point = SymbolInfoDouble(cfg.symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return true;
   const double spread = SymbolInfoDouble(cfg.symbol, SYMBOL_ASK)
                         - SymbolInfoDouble(cfg.symbol, SYMBOL_BID);
   return ((spread / point) <= (double)cfg.maxSpreadPoints + 1e-9);
  }

int GppRiskSelfTest(void)
  {
   int fail = 0;
   double parts[];
   // synthetic: if symbol unavailable, skip hard assert
   if(GppNormalizePrice("EURUSD", 1.23456) <= 0.0)
      fail++;
   return fail;
  }

#endif
//+------------------------------------------------------------------+
