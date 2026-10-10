#property copyright "Ported from Pine Script 'VWAP Stdev Bands v2 Mod'"
#property strict
#property description "Anchored daily VWAP + volume-weighted stdev bands, dengan mode"
#property description "entry mean-reversion ATAU breakout (dipilih lewat input)."
#property description "PENTING: di MT4 'Volume' = tick volume, bukan volume transaksi"
#property description "asli (kecuali di beberapa simbol futures/crypto broker tertentu)."
#property description "Uji di Strategy Tester dulu sebelum dipakai live."

enum ENUM_STRATEGY_MODE
{
   MODE_MEAN_REVERSION = 0,   // Fade band luar, target balik ke VWAP / band dalam
   MODE_BREAKOUT       = 1    // Entry searah breakout band dgn filter displacement
};

enum ENUM_TP_TARGET
{
   TP_VWAP       = 0,   // Target = VWAP (mode mean-reversion)
   TP_INNER_BAND = 1    // Target = band tier 1 (mode mean-reversion)
};

//--- Multiplier band (default identik indikator Pine aslinya) ---
input double DevUp1 = 1.28;
input double DevDn1 = 1.28;
input double DevUp2 = 2.01;
input double DevDn2 = 2.01;
input double DevUp3 = 2.51;
input double DevDn3 = 2.51;
input double DevUp4 = 3.09;
input double DevDn4 = 3.09;
input double DevUp5 = 4.01;
input double DevDn5 = 4.01;

input bool ShowTier2OnChart = true;
input bool ShowTier3OnChart = true;
input bool ShowTier4OnChart = false;
input bool ShowTier5OnChart = false;
input bool DrawBandsOnChart = true;

//--- Anchor sesi harian VWAP ---
input int SessionAnchorShiftHours = 0;   // geser titik reset harian (jam) relatif waktu server

//--- Mode & pemicu entry ---
input ENUM_STRATEGY_MODE StrategyMode     = MODE_MEAN_REVERSION;
input int                EntryBandTier    = 2;      // 1-5, tier band pemicu mean-reversion
input int                BreakoutBandTier = 1;      // 1-5, tier band pemicu breakout
input ENUM_TP_TARGET     TPTarget         = TP_VWAP;
input double             DisplacementFactor = 0.25; // filter body candle breakout (x dev)
input double             SLBufferPoints   = 20;     // buffer SL tambahan (point)
input double             FixedRR          = 1.5;    // fallback RR kalau tidak ada tier berikutnya

//--- Manajemen risiko & order ---
input bool   UseRiskPercent    = true;
input double RiskPercent       = 1.0;
input double FixedLotSize      = 0.10;
input int    MaxOpenPositions  = 1;
input int    MagicNumber       = 990211;
input int    Slippage          = 5;
input double MaxSpreadPoints   = 30;

//--- Filter jam trading (jam server) ---
input bool UseTradingHoursFilter = false;
input int  TradingStartHour      = 0;
input int  TradingEndHour        = 23;

input bool CloseAllAtSessionEnd = false;

double   g_devUp[5];
double   g_devDn[5];
bool     g_showTier[5];
datetime g_lastBarTime    = 0;
datetime g_lastSessionKey = 0;
int      g_lineCounter    = 0;

double   g_prevVwap = 0;
double   g_prevUp[5];
double   g_prevDn[5];
bool     g_haveLastPoint = false;

