//+------------------------------------------------------------------+
//|                                   Gangplank Plunder Parrrley.mq5 |
//|                                                 Randi Apriliyadi |
//|                  https://github.com/randiapriliyadiR             |
//+------------------------------------------------------------------+
#property copyright "Randi Apriliyadi"
#property link      "https://github.com/randiapriliyadiR"
#property version   "1.06"
#property strict
#property description "Gangplank Plunder Parrrley — range dual-arm; one direction after fill"

#include "Include/GangplankPP/Types.mqh"
#include "Include/GangplankPP/Levels.mqh"
#include "Include/GangplankPP/Plan.mqh"
#include "Include/GangplankPP/Risk.mqh"
#include "Include/GangplankPP/Orders.mqh"
#include "Include/GangplankPP/Manage.mqh"
#include "Include/GangplankPP/Panel.mqh"

input group "=== Symbol / template ==="
input string          InpSymbol            = "XAUUSD";   // Chart symbol must contain this
input ENUM_TIMEFRAMES InpTemplateTF        = PERIOD_D1;  // Template timeframe
input int             InpPivotBars         = 3;          // Swing pivot left/right
input int             InpLookback          = 180;        // D1 bars to scan
input int             InpNearLevels        = 3;          // Nearest S and R each (Major zones)
input int             InpAtrPeriod         = 14;         // ATR period
input double          InpMinReactionATR    = 0.8;        // Min swing reaction (ATR)
input double          InpClusterATR        = 0.80;       // Merge swings into SnR zone (ATR)
input double          InpMinLevelSepATR    = 1.0;        // Min gap between ladder lines (ATR)
input double          InpBreakBufferATR    = 0.15;       // Entry/SL buffer (ATR)
input int             InpBreakBufferPoints = 0;          // Extra buffer in points (0=ATR only)
input bool            InpDrawTemplate      = true;       // Draw S/R + major TP

input group "=== Major Trend ==="
input int             InpMaxLadder         = 3;          // Pending rungs each side (major zones)
input bool            InpUseSeasonFilter   = false;      // Filter by season months
input string          InpSeasonMonths      = "1,2,3,4,5,6,7,8,9,10,11,12"; // Allow-list if filter on
input bool            InpOneDirection      = true;       // Idle: buy+sell; after fill: one side only
input bool            InpLockTemplate      = true;       // Lock S/R lines + plan until flat (no repaint)

input group "=== Risk / SL ==="
input double          InpRiskPct           = 2.0;        // Risk % equity per trade
input double          InpLotDecay          = 0.85;       // Lot multiplier per higher rung
input double          InpBudgetPct         = 30.0;       // Max risk budget % equity (split 50/50 idle)
input double          InpMaxSlAtr        = 2.5;        // Max SL distance from break level (ATR)
input ENUM_GPP_SL_MODE InpSlMode           = GPP_SL_FIXED; // Fixed | BEP | TrailLadder
input int             InpMaxSpreadPoints   = 80;         // Max spread (points)
input ulong           InpDeviation         = 30;         // Max slippage (points)
input double          InpMaxLotPerOrder    = 10.0;       // Split if lots exceed this
input int             InpMaxPending        = 40;         // Max pending (split per direction)
input int             InpMaxPos            = 24;         // Max positions
input ulong           InpMagic             = 26083001;   // Magic number

SGppCfg      g_cfg;
SGppTemplate g_tpl;
SGppPlan     g_plan;
SGppView     g_view;
int          g_atrHandle = INVALID_HANDLE;
datetime     g_lastD1    = 0;
datetime     g_lastUiSec = 0;
datetime     g_lastArmSec = 0;
int          g_lastPosN  = -1;
int          g_lastOrdN  = -1;

bool GppSymbolAllowed(void)
  {
   if(InpSymbol == "")
      return true;
   return (StringFind(_Symbol, InpSymbol) >= 0);
  }

