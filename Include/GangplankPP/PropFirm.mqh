//+------------------------------------------------------------------+
//| GangplankPP/PropFirm.mqh — challenge: +target vs daily/max DD    |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_PROPFIRM_MQH
#define GANGPLANKPP_PROPFIRM_MQH

#include "Types.mqh"
#include "Orders.mqh"

enum ENUM_GPP_PROP_STATE
  {
   GPP_PROP_OFF        = 0,
   GPP_PROP_RUNNING    = 1,
   GPP_PROP_PASS       = 2,
   GPP_PROP_FAIL_DAILY = 3,
   GPP_PROP_FAIL_MAX   = 4
  };

struct SGppProp
  {
   bool               enabled;
   double             dailyDdPct;   // e.g. 3
   double             maxDdPct;     // e.g. 10
   double             targetPct;    // e.g. 10
   double             startEquity;  // challenge start (max DD floor)
   double             dayStartEq;   // equity at day open
   datetime           dayStamp;     // D1 bar time of current day
   ENUM_GPP_PROP_STATE state;
   datetime           eventTime;
   string             eventNote;
  };

SGppProp g_prop;

datetime GppDayStamp(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

string GppPropStateName(const ENUM_GPP_PROP_STATE st)
  {
   switch(st)
     {
      case GPP_PROP_RUNNING:    return "RUNNING";
      case GPP_PROP_PASS:       return "PASS +target";
      case GPP_PROP_FAIL_DAILY: return "FAIL daily DD";
      case GPP_PROP_FAIL_MAX:   return "FAIL max DD";
      default:                  return "OFF";
     }
  }

void GppCloseAllPositions(const SGppCfg &cfg)
  {
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
      if(!g_gppTrade.PositionClose(ticket))
         Print("GPP prop: close fail ", ticket, " ",
               g_gppTrade.ResultRetcodeDescription());
     }
  }

void GppPropHalt(const SGppCfg &cfg, const ENUM_GPP_PROP_STATE st, const string note)
  {
   if(g_prop.state != GPP_PROP_RUNNING)
      return;
   g_prop.state     = st;
   g_prop.eventTime = TimeCurrent();
   g_prop.eventNote = note;
   GppCancelAllPendings(cfg);
   GppCloseAllPositions(cfg);
   Print("GPP PROP ", GppPropStateName(st), " | ", note,
         " | eq=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
         " start=", DoubleToString(g_prop.startEquity, 2),
         " dayStart=", DoubleToString(g_prop.dayStartEq, 2));
  }

void GppPropInit(const bool enabled,
                 const double dailyPct,
                 const double maxPct,
                 const double targetPct)
  {
   ZeroMemory(g_prop);
   g_prop.enabled    = enabled;
   g_prop.dailyDdPct = dailyPct;
   g_prop.maxDdPct   = maxPct;
   g_prop.targetPct  = targetPct;
   if(!enabled)
     {
      g_prop.state = GPP_PROP_OFF;
      return;
     }
   g_prop.startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_prop.startEquity <= 0.0)
      g_prop.startEquity = AccountInfoDouble(ACCOUNT_BALANCE);
   g_prop.dayStartEq = g_prop.startEquity;
   g_prop.dayStamp   = GppDayStamp(TimeCurrent());
   g_prop.state      = GPP_PROP_RUNNING;
   Print("GPP PROP challenge ON | startEq=", DoubleToString(g_prop.startEquity, 2),
         " daily=", DoubleToString(dailyPct, 2), "% max=", DoubleToString(maxPct, 2),
         "% target=+", DoubleToString(targetPct, 2), "%");
  }

// Returns true if trading allowed.
bool GppPropAllowTrade(void)
  {
   if(!g_prop.enabled)
      return true;
   return (g_prop.state == GPP_PROP_RUNNING);
  }

void GppPropOnTick(const SGppCfg &cfg)
  {
   if(!g_prop.enabled || g_prop.state != GPP_PROP_RUNNING)
      return;

   const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0)
      return;

   const datetime day = GppDayStamp(TimeCurrent());
   if(day != g_prop.dayStamp)
     {
      g_prop.dayStamp   = day;
      g_prop.dayStartEq = eq;
     }

   // Max DD: from challenge start equity (static floor).
   if(g_prop.maxDdPct > 0.0 && g_prop.startEquity > 0.0)
     {
      const double floorEq = g_prop.startEquity * (1.0 - g_prop.maxDdPct / 100.0);
      if(eq <= floorEq)
        {
         GppPropHalt(cfg, GPP_PROP_FAIL_MAX,
                     StringFormat("max DD hit eq=%.2f floor=%.2f (%.2f%% from start)",
                                  eq, floorEq, g_prop.maxDdPct));
         return;
        }
     }

   // Daily DD: from equity at start of that day.
   if(g_prop.dailyDdPct > 0.0 && g_prop.dayStartEq > 0.0)
     {
      const double dayFloor = g_prop.dayStartEq * (1.0 - g_prop.dailyDdPct / 100.0);
      if(eq <= dayFloor)
        {
         GppPropHalt(cfg, GPP_PROP_FAIL_DAILY,
                     StringFormat("daily DD hit eq=%.2f dayFloor=%.2f (%.2f%% from day start %.2f)",
                                  eq, dayFloor, g_prop.dailyDdPct, g_prop.dayStartEq));
         return;
        }
     }

   // Target profit first.
   if(g_prop.targetPct > 0.0 && g_prop.startEquity > 0.0)
     {
      const double targetEq = g_prop.startEquity * (1.0 + g_prop.targetPct / 100.0);
      if(eq >= targetEq)
        {
         GppPropHalt(cfg, GPP_PROP_PASS,
                     StringFormat("target +%.2f%% hit eq=%.2f need=%.2f",
                                  g_prop.targetPct, eq, targetEq));
         return;
        }
     }
  }

#endif
//+------------------------------------------------------------------+