int OnInit()
{
   g_devUp[0]=DevUp1; g_devUp[1]=DevUp2; g_devUp[2]=DevUp3; g_devUp[3]=DevUp4; g_devUp[4]=DevUp5;
   g_devDn[0]=DevDn1; g_devDn[1]=DevDn2; g_devDn[2]=DevDn3; g_devDn[3]=DevDn4; g_devDn[4]=DevDn5;
   g_showTier[0]=true; g_showTier[1]=ShowTier2OnChart; g_showTier[2]=ShowTier3OnChart;
   g_showTier[3]=ShowTier4OnChart; g_showTier[4]=ShowTier5OnChart;

   if(EntryBandTier<1 || EntryBandTier>5)
   {
      Print("EntryBandTier harus di rentang 1-5");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(BreakoutBandTier<1 || BreakoutBandTier>5)
   {
      Print("BreakoutBandTier harus di rentang 1-5");
      return(INIT_PARAMETERS_INCORRECT);
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "VWB_");
   Comment("");
}

datetime SessionKey(datetime t)
{
   datetime shifted = t - SessionAnchorShiftHours*3600;
   return shifted - (shifted % 86400);
}

int FindSessionStartBar()
{
   datetime key0   = SessionKey(Time[0]);
   int      idx    = 0;
   int      maxIdx = Bars-1;

   while(idx < maxIdx)
   {
      if(SessionKey(Time[idx+1]) != key0) break;
      idx++;
   }
   return idx;
}

void CalculateVWAP(double &vwapOut, double &devOut, double &upBands[], double &dnBands[])
{
   int startIdx = FindSessionStartBar();
   double vwapSum=0, volSum=0, v2Sum=0;

   for(int i=startIdx; i>=0; i--)
   {
      double hl2 = (High[i]+Low[i])/2.0;
      double vol = (double)Volume[i];
      vwapSum += hl2*vol;
      volSum  += vol;
      v2Sum   += vol*hl2*hl2;
   }

   if(volSum<=0)
   {
      vwapOut = Close[0];
      devOut  = 0;
   }
   else
   {
      vwapOut = vwapSum/volSum;
      double variance = v2Sum/volSum - vwapOut*vwapOut;
      if(variance<0) variance=0;
      devOut = MathSqrt(variance);
   }

   for(int t=0; t<5; t++)
   {
      upBands[t] = vwapOut + g_devUp[t]*devOut;
      dnBands[t] = vwapOut - g_devDn[t]*devOut;
   }
}

double LotStepAllowed() { return MarketInfo(Symbol(), MODE_LOTSTEP); }
double MinLotAllowed()  { return MarketInfo(Symbol(), MODE_MINLOT); }
double MaxLotAllowed()  { return MarketInfo(Symbol(), MODE_MAXLOT); }

double CalcLotSize(double slDistancePrice)
{
   if(!UseRiskPercent || slDistancePrice<=0) return FixedLotSize;

   double riskAmount = AccountBalance()*RiskPercent/100.0;
   double tickValue   = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize    = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize<=0) tickSize = Point;
   if(tickValue<=0) return FixedLotSize;

   double lossPerLot = (slDistancePrice/tickSize)*tickValue;
   if(lossPerLot<=0) return FixedLotSize;

   double lots = riskAmount/lossPerLot;
   double step = LotStepAllowed();
   if(step>0) lots = MathFloor(lots/step)*step;
   lots = MathMax(MinLotAllowed(), MathMin(MaxLotAllowed(), lots));
   return lots;
}

int CountOpenPositions()
{
   int count=0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber)
            count++;
   }
   return count;
}

bool HasOpenPositionType(int type)
{
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber && OrderType()==type)
            return true;
   }
   return false;
}

bool WithinTradingHours()
{
   if(!UseTradingHoursFilter) return true;
   int h = Hour();
   if(TradingStartHour<=TradingEndHour)
      return (h>=TradingStartHour && h<=TradingEndHour);
   return (h>=TradingStartHour || h<=TradingEndHour);
}

void OpenTrade(int cmd, double vwap, double &upBands[], double &dnBands[], int tier)
{
   if(CountOpenPositions()>=MaxOpenPositions) return;
   if(HasOpenPositionType(cmd)) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpreadPoints) return;
   if(!WithinTradingHours()) return;

   RefreshRates();
   double price = (cmd==OP_BUY) ? Ask : Bid;
   double sl=0, tp=0;

   if(StrategyMode==MODE_MEAN_REVERSION)
   {
      int slTier = MathMin(tier+1, 4);
      if(cmd==OP_SELL)
      {
         sl = upBands[slTier] + SLBufferPoints*Point;
         tp = (TPTarget==TP_VWAP) ? vwap : dnBands[0];
      }
      else
      {
         sl = dnBands[slTier] - SLBufferPoints*Point;
         tp = (TPTarget==TP_VWAP) ? vwap : upBands[0];
      }
   }
   else // MODE_BREAKOUT
   {
      if(cmd==OP_BUY)
      {
         sl = upBands[tier] - SLBufferPoints*Point;
         tp = (tier+1<5) ? upBands[tier+1] : price + (price-sl)*FixedRR;
      }
      else
      {
         sl = dnBands[tier] + SLBufferPoints*Point;
         tp = (tier+1<5) ? dnBands[tier+1] : price - (sl-price)*FixedRR;
      }
   }

   double lots = CalcLotSize(MathAbs(price-sl));
   if(lots<=0) return;

   color arrowColor = (cmd==OP_BUY) ? clrBlue : clrRed;
   int ticket = OrderSend(Symbol(), cmd, lots, price, Slippage,
                           NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                           "VWAPBands", MagicNumber, 0, arrowColor);
   if(ticket<0)
      Print("OrderSend gagal: ", GetLastError());
}

