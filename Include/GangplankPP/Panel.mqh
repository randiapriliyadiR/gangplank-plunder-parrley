//+------------------------------------------------------------------+
//| GangplankPP/Panel.mqh — status overlay                           |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_PANEL_MQH
#define GANGPLANKPP_PANEL_MQH

#include "Types.mqh"
#include "Risk.mqh"

#define GPP_PNL_PREFIX   "GPP_PNL_"
#define GPP_PNL_X        14
#define GPP_PNL_Y        22
#define GPP_PNL_PAD_X    12
#define GPP_PNL_PAD_Y    10
#define GPP_PNL_ROW      17
#define GPP_PNL_TITLE_H  22
#define GPP_PNL_WIDTH    380
#define GPP_PNL_ROWS     11

#define GPP_PNL_BG       C'14,22,28'
#define GPP_PNL_BORDER   C'56,72,64'
#define GPP_PNL_ACCENT   C'212,168,75'
#define GPP_PNL_TITLE    C'245,245,242'
#define GPP_PNL_MUTED    C'168,174,186'
#define GPP_PNL_OK       C'86,214,130'

bool   g_gpp_pnl_built = false;
string g_gpp_pnl_fp    = "";

string GppPnlName(const string key)
  {
   return GPP_PNL_PREFIX + key;
  }

void GppPnlRect(const string key,
                const int x, const int y,
                const int w, const int h,
                const color bg, const color border,
                const int zorder)
  {
   const string n = GppPnlName(key);
   if(!g_gpp_pnl_built && ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, border);
   ObjectSetInteger(0, n, OBJPROP_ZORDER, zorder);
  }

void GppPnlLabel(const string key,
                 const int x, const int y,
                 const string text,
                 const color clr,
                 const int size,
                 const bool bold)
  {
   const string n = GppPnlName(key);
   if(!g_gpp_pnl_built && ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_FONT, bold ? "Arial Bold" : "Consolas");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_ZORDER, 20);
  }

void GppPanelRemove(void)
  {
   ObjectsDeleteAll(0, GPP_PNL_PREFIX);
   g_gpp_pnl_built = false;
   g_gpp_pnl_fp = "";
  }

void GppPanelUpdate(const SGppCfg &cfg,
                    const SGppTemplate &tpl,
                    const SGppPlan &plan,
                    const SGppView &view)
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;

   const string fp = StringFormat("%s|%.2f|%.2f|%.2f|%.2f|%d|%d|%d|%d|%s|%.0f|%.0f",
                                  GppSlModeName(cfg.slMode),
                                  tpl.range.support, tpl.range.resist, tpl.tpBuy, tpl.tpSell,
                                  tpl.levelCount, plan.count, view.pending, view.positions,
                                  view.reason, view.balance, view.equity);
   if(g_gpp_pnl_built && fp == g_gpp_pnl_fp)
      return;
   g_gpp_pnl_fp = fp;

   const int h = GPP_PNL_PAD_Y * 2 + GPP_PNL_TITLE_H + GPP_PNL_ROWS * GPP_PNL_ROW;
   GppPnlRect("bg", GPP_PNL_X, GPP_PNL_Y, GPP_PNL_WIDTH, h, GPP_PNL_BG, GPP_PNL_BORDER, 10);

   int y = GPP_PNL_Y + GPP_PNL_PAD_Y;
   const int x = GPP_PNL_X + GPP_PNL_PAD_X;
   GppPnlLabel("title", x, y, "GANGPLANK PLUNDER PARRRLEY", GPP_PNL_ACCENT, 11, true);
   y += GPP_PNL_TITLE_H;

   GppPnlLabel("r1", x, y, StringFormat("TF %s | SL %s | Season %s",
              EnumToString(cfg.tf), GppSlModeName(cfg.slMode),
              (view.seasonOn ? "ON/all" : "filtered-off")), GPP_PNL_TITLE, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r2", x, y, StringFormat("Range %.2f — %.2f | ATR %.2f buf %.2f",
              tpl.range.support, tpl.range.resist, tpl.atr, tpl.buffer), GPP_PNL_MUTED, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r3", x, y, StringFormat("TP buy %.2f | TP sell %.2f",
              tpl.tpBuy, tpl.tpSell), GPP_PNL_OK, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r4", x, y, StringFormat("Levels %d | Slots %d | Swings %d",
              tpl.levelCount, plan.count, tpl.swingCount), GPP_PNL_MUTED, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r5", x, y, StringFormat("Pending %d | Positions %d",
              view.pending, view.positions), GPP_PNL_TITLE, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r6", x, y, StringFormat("Bal %.2f | Eq %.2f",
              view.balance, view.equity), GPP_PNL_MUTED, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r7", x, y, view.propStatus, GPP_PNL_TITLE, 9, false);
   y += GPP_PNL_ROW;
   GppPnlLabel("r8", x, y, view.reason, GPP_PNL_ACCENT, 9, false);

   g_gpp_pnl_built = true;
  }

#endif
//+------------------------------------------------------------------+