bool GppFillCfg(SGppCfg &c)
  {
   GppCfgInit(c);
   c.symbol            = _Symbol;
   c.tf                = InpTemplateTF;
   c.pivotBars         = InpPivotBars;
   c.lookback          = InpLookback;
   c.atrPeriod         = InpAtrPeriod;
   c.minReactionATR    = InpMinReactionATR;
   c.clusterATR        = InpClusterATR;
   c.minLevelSepATR    = InpMinLevelSepATR;
   c.nearLevels        = InpNearLevels;
   c.breakBufferATR    = InpBreakBufferATR;
   c.breakBufferPoints = InpBreakBufferPoints;
   c.maxLadder         = InpMaxLadder;
   c.riskPct           = InpRiskPct;
   c.lotDecay          = InpLotDecay;
   c.budgetPct         = InpBudgetPct;
   c.slMode            = InpSlMode;
   c.useSeasonFilter   = InpUseSeasonFilter;
   c.magic             = InpMagic;
   c.deviation         = InpDeviation;
   c.maxSpreadPoints   = InpMaxSpreadPoints;
   c.maxPending        = InpMaxPending;
   c.maxPos            = InpMaxPos;
   c.maxLotPerOrder    = InpMaxLotPerOrder;
   c.maxSlAtr          = InpMaxSlAtr;
   c.drawTemplate      = InpDrawTemplate;
   c.oneDirection      = InpOneDirection;
   c.lockTemplate      = InpLockTemplate;
   GppSetSeasonMonths(c, InpSeasonMonths);
   return (c.pivotBars >= 1 && c.lookback >= 30 && c.maxLadder >= 1
           && c.nearLevels >= 1 && c.riskPct > 0.0);
  }

bool GppNeedRebuild(void)
  {
   const datetime t = iTime(_Symbol, g_cfg.tf, 0);
   if(t == 0)
      return false;
   if(!g_tpl.valid)
      return true;
   if(g_cfg.lockTemplate && GppBookActive(_Symbol, g_cfg.magic))
      return false;
   if(t == g_lastD1)
      return false;
   return true;
  }

bool GppLoadSeries(double &high[], double &low[], datetime &time[], double &atrBuf[], int &rates)
  {
   const int need = MathMax(g_cfg.lookback, 40) + g_cfg.pivotBars + 5;
   rates = CopyHigh(_Symbol, g_cfg.tf, 0, need, high);
   if(rates < 30)
      return false;
   if(CopyLow(_Symbol, g_cfg.tf, 0, need, low) < 30)
      return false;
   if(CopyTime(_Symbol, g_cfg.tf, 0, need, time) < 30)
      return false;
   if(CopyBuffer(g_atrHandle, 0, 0, need, atrBuf) < 30)
      return false;
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(atrBuf, true);
   return true;
  }

bool GppRebuild(void)
  {
   double high[], low[], atrBuf[];
   datetime time[];
   int rates = 0;
   if(!GppLoadSeries(high, low, time, atrBuf, rates))
     {
      g_view.reason = "wait series";
      return false;
     }

   double atr = 0.0;
   for(int i = 1; i < MathMin(rates, 6); i++)
     {
      if(atrBuf[i] > 0.0)
        {
         atr = atrBuf[i];
         break;
        }
     }
   if(atr <= 0.0)
     {
      g_view.reason = "wait ATR";
      return false;
     }

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double spread = ask - bid;
   double refPrice = iClose(_Symbol, g_cfg.tf, 1);
   if(refPrice <= 0.0)
      refPrice = bid;
   if(!GppBuildTemplate(g_cfg, high, low, time, rates, atr, refPrice, spread, g_tpl))
     {
      g_plan.count = 0;
      g_view.reason = "no template";
      return false;
     }

   GppBuildPlan(g_cfg, g_tpl, refPrice, g_plan);
   int nBuy = 0, nSell = 0;
   for(int i = 0; i < g_plan.count; i++)
     {
      if(g_plan.slots[i].isBuy)
         nBuy++;
      else
         nSell++;
     }
   GppDrawTemplate(g_cfg, g_tpl);
   GppSyncPendings(g_cfg, g_plan);
   g_lastD1 = iTime(_Symbol, g_cfg.tf, 0);
   g_view.reason = (g_plan.count > 0 ? "armed" : "no slots");
   if(g_plan.count == 0)
      Print("GPP: template ok but no ladder slots. levels=", g_tpl.levelCount,
            " range=", DoubleToString(g_tpl.range.support, _Digits), "-",
            DoubleToString(g_tpl.range.resist, _Digits));
   else
      Print("GPP: plan slots buy=", nBuy, " sell=", nSell,
            " range=", DoubleToString(g_tpl.range.support, _Digits), "-",
            DoubleToString(g_tpl.range.resist, _Digits));
   return true;
  }