void CheckMeanReversion(double vwap, double &upBands[], double &dnBands[])
{
   int tier = EntryBandTier-1;
   double upperLevel = upBands[tier];
   double lowerLevel = dnBands[tier];

   if(High[1]>=upperLevel && Close[1]<upperLevel)
      OpenTrade(OP_SELL, vwap, upBands, dnBands, tier);

   if(Low[1]<=lowerLevel && Close[1]>lowerLevel)
      OpenTrade(OP_BUY, vwap, upBands, dnBands, tier);
}

void CheckBreakout(double vwap, double dev, double &upBands[], double &dnBands[])
{
   int tier = BreakoutBandTier-1;
   double upperLevel = upBands[tier];
   double lowerLevel = dnBands[tier];

   double body    = MathAbs(Close[1]-Open[1]);
   double minBody = DisplacementFactor*dev;

   if(Close[1]>upperLevel && body>=minBody)
      OpenTrade(OP_BUY, vwap, upBands, dnBands, tier);

   if(Close[1]<lowerLevel && body>=minBody)
      OpenTrade(OP_SELL, vwap, upBands, dnBands, tier);
}

void CloseAllManaged()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;

      RefreshRates();
      bool ok = false;
      if(OrderType()==OP_BUY)       ok = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage);
      else if(OrderType()==OP_SELL) ok = OrderClose(OrderTicket(), OrderLots(), Ask, Slippage);
      if(!ok) Print("OrderClose gagal: ", GetLastError());
   }
}

void DrawSegment(string namePrefix, datetime t1, double p1, datetime t2, double p2, color col)
{
   string name = namePrefix + "_" + IntegerToString(g_lineCounter++);
   if(ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void UpdateChartDrawing(double vwap, double &upBands[], double &dnBands[])
{
   if(!DrawBandsOnChart) return;

   if(g_haveLastPoint)
   {
      DrawSegment("VWB_V", Time[1], g_prevVwap, Time[0], vwap, clrYellow);
      for(int t=0; t<5; t++)
      {
         if(!g_showTier[t]) continue;
         DrawSegment("VWB_U"+IntegerToString(t), Time[1], g_prevUp[t], Time[0], upBands[t], clrTomato);
         DrawSegment("VWB_D"+IntegerToString(t), Time[1], g_prevDn[t], Time[0], dnBands[t], clrLimeGreen);
      }
   }

   g_prevVwap = vwap;
   for(int t=0; t<5; t++) { g_prevUp[t]=upBands[t]; g_prevDn[t]=dnBands[t]; }
   g_haveLastPoint = true;
}

void OnTick()
{
   if(Time[0]==g_lastBarTime) return;
   bool hasPriorBar = (g_lastBarTime!=0);
   g_lastBarTime = Time[0];

   datetime key = SessionKey(Time[0]);
   bool newSession = (g_lastSessionKey!=0 && key!=g_lastSessionKey);
   if(newSession)
   {
      g_haveLastPoint = false;
      if(CloseAllAtSessionEnd) CloseAllManaged();
   }
   g_lastSessionKey = key;

   double vwap, dev;
   double upBands[5], dnBands[5];
   CalculateVWAP(vwap, dev, upBands, dnBands);

   UpdateChartDrawing(vwap, upBands, dnBands);

   if(hasPriorBar)
   {
      if(StrategyMode==MODE_MEAN_REVERSION)
         CheckMeanReversion(vwap, upBands, dnBands);
      else
         CheckBreakout(vwap, dev, upBands, dnBands);
   }

   Comment("VWAP Stdev Bands EA\n",
           "Mode : ", (StrategyMode==MODE_MEAN_REVERSION ? "Mean-Reversion" : "Breakout"), "\n",
           "VWAP : ", DoubleToString(vwap, Digits), "\n",
           "Dev  : ", DoubleToString(dev, Digits));
}
