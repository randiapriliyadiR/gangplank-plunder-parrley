//+------------------------------------------------------------------+
//| GangplankPP/Types.mqh                                            |
//+------------------------------------------------------------------+
#ifndef GANGPLANKPP_TYPES_MQH
#define GANGPLANKPP_TYPES_MQH

#define GPP_MAX_SWINGS 256
#define GPP_MAX_LEVELS 64
#define GPP_MAX_SLOTS  24
#define GPP_MAX_MONTHS 12

enum ENUM_GPP_SL_MODE
  {
   GPP_SL_FIXED = 0,
   GPP_SL_BEP   = 1,
   GPP_SL_TRAIL = 2
  };

struct SGppCfg
  {
   string            symbol;
   ENUM_TIMEFRAMES   tf;
   int               pivotBars;
   int               lookback;
   int               atrPeriod;
   double            minReactionATR;
   double            clusterATR;
   double            minLevelSepATR;
   int               nearLevels;
   double            breakBufferATR;
   int               breakBufferPoints;
   int               maxLadder;
   double            riskPct;
   double            lotDecay;
   double            budgetPct;
   ENUM_GPP_SL_MODE  slMode;
   bool              useSeasonFilter;
   int               seasonMonths[GPP_MAX_MONTHS];
   int               seasonMonthCount;
   ulong             magic;
   ulong             deviation;
   int               maxSpreadPoints;
   int               maxPending;
   int               maxPos;
   double            maxLotPerOrder;
   double            maxSlAtr;         // Max SL distance from break (ATR)
   bool              drawTemplate;
   bool              oneDirection;   // no hedge: cancel/close opposite when one side fills
   bool              lockTemplate;   // keep S/R + plan until flat (no repaint)
   bool              propChallenge;
   bool              propHaltOnTarget; // false = log PASS then keep trading
   double            propDailyDdPct;
   double            propMaxDdPct;
   double            propTargetPct;
   double            propRiskAfterPass;   // risk % after +target (phase 2)
   double            propDailyBufferPct;  // pause new entries when daily room left < this
  };

// Implemented in PropFirm.mqh (same compilation unit).
double GppActiveRiskPct(const SGppCfg &cfg);
bool   GppPropAllowNewEntries(void);

struct SGppSwing
  {
   datetime time;
   double   price;
   bool     isHigh;
   double   reaction;
  };

struct SGppLevel
  {
   double   price;
   datetime anchorTime;
   double   anchorPrice;
   bool     isHigh;
   int      hits;
   double   reaction;
  };

struct SGppRange
  {
   bool   valid;
   double support;
   double resist;
   int    supIdx;
   int    resIdx;
  };

struct SGppTemplate
  {
   SGppSwing swings[GPP_MAX_SWINGS];
   int       swingCount;
   SGppLevel levels[GPP_MAX_LEVELS];
   int       levelCount;
   SGppRange range;
   double    atr;
   double    buffer;
   double    tpBuy;
   double    tpSell;
   datetime  lockBar;
   double    lockPrice;
   bool      valid;
  };

struct SGppSlot
  {
   bool     valid;
   bool     isBuy;
   int      ladder;
   double   entry;
   double   sl;
   double   tp;
   double   slSwing;
   datetime slSwingTime;
   double   breakPrice;
   datetime breakTime;
   double   lots;
   string   comment;
  };

struct SGppPlan
  {
   SGppSlot slots[GPP_MAX_SLOTS];
   int      count;
  };

struct SGppView
  {
   string reason;
   int    pending;
   int    positions;
   double balance;
   double equity;
   bool   seasonOn;
   string propStatus;
  };

void GppCfgInit(SGppCfg &c)
  {
   ZeroMemory(c);
   c.tf                = PERIOD_H4;
   c.pivotBars         = 3;
   c.lookback          = 240;
   c.atrPeriod         = 14;
   c.minReactionATR    = 0.8;
   c.clusterATR        = 0.80;
   c.minLevelSepATR    = 1.0;
   c.nearLevels        = 3;
   c.breakBufferATR    = 0.15;
   c.maxLadder         = 3;
   c.riskPct           = 1.0;
   c.lotDecay          = 0.85;
   c.budgetPct         = 15.0;
   c.slMode            = GPP_SL_FIXED;
   c.useSeasonFilter   = false;
   c.maxPending        = 24;
   c.maxPos            = 24;
   c.maxLotPerOrder    = 10.0;
   c.maxSlAtr          = 2.5;
   c.drawTemplate      = true;
   c.oneDirection      = true;
   c.lockTemplate      = true;
   c.propChallenge     = true;
   c.propHaltOnTarget  = false;
   c.propDailyDdPct    = 3.0;
   c.propMaxDdPct      = 10.0;
   c.propTargetPct     = 10.0;
   c.propRiskAfterPass = 0.35;
   c.propDailyBufferPct = 0.75;
  }

int GppParseMonths(const string src, int &months[])
  {
   ArrayResize(months, 0);
   string parts[];
   const int n = StringSplit(src, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      const int m = (int)StringToInteger(s);
      if(m < 1 || m > 12)
         continue;
      const int sz = ArraySize(months);
      ArrayResize(months, sz + 1);
      months[sz] = m;
     }
   return ArraySize(months);
  }

void GppSetSeasonMonths(SGppCfg &c, const string src)
  {
   int months[];
   GppParseMonths(src, months);
   c.seasonMonthCount = MathMin(ArraySize(months), GPP_MAX_MONTHS);
   for(int i = 0; i < c.seasonMonthCount; i++)
      c.seasonMonths[i] = months[i];
  }

bool GppIsSeasonMonth(const SGppCfg &c, const datetime t)
  {
   if(!c.useSeasonFilter)
      return true;
   if(c.seasonMonthCount <= 0)
      return false;
   MqlDateTime dt;
   TimeToStruct(t, dt);
   for(int i = 0; i < c.seasonMonthCount; i++)
     {
      if(dt.mon == c.seasonMonths[i])
         return true;
     }
   return false;
  }

string GppComment(const bool isBuy, const int ladder)
  {
   return StringFormat("GPP|%s%d", (isBuy ? "B" : "S"), ladder);
  }

string GppCommentLeg(const bool isBuy, const int ladder, const int leg)
  {
   if(leg <= 1)
      return GppComment(isBuy, ladder);
   return StringFormat("GPP|%s%dL%d", (isBuy ? "B" : "S"), ladder, leg);
  }

bool GppParseComment(const string comment, bool &isBuy, int &ladder)
  {
   isBuy  = true;
   ladder = 0;
   if(StringFind(comment, "GPP|") != 0)
      return false;
   const string rest = StringSubstr(comment, 4);
   if(StringLen(rest) < 2)
      return false;
   const ushort ch = StringGetCharacter(rest, 0);
   if(ch == 'B')
      isBuy = true;
   else if(ch == 'S')
      isBuy = false;
   else
      return false;
   string num = "";
   for(int i = 1; i < StringLen(rest); i++)
     {
      const ushort c = StringGetCharacter(rest, i);
      if(c < '0' || c > '9')
         break;
      num += ShortToString(c);
     }
   ladder = (int)StringToInteger(num);
   return (ladder >= 1);
  }

string GppSlModeName(const ENUM_GPP_SL_MODE m)
  {
   if(m == GPP_SL_BEP)
      return "BEP";
   if(m == GPP_SL_TRAIL)
      return "TrailLadder";
   return "Fixed";
  }

#endif
//+------------------------------------------------------------------+