void GppRefreshView(void)
  {
   g_view.pending   = GppCountPendings(_Symbol, g_cfg.magic);
   g_view.positions = GppCountPositions(_Symbol, g_cfg.magic);
   g_view.balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_view.equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_view.seasonOn  = GppIsSeasonMonth(g_cfg, TimeCurrent());
  }

int OnInit()
  {
   if(!GppSymbolAllowed())
     {
      Print("GPP: symbol filter mismatch. Chart=", _Symbol, " filter=", InpSymbol);
      return INIT_FAILED;
     }
   if(!GppFillCfg(g_cfg))
      return INIT_PARAMETERS_INCORRECT;

   const int lvFail = GppLevelsSelfTest();
   const int plFail = GppPlanSelfTest();
   const int rkFail = GppRiskSelfTest();
   if(lvFail + plFail + rkFail > 0)
     {
      Print("GPP: self-test FAIL levels=", lvFail, " plan=", plFail, " risk=", rkFail);
      return INIT_FAILED;
     }
   Print("GPP: self-test PASS | SL=", GppSlModeName(g_cfg.slMode),
         " oneDir=", g_cfg.oneDirection,
         " lockTpl=", g_cfg.lockTemplate,
         " seasonFilter=", g_cfg.useSeasonFilter, " ladder=", g_cfg.maxLadder);

   GppOrdersInit(InpDeviation);
   g_atrHandle = iATR(_Symbol, g_cfg.tf, g_cfg.atrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("GPP: ATR init failed");
      return INIT_FAILED;
     }

   ZeroMemory(g_view);
   g_view.reason = "init";
   g_lastD1 = 0;
   EventSetTimer(1);
   GppRebuild();
   GppRefreshView();
   GppPanelUpdate(g_cfg, g_tpl, g_plan, g_view);
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   if(!g_tpl.valid)
      GppRebuild();
   else
      EventKillTimer();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   GppPanelRemove();
   GppDeleteChart("GPP_");
   if(g_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
     }
  }

void OnTick()
  {
   if(!GppSymbolAllowed())
      return;

   const int posN = PositionsTotal();
   const int ordN = OrdersTotal();
   const bool bookChanged = (posN != g_lastPosN || ordN != g_lastOrdN);
   g_lastPosN = posN;
   g_lastOrdN = ordN;

   const int gppPos  = GppCountPositions(_Symbol, g_cfg.magic);
   const int gppPend = GppCountPendings(_Symbol, g_cfg.magic);
   const datetime sec = TimeCurrent();

   bool rebuilt = false;
   if(GppNeedRebuild())
      rebuilt = GppRebuild();

   const bool wantRearm = (g_tpl.valid && g_plan.count > 0 && gppPos == 0 && gppPend == 0);
   const bool needSync = rebuilt || bookChanged
                         || (wantRearm && sec != g_lastArmSec);

   if(needSync)
     {
      if(wantRearm && !rebuilt && !bookChanged)
         g_lastArmSec = sec;
      GppEnforceOneDirection(g_cfg);
      if(g_tpl.valid && g_plan.count > 0)
         GppSyncPendings(g_cfg, g_plan);
     }
   else if(bookChanged)
      GppEnforceOneDirection(g_cfg);

   if(gppPos > 0)
      GppManageOpen(g_cfg, g_plan);

   if(sec != g_lastUiSec)
     {
      g_lastUiSec = sec;
      if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
        {
         GppRefreshView();
         GppPanelUpdate(g_cfg, g_tpl, g_plan, g_view);
        }
     }
  }
//+------------------------------------------------------------------+
