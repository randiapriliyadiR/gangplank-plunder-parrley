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
   bool               haltOnTarget; // if false: log PASS then keep trading (full report)
   double             dailyDdPct;
   double             maxDdPct;
   double             targetPct;
   double             riskAfterPass;
   double             dailyBufferPct;
   double             startEquity;
   double             dayStartEq;
   datetime           dayStamp;
   ENUM_GPP_PROP_STATE state;
   datetime           eventTime;
   string             eventNote;
   bool               targetLogged;
   bool               entriesPaused; // near daily floor buffer
   bool               flattenedPause; // already flattened for this pause episode
   bool               dailyRescued;   // rolled dayStart once after buffer flatten
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
                 const double targetPct,
                 const bool haltOnTarget,
                 const double riskAfterPass,
                 const double dailyBufferPct)
  {
   ZeroMemory(g_prop);
   g_prop.enabled        = enabled;
   g_prop.haltOnTarget   = haltOnTarget;
   g_prop.dailyDdPct     = dailyPct;
   g_prop.maxDdPct       = maxPct;
   g_prop.targetPct      = targetPct;
   g_prop.riskAfterPass  = riskAfterPass;
   g_prop.dailyBufferPct = dailyBufferPct;
   g_prop.targetLogged   = false;
   g_prop.entriesPaused  = false;
   g_prop.flattenedPause = false;
   g_prop.dailyRescued   = false;
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
         "% target=+", DoubleToString(targetPct, 2),
         "% haltOnTarget=", (haltOnTarget ? "yes" : "no"),
         " riskAfterPass=", DoubleToString(riskAfterPass, 2),
         "% dailyBuffer=", DoubleToString(dailyBufferPct, 2), "%");
  }

double GppActiveRiskPct(const SGppCfg &cfg)
  {
   if(!g_prop.enabled || !g_prop.targetLogged)
      return cfg.riskPct;
   if(g_prop.riskAfterPass > 0.0)
      return g_prop.riskAfterPass;
   return cfg.riskPct;
  }

bool GppPropAllowTrade(void)
  {
   if(!g_prop.enabled)
      return true;
   return (g_prop.state == GPP_PROP_RUNNING);
  }

bool GppPropAllowNewEntries(void)
  {
   if(!g_prop.enabled)
      return true;
   if(g_prop.state != GPP_PROP_RUNNING)
      return false;
   return !g_prop.entriesPaused;
  }

void GppPropUpdateEntryPause(const double eq)
  {
   g_prop.entriesPaused = false;
   if(!g_prop.enabled || g_prop.state != GPP_PROP_RUNNING)
      return;
   if(g_prop.dailyDdPct <= 0.0 || g_prop.dailyBufferPct <= 0.0 || g_prop.dayStartEq <= 0.0)
      return;
   const double dayFloor = g_prop.dayStartEq * (1.0 - g_prop.dailyDdPct / 100.0);
   const double pauseAt  = dayFloor + g_prop.dayStartEq * (g_prop.dailyBufferPct / 100.0);
   g_prop.entriesPaused  = (eq <= pauseAt);
  }

void GppPropOnTick(const SGppCfg &cfg)
  {
   if(!g_prop.enabled || g_prop.state != GPP_PROP_RUNNING)
      return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0)
      return;

   const datetime day = GppDayStamp(TimeCurrent());
   if(day != g_prop.dayStamp)
     {
      g_prop.dayStamp   = day;
      g_prop.dayStartEq = eq;
      g_prop.entriesPaused  = false;
      g_prop.flattenedPause = false;
      g_prop.dailyRescued   = false;
     }

   // Soft daily buffer first: flatten before hard FAIL can fire.
   GppPropUpdateEntryPause(eq);
   if(g_prop.entriesPaused && !g_prop.flattenedPause)
     {
      g_prop.flattenedPause = true;
      GppCancelAllPendings(cfg);
      GppCloseAllPositions(cfg);
      eq = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("GPP PROP daily buffer: flatten + pause new entries | eq=",
            DoubleToString(eq, 2),
            " dayStart=", DoubleToString(g_prop.dayStartEq, 2));
      // One roll per calendar day: new day-start after defensive flatten so
      // challenge can keep racing +target without terminal daily FAIL.
      if(!g_prop.dailyRescued && eq > 0.0)
        {
         g_prop.dailyRescued  = true;
         g_prop.dayStartEq    = eq;
         g_prop.entriesPaused = false;
         g_prop.flattenedPause = false;
         Print("GPP PROP daily rescue: roll dayStart to ", DoubleToString(eq, 2));
        }
     }
   if(!g_prop.entriesPaused)
      g_prop.flattenedPause = false;

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

   // Target: log first hit; optionally halt (lab usually continues for full curve).
   if(g_prop.targetPct > 0.0 && g_prop.startEquity > 0.0 && !g_prop.targetLogged)
     {
      const double targetEq = g_prop.startEquity * (1.0 + g_prop.targetPct / 100.0);
      if(eq >= targetEq)
        {
         g_prop.targetLogged = true;
         g_prop.eventTime = TimeCurrent();
         g_prop.eventNote = StringFormat("target +%.2f%% hit eq=%.2f need=%.2f",
                                         g_prop.targetPct, eq, targetEq);
         Print("GPP PROP PASS +target | ", g_prop.eventNote,
               " | halt=", (g_prop.haltOnTarget ? "yes" : "no (continue)"),
               " | riskNow=", DoubleToString(GppActiveRiskPct(cfg), 2), "%");
         if(g_prop.haltOnTarget)
           {
            GppPropHalt(cfg, GPP_PROP_PASS, g_prop.eventNote);
            return;
           }
         // Drop large pre-PASS pendings; next arm uses phase-2 risk.
         GppCancelAllPendings(cfg);
        }
     }
  }

#endif
//+------------------------------------------------------------------+
