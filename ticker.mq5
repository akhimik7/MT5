//+------------------------------------------------------------------+
//|                                                      Ticker |
//|                                      Copyright 2012, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include <MQLMySQL.mqh>
#property strict

#define MAGICMA  11111111

input double Lots=0.1;
input double MaximumRisk        = 0.02;    // Максимальный риск в процентах
input double DecreaseFactor     = 3;       // Фактор уменьшения
input int MAHighTrendPeriod=144;
input int MALowTrendPeriod=89;
input bool StoplossOnOff=false;
input bool HighGlobalTrend=true;
input bool LowGlobalTrend=true;
input bool Martingeil=false;
input int MartingeilStep=2;
input int InpStopLoss=20;  // First StopLoss Level (in pips)
input int InpTrailingStop=20;  // Trailing Stop Level (in pips)
double lot=0.01;

                               //первый коэффициент чувстивительности - ручной подстройки, учавствует в расчете inaquality бара 
input int k1=5;

//переменные для подключения к БД MySQL
string Host,User,Password,Database,Socket; // database credentials
int Port,ClientFlag;
int DB; // database identifier
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//_____________переменные для индикаторных вычислений________________
//объявление данных перечислимого типа

int ticksInCandle[];
int ticks=0;
//разница по модулю между скользящими средними
double MaInaquality[];
int MaInaqualityNumber=0;
double MA1,MA2;
double HLBuffer[];
double OCBuffer[];
//Параметр обозначающий разницу между максимумом и минимумом текущей свечи.
//Если разница между максимумом и минимумом больше или равно inaquality, значение текущего тика присваивается
//цене закрытия текущей свечи.
double inaquality;
double Currentinaquality;
//спред
int spread=0;
//--- Параметры первой скользящей средней
input int            InpMAPeriod1=4;         // Period, обязательно должен быть меньше чем у второй скользящей средней
input int            InpMAShift1=0;           // Shift
input ENUM_MA_METHOD InpMAMethod1=MODE_LWMA;  // Method
//--- indicator buffers
double               MALineBuffer1[];

//--- Параметры второй сколльзящей средней
input int            InpMAPeriod2=8;         // Period, обязательно должен быть больше чем у первой скользящей средней
input int            InpMAShift2=0;           // Shift
input ENUM_MA_METHOD InpMAMethod2=MODE_LWMA;  // Method



//--- indicator buffers
double               MALineBuffer2[];

//переменная служащая для перебора всех значений элементов массива TicksBuffer[]
int i=0;
int i1=0;
int i2=0;

//массивы OpenBuffer[], HighBuffer[], LowBuffer[] и CloseBuffer[]
//используются для хранения цен OHLC отображаемых свечей, массив
double CurrentTick,OpenBuffer[],HighBuffer[],LowBuffer[],CloseBuffer[],ColorIndexBuffer[],TicksBuffer[],ComputeInaquality;
//переменная firstStart позволяет определить первый раз прилетает новый тик или нет, 
//если переменная равна 0 - значит первый, если 1 - значит второй или более
uchar firstStart=0;
//Хранит номер текущей свечи
int CandleNumber=0;
//Номера рассчитанных точек для скользящей средней
int MA1Number = 0;
int MA2Number = 0;

bool firstMA1Number=false;
bool firstMA2Number=false;


double ProfitMin=0;
double ProfitMax=0;
double CurrentTrailingStop=0;
double CurrentStopLoss=0;
double TrailingStop;
double CurrentStopLossBuy;
double CurrentStopLossSell;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string QueryMA1;
string QueryMA2;
//--- calculation
void CalculateSMA1()
  {
//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==InpMAPeriod1) && (firstMA1Number==false))
     {
      double firstValue1=0;
      for(i=0;i<InpMAPeriod1;i++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue1=NormalizeDouble(firstValue1/InpMAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;
      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
/*  {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;
     }
   if((CandleNumber-1)>InpMAPeriod1)
     {
      //тест_стандартная формула расчета МА
      double firstValue1=0;
      for(i1=(CandleNumber-InpMAPeriod1);i1<CandleNumber;i1++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i1],_Digits);
        }
      firstValue1=NormalizeDouble(firstValue1/InpMAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA1))
/*  {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateSMA2()
  {
//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА2 и ранее первое значение  МА2 не вычислялось
   if(((CandleNumber-1)==InpMAPeriod2) && (firstMA2Number==false))// first calculation
     {
      double firstValue2=0;
      for(i=0;i<InpMAPeriod2;i++)
        {
         firstValue2+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/InpMAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
/*  {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      MA2Number++;
      firstMA2Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod2)
     {
      //тест_стандартная формула расчета МА
      double firstValue2=0;
      for(i2=(CandleNumber-InpMAPeriod2);i2<CandleNumber;i2++)

        {
         firstValue2+=NormalizeDouble(CloseBuffer[i2],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/InpMAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
/*  {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      MA2Number++;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateLWMA1()
  {

//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==InpMAPeriod1) && (firstMA1Number==false))
     {
      int  weightsum=0;
      double firstValue1=0;
      for(i=0;i<InpMAPeriod1;i++)
        {
         //весовой коэффициент равный номеру текущему значению Candlenumber
         int k=InpMAPeriod1-i;
         firstValue1+=CloseBuffer[i]*k;
         weightsum+=k;
        }

      firstValue1=NormalizeDouble(firstValue1/(double)weightsum,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
/*  {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod1)
     {
      //тест_стандартная формула расчета МА
      int MAincr=1;
      int  weightsum=0;
      double firstValue1=0;
      for(i1=(CandleNumber-InpMAPeriod1);i1<CandleNumber;i1++)
        {
         int k=MAincr;
         firstValue1+=CloseBuffer[i1]*k;
         weightsum+=MAincr;
         MAincr++;
        }

      firstValue1=NormalizeDouble(firstValue1/(double)weightsum,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;
      MA1=MALineBuffer1[MA1Number];
      // Print("MA1: ",MA1);
      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      MA1Number++;
      if(MySqlExecute(DB,QueryMA1))
        {}
/*   {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/

     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateLWMA2()
  {

//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==InpMAPeriod2) && (firstMA2Number==false))
     {
      int  weightsum=0;
      double firstValue2=0;
      for(i=0;i<InpMAPeriod2;i++)
        {
         //весовой коэффициент равный номеру текущему значению Candlenumber
         int k=InpMAPeriod2-i;
         // firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
         firstValue2+=NormalizeDouble(CloseBuffer[i]*k,_Digits);
         weightsum+=k;
        }

      firstValue2=NormalizeDouble(firstValue2/weightsum,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
/*    {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      //    Print("MA2: ",MA2);
      MA2Number++;
      firstMA2Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod2)
     {
      //тест_стандартная формула расчета МА
      int MAincr=1;
      int  weightsum=0;
      double firstValue2=0;
      for(i2=(CandleNumber-InpMAPeriod2);i2<CandleNumber;i2++)
        {
         int k=MAincr;
         firstValue2+=CloseBuffer[i2]*k;
         weightsum+=MAincr;
         MAincr++;
        }

      firstValue2=NormalizeDouble(firstValue2/weightsum,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
/*   {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      // Print("MA2: ",MA2);
      MA2Number++;
     }

//RSI

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateEMA1()
  {

   if(((CandleNumber-1)==InpMAPeriod1) && (firstMA1Number==false))
     {
      double SmoothFactor=2.0/(1.0+InpMAPeriod1);
      double firstValue1=0;

      for(i=0;i<InpMAPeriod1;i++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue1=NormalizeDouble(firstValue1/InpMAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
/*  {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod1)
     {
      double SmoothFactor=2.0/(1.0+InpMAPeriod1);

      //тест_стандартная формула расчета МА
      MALineBuffer1[MA1Number]=(CloseBuffer[CandleNumber]*SmoothFactor)+((MALineBuffer1[MA1Number-1])*(1-SmoothFactor));

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA1))
/*     {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateEMA2()
  {

   if(((CandleNumber-1)==InpMAPeriod2) && (firstMA2Number==false))
     {
      double SmoothFactor=2.0/(1.0+InpMAPeriod2);
      double firstValue2=0;

      for(i=0;i<InpMAPeriod2;i++)
        {
         firstValue2+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/InpMAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
/*   {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      MA2Number++;
      firstMA2Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod2)
     {

      double SmoothFactor=2.0/(1.0+InpMAPeriod2);
/*   Print("CloseBuffer[CandleNumber]: ",CloseBuffer[CandleNumber]);
      Print("MALineBuffer2[MA2Number-1]: ",MALineBuffer2[MA2Number-1]);
      Print("1-SmoothFactor: ",1-SmoothFactor);
      Print("((MALineBuffer2[MA2Number-1])*(1-SmoothFactor): ",((MALineBuffer2[MA2Number-1])*(1-SmoothFactor)));
*/
      MALineBuffer2[MA2Number]=(CloseBuffer[CandleNumber]*SmoothFactor)+((MALineBuffer2[MA2Number-1])*(1-SmoothFactor));
      //   Print("MALineBuffer2[MA2Number]: ",MALineBuffer2[MA2Number]);

      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
/*    {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      MA2Number++;
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateSmMA1()
  {

//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==InpMAPeriod1) && (firstMA1Number==false))
     {

      double firstValue1=0;
      for(i=0;i<InpMAPeriod1;i++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue1=NormalizeDouble(firstValue1/InpMAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
/*    {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod1)
     {

      //тест_стандартная формула расчета МА
      MALineBuffer1[MA1Number]=((MALineBuffer1[MA1Number-1]*(InpMAPeriod1-1))+CloseBuffer[CandleNumber])/InpMAPeriod1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
/*   {
         Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }*/
         MA1=MALineBuffer1[MA1Number];
      MA1Number++;
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateSmMA2()
  {

//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==InpMAPeriod2) && (firstMA2Number==false))
     {
      double firstValue2=0;
      for(i=0;i<InpMAPeriod2;i++)
        {
         firstValue2+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/InpMAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
/*  {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      MA2Number++;
      firstMA2Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod2)
     {
      //тест_стандартная формула расчета МА
      MALineBuffer2[MA2Number]=(MALineBuffer2[MA2Number-1]*(InpMAPeriod2-1)+CloseBuffer[CandleNumber])/InpMAPeriod2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
/*   {
         Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }*/
         MA2=MALineBuffer2[MA2Number];
      MA2Number++;
     }

  }
//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double LotsOptimized()
  {
         
  
  /*  int    orders=HistoryTotal();     // history orders total

   int    losses=0;                  // number of losses orders without a break
//--- select lot size
   lot=NormalizeDouble(AccountFreeMargin()*MaximumRisk/1000.0,1);
//--- calcuulate number of losses orders without a break
   if(DecreaseFactor>0)
     {
      for(int j=orders-1;j>=0;j--)
        {
         if(OrderSelect(j,SELECT_BY_POS,MODE_HISTORY)==false)
           {
            Print("Error in history!");
            break;
           }
         if(OrderSymbol()!=Symbol() || OrderType()>OP_SELL)
            continue;
         //---
         if(OrderProfit()>0) break;
         if(OrderProfit()<0) losses++;
        }
      if(losses>1)
         lot=NormalizeDouble(lot-lot*losses/DecreaseFactor,1);
     }
//--- return lot size
   if(lot<0.1) lot=0.1;
//return(lot);
lot=0.01;
*/
if (Martingeil==true)
{
if(OrderSelect(HistoryTotal()-1,SELECT_BY_POS,MODE_HISTORY)==false);
if(OrderProfit()>=0) lot=0.01;
if(OrderProfit()<0)  lot=lot*MartingeilStep;
}
   return(lot);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckForClose(void)
  {
   for(int m=0;m<OrdersTotal();m++)
     {
      if(OrderSelect(m,SELECT_BY_POS,MODE_TRADES)==false) break;
      if(OrderMagicNumber()!=MAGICMA || OrderSymbol()!=Symbol()) continue;
      //--- check order type 
      if(OrderType()==OP_BUY)
        {
         //проверка условий на закрытие позиции
         if(((MaInaquality[MaInaqualityNumber]>0) && (MaInaquality[MaInaqualityNumber-1]<0)) || ((MaInaquality[MaInaqualityNumber]<0) && (MaInaquality[MaInaqualityNumber-1]>0)))

           {
            Print("Мы в функции закрытия позиции");
            if(!OrderClose(OrderTicket(),OrderLots(),Bid,20,White)) ///ЕСЛИ BUY
              {
               Print("OrderModify error ",GetLastError());
              }
           }
         break;
        }
      if(OrderType()==OP_SELL)
        {
         //проверка условий на закрытие позиции
         if(((MaInaquality[MaInaqualityNumber]<0) && (MaInaquality[MaInaqualityNumber-1]>0)) || ((MaInaquality[MaInaqualityNumber]>0) && (MaInaquality[MaInaqualityNumber-1]<0)))

           {
            Print("Мы в функции закрытия позиции");
            if(!OrderClose(OrderTicket(),OrderLots(),Ask,20,White)) ///ЕСЛИ SELL
              {
               Print("OrderModify error ",GetLastError());
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Check for open position conditions                               |
//+------------------------------------------------------------------+
void CheckForOpen(void)
  {
//Проверка на наличие данных для торговых расчетов
//Проверяем есть ли данные второй скользящей средней   
// Print("CheckForOpen:PRE:InpMAPeriod2=",InpMAPeriod2);
//Print("CheckForOpen:PRE:MaInaqualityNumber=",MaInaqualityNumber);

   double MaHighCurrent,MaHighPrevious,MaLowCurrent,MaLowPrevious;

   if(MaInaqualityNumber<=0)
     {
      //   Print("Вторая скользящая средняя еще не рассчитывалась");
      return;
     }
   long Positiontype=OrderType();

//--- check signals
// Print("Мы в CheckForOpen");
   ENUM_ORDER_TYPE signal=WRONG_VALUE;

   MaHighCurrent=iMA(NULL,0,MAHighTrendPeriod,0,MODE_LWMA,PRICE_CLOSE,0);
   MaHighPrevious=iMA(NULL,0,MAHighTrendPeriod,0,MODE_LWMA,PRICE_CLOSE,1);

   MaLowCurrent=iMA(NULL,0,MALowTrendPeriod,0,MODE_LWMA,PRICE_CLOSE,0);
   MaLowPrevious=iMA(NULL,0,MALowTrendPeriod,0,MODE_LWMA,PRICE_CLOSE,1);

//Анализ открытия без учета обоих высших трендов
///позиция на SELL
   if(HighGlobalTrend==false && LowGlobalTrend==false)
     {
      if(MaInaquality[MaInaqualityNumber]>0 && MaInaquality[MaInaqualityNumber-1]<0)
        {
         //Print("Мы в CheckForOpen:ORDER_TYPE_SELL");
         signal=OP_SELL;
         // Print("В открытии на SELL:signal:",signal); // sell conditions
        }

      ///позиция на BUY
      if(MaInaquality[MaInaqualityNumber]<0 && MaInaquality[MaInaqualityNumber-1]>0)
        {
         // Print("Мы в CheckForOpen:ORDER_TYPE_BUY");
         signal=OP_BUY;  // buy conditions
                         // Print("В открытии на BUY:signal:",signal); // sell conditions
        }
     }

//Анализ открытия c учетом только тренда низшего порядка
///позиция на SELL
   if(HighGlobalTrend==false && LowGlobalTrend==true)
     {
      if(MaInaquality[MaInaqualityNumber]>0 && MaInaquality[MaInaqualityNumber-1]<0 && MaLowCurrent<MaLowPrevious)
        {
         //Print("Мы в CheckForOpen:ORDER_TYPE_SELL");
         signal=OP_SELL;
         // Print("В открытии на SELL:signal:",signal); // sell conditions
        }

      ///позиция на BUY
      if(MaInaquality[MaInaqualityNumber]<0 && MaInaquality[MaInaqualityNumber-1]>0 && MaLowCurrent>MaLowPrevious)
        {
         // Print("Мы в CheckForOpen:ORDER_TYPE_BUY");
         signal=OP_BUY;  // buy conditions
                         // Print("В открытии на BUY:signal:",signal); // sell conditions
        }
     }

//Анализ открытия c учетом только тренда вызшего порядка
///позиция на SELL
   if(HighGlobalTrend==true && LowGlobalTrend==false)
     {
      if(MaInaquality[MaInaqualityNumber]>0 && MaInaquality[MaInaqualityNumber-1]<0 && MaHighCurrent<MaHighPrevious)
        {
         //Print("Мы в CheckForOpen:ORDER_TYPE_SELL");
         signal=OP_SELL;
         // Print("В открытии на SELL:signal:",signal); // sell conditions
        }

      ///позиция на BUY
      if(MaInaquality[MaInaqualityNumber]<0 && MaInaquality[MaInaqualityNumber-1]>0 && MaHighCurrent>MaHighPrevious)
        {
         // Print("Мы в CheckForOpen:ORDER_TYPE_BUY");
         signal=OP_BUY;  // buy conditions
                         // Print("В открытии на BUY:signal:",signal); // sell conditions
        }
     }

//Анализ открытия c учетом трендов высшего и низшего порядков
///позиция на SELL
   if(MaInaquality[MaInaqualityNumber]>0 && MaInaquality[MaInaqualityNumber-1]<0 && MaHighCurrent<MaHighPrevious && MaLowCurrent<MaLowPrevious)
   {
      //Print("Мы в CheckForOpen:ORDER_TYPE_SELL");
      signal=OP_SELL;
      // Print("В открытии на SELL:signal:",signal); // sell conditions
     }

///позиция на BUY
   if(MaInaquality[MaInaqualityNumber]<0 && MaInaquality[MaInaqualityNumber-1]>0 && MaHighCurrent>MaHighPrevious && MaLowCurrent>MaLowPrevious)
     {
      // Print("Мы в CheckForOpen:ORDER_TYPE_BUY");
      signal=OP_BUY;  // buy conditions
                      // Print("В открытии на BUY:signal:",signal); // sell conditions
     }

//Print("Precheck:(Перед открытием)Positiontype:",Positiontype);
//--- additional checking
   if(signal!=WRONG_VALUE)
      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {

         // Print("В основной функции на открытие позиции:signal:",signal); // sell conditions

         if(!OrderSend(Symbol(),signal,LotsOptimized(),SymbolInfoDouble(_Symbol,signal==ORDER_TYPE_SELL ? SYMBOL_BID:SYMBOL_ASK),20,0,0,"",MAGICMA,0,signal==OP_SELL ? Red : Green))
           {
            Print("OrderModify error ",GetLastError());
           }

        }

  }
//+------------------------------------------------------------------+
//| Calculate open positions                                         |
//+------------------------------------------------------------------+
int CalculateCurrentOrders(string symbol)
  {
   int buys=0,sells=0;
//---
   for(int n=0;n<OrdersTotal();n++)
     {
      if(OrderSelect(n,SELECT_BY_POS,MODE_TRADES)==false) break;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGICMA)
        {
         if(OrderType()==OP_BUY)  buys++;
         if(OrderType()==OP_SELL) sells++;
        }
     }
//--- return orders volume
   if(buys>0) return(buys);
   else       return(-sells);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit()
  {

//  Print(MySqlVersion());

//string INI=TerminalInfoString(TERMINAL_PATH)+"\\MQL5\\Scripts\\MyConnection.ini";

// reading database credentials from INI file
   Host = "127.0.0.1";
   User = "root";
   Password = "Qw123456";
   Database = "ticks";
   Port     = 3306;
   Socket="0";
   ClientFlag=0; //(int)StringToInteger(ReadIni(INI, "MYSQL", "ClientFlag"));  

                 // Print("Host: ",Host,", User: ",User,", Database: ",Database);

// open database connection
// Print("Connecting...");

   DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);

   if(DB==-1) { Print("Connection failed! Error: "+MySqlErrorDescription); } else { Print("Connected! DBID#",DB);}

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   Print("OrdersTotal()%2!=0: ",OrdersTotal()%2!=0);
   Print("OrdersTotal()= ",OrdersTotal());
   Print("OrdersTotal()%2= ",OrdersTotal()%2);
//Проверяем соединение к MySQL, если соединение отсутствует пытаемся подключиться
   if(DB==-1)
     {
      //  Print("Connection failed! Error: "+MySqlErrorDescription);
      while(DB==-1)
        {
         //     Print("Connecting...");
         DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
        }

     }
/*  else
     {
      Print("Already Connected. DBID#",DB);

     }*/
   ticks++;

   string text=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   StringReplace(text,".","-");

   string QueryTicks;

//Пишем в MySQL данные прилетевшего тика
   QueryTicks="INSERT INTO `eurusd` (DATETIME, BID, ASK, LAST, SPREAD, CANDLENUMBER) VALUES (\""+text+"\", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_BID)+", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_ASK)+", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_LAST)+", "+(string)spread+", "+(string)CandleNumber+")";

   if(MySqlExecute(DB,QueryTicks))

      //переменная last_price_bid - последняя поступившая котировка Bid
      CurrentTick=SymbolInfoDouble(Symbol(),SYMBOL_BID);
   CurrentTick=NormalizeDouble(CurrentTick,_Digits);

   spread=(int)SymbolInfoInteger(Symbol(),SYMBOL_SPREAD);
   inaquality=NormalizeDouble((_Point*k1),_Digits);

//CurrentTrailingStop
//+------------------------------------------------------------------+  
   if(StoplossOnOff==true)
     {
      for(int l=0; l<OrdersTotal(); l++)
        {
         if(OrderSelect(l,SELECT_BY_POS,MODE_TRADES))
            if(OrderSymbol()==Symbol() || OrderMagicNumber()==MAGICMA)
               if(InpTrailingStop<=SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL))
                 {
                  CurrentTrailingStop=SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL)*Point();
                 }
         else
           {
            CurrentTrailingStop=InpTrailingStop*Point();
           }

         if(InpTrailingStop>0)
           {

            if(OrderType()==OP_SELL)
              {

               if(OrderStopLoss()==0)
                 {
                  if(!OrderModify(OrderTicket(),OrderOpenPrice(),SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop,0,0,Red))
                    {
                     Print("OrderModify error ",GetLastError());
                    }
                 }

               if(NormalizeDouble(OrderOpenPrice()-SymbolInfoDouble(Symbol(),SYMBOL_ASK),_Digits)>CurrentTrailingStop)
                 {
                  if(OrderStopLoss()>SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop)
                    {
                     if(!OrderModify(OrderTicket(),OrderOpenPrice(),SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop,0,0))
                       {
                        Print("OrderModify error ",GetLastError());
                       }
                    }
                 }
              }

            if(OrderType()==OP_BUY)
              {

               if(OrderStopLoss()==0)
                 {
                  if(!OrderModify(OrderTicket(),OrderOpenPrice(),SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop,OrderTakeProfit(),0,Green))
                    {
                     Print("OrderModify error ",GetLastError());
                    }

                 }

               if(NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_BID)-OrderOpenPrice(),_Digits)>CurrentTrailingStop)
                 {
                  if(OrderStopLoss()<SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop || OrderStopLoss()==0)
                    {

                     if(!OrderModify(OrderTicket(),OrderOpenPrice(),SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop,0,0))
                       {
                        Print("OrderModify error ",GetLastError());
                       }

                    }
                 }
              }
           }
        }
     }
//+------------------------------------------------------------------+

   if(firstStart==0)
     {

      string QueryClean;
      //удаляем все значения из таблицы eurusd
      QueryClean="TRUNCATE TABLE `eurusd`";

      if(MySqlExecute(DB,QueryClean))
        {
         Print("Succeeded: ",QueryClean);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryClean);
        }
      //удаляем все значения из таблицы ma1_data
      QueryClean="TRUNCATE TABLE `ma1_data`";

      if(MySqlExecute(DB,QueryClean))
        {
         Print("Succeeded: ",QueryClean);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryClean);
        }
      //удаляем все значения из таблицы ma2_data
      QueryClean="TRUNCATE TABLE `ma2_data`";

      if(MySqlExecute(DB,QueryClean))
        {
         Print("Succeeded: ",QueryClean);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryClean);
        }
      //удаляем все значения из таблицы ma1_data
      QueryClean="TRUNCATE TABLE `ohlc`";

      if(MySqlExecute(DB,QueryClean))
        {
         Print("Succeeded: ",QueryClean);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryClean);
        }

      ArrayInitialize(OpenBuffer,0);
      ArrayInitialize(HighBuffer,0);
      ArrayInitialize(LowBuffer,0);
      ArrayInitialize(CloseBuffer,0);
      ArrayInitialize(TicksBuffer,0);
      ArrayInitialize(ColorIndexBuffer,0);

      ArrayResize(OpenBuffer,5000000);
      ArrayResize(HighBuffer,5000000);
      ArrayResize(LowBuffer,5000000);
      ArrayResize(CloseBuffer,5000000);

      ArrayResize(MALineBuffer1,5000000);
      ArrayResize(MALineBuffer2,5000000);
      ArrayResize(MaInaquality,5000000);
      ArrayResize(HLBuffer,5000000);
      ArrayResize(OCBuffer,5000000);
      ArrayResize(ticksInCandle,5000000);

      MaInaquality[0]=0;
      MaInaqualityNumber=1;

      // текущая котировка будет являться ценой открытия свечи
      OpenBuffer[CandleNumber]=CurrentTick;
      // текущая котировка будет являться максимальной ценой свечи
      HighBuffer[CandleNumber]=CurrentTick;
      // текущая котировка будет являться минимальной ценой свечи
      LowBuffer[CandleNumber]=CurrentTick;
      // текущая котировка пока является ценой закрытия текущей свечи
      CloseBuffer[CandleNumber]=CurrentTick;

      firstStart++;
      Currentinaquality=(HighBuffer[CandleNumber]-LowBuffer[CandleNumber]);
      Comment(StringFormat("firstStart=%G\nCurrentTick=%G\nCandleNumber=%G,\nOpenBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\ninaquality=%G\nCurrentinaquality=%G",firstStart,CurrentTick,CandleNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],inaquality,Currentinaquality));

     }
   else
     {

      if((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])<inaquality)
        {
         // текущая котировка пока является ценой закрытия текущей свечи
         CloseBuffer[CandleNumber]=CurrentTick;
         // если текущая котировка больше максимальной цены текущей свечи, то это будет новое значение максимальной цены свечи
         if(CurrentTick>HighBuffer[CandleNumber]) HighBuffer[CandleNumber]=CurrentTick;
         // если текущая котировка меньше минимальной цены текущей свечи, то это будет новое значение минимальной цены свечи
         if(CurrentTick<LowBuffer[CandleNumber]) LowBuffer[CandleNumber]=CurrentTick;
         Currentinaquality=(HighBuffer[CandleNumber]-LowBuffer[CandleNumber]);
         Comment(StringFormat("firstStart=%G\nCurrentTick=%G\nCandleNumber=%G,\nOpenBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\ninaquality=%G\nCurrentinaquality=%G",firstStart,CurrentTick,CandleNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],inaquality,Currentinaquality));

        }

      if((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=inaquality)
        {
         Currentinaquality=(HighBuffer[CandleNumber]-LowBuffer[CandleNumber]);

         CloseBuffer[CandleNumber]=CurrentTick;

         Comment(StringFormat("firstStart=%G\nCurrentTick=%G\nCandleNumber=%G,\nOpenBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\ninaquality=%G\nCurrentinaquality=%G",firstStart,CurrentTick,CandleNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],inaquality,Currentinaquality));

         //Проверяем соединение к MySQL, если соединение отсутствует пытаемся подключиться
         if(DB==-1)
           {
            //    Print("Connection failed! Error: "+MySqlErrorDescription);
            while(DB==-1)
              {
               //       Print("Connecting...");
               DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
              }

           }
/*  else
           {
            Print("Already Connected. DBID#",DB);
           }*/

         //--- calculation
         switch(InpMAMethod1)
           {
            case MODE_SMA:  CalculateSMA1();  break;
            case MODE_LWMA: CalculateLWMA1(); break;
            case MODE_EMA:  CalculateEMA1();  break;
            case MODE_SMMA: CalculateSmMA1(); break;
           }

         switch(InpMAMethod2)
           {
            case MODE_SMA:  CalculateSMA2();  break;
            case MODE_LWMA: CalculateLWMA2(); break;
            case MODE_EMA:  CalculateEMA2();  break;
            case MODE_SMMA: CalculateSmMA2(); break;
           }
         //  Print("1:MA1 = ",MA1);
         //  Print("1:MA2 = ",MA2);

         if((CandleNumber)>InpMAPeriod2)
           {
/*
            Print("MA1 = ",MA1);
            Print("MA2 = ",MA2);
            Print("MA2-MA1 = ",MA2-MA1);
            Print("(NormalizeDouble(MA2-MA1),_Digits) = ",(NormalizeDouble((MA2-MA1),_Digits)));
*/
            MaInaquality[MaInaqualityNumber]=NormalizeDouble((MA2-MA1),_Digits);
            if(MaInaquality[MaInaqualityNumber]==0)
              {
/*       Print("MaInaqualityNumber = ",MaInaqualityNumber);
               Print("MaInaquality[MaInaqualityNumber] = ",MaInaquality[MaInaqualityNumber]);
               Print("MaInaquality[MaInaqualityNumber-1] = ",MaInaquality[MaInaqualityNumber-1]);
         */      if(MaInaquality[MaInaqualityNumber-1]>0)
                 {
                  MaInaquality[MaInaqualityNumber]=1;
                 }
               else if(MaInaquality[MaInaqualityNumber-1]<0)
                 {
                  MaInaquality[MaInaqualityNumber]=-1;
                 }
              }

            if(OpenBuffer[CandleNumber]>CloseBuffer[CandleNumber])
              {
               OCBuffer[CandleNumber]=NormalizeDouble((OpenBuffer[CandleNumber]-CloseBuffer[CandleNumber])*100000,_Digits);
              }

            else if(CloseBuffer[CandleNumber]>OpenBuffer[CandleNumber])
              {
               OCBuffer[CandleNumber]=NormalizeDouble((CloseBuffer[CandleNumber]-OpenBuffer[CandleNumber])*100000,_Digits);
              }

            else if(OpenBuffer[CandleNumber]==CloseBuffer[CandleNumber])
              {
               OCBuffer[CandleNumber]=NormalizeDouble((OpenBuffer[CandleNumber]-CloseBuffer[CandleNumber])*100000,_Digits);
              }

            HLBuffer[CandleNumber]=NormalizeDouble((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])*100000,_Digits);

            string QueryOHCL;
            //Пишем в MySQL данные прилетевшего тика
            QueryOHCL="INSERT INTO `ohlc` (O, H, L, C, CandleNumber, MAINAQUALITY, SPREAD, HL, OC, TICKSINCANDLE) VALUES ("+(string)OpenBuffer[CandleNumber]+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber]+", "+(string)spread+", "+(string)HLBuffer[CandleNumber]+", "+(string)OCBuffer[CandleNumber]+", "+(string)ticks+")";

            if(MySqlExecute(DB,QueryOHCL))
/*   {
               Print("Succeeded: ",QueryOHCL);
              }
            else
              {
               Print("Error: ",MySqlErrorDescription);
               Print("Query: ",QueryOHCL);
              }*/

               //--- calculate open orders by current symbol
               if(CalculateCurrentOrders(Symbol())==0) CheckForOpen();
            else                                    CheckForClose();

            MaInaqualityNumber++;
           }
         else
           {

            HLBuffer[CandleNumber]=NormalizeDouble((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])*100000,_Digits);

            if(OpenBuffer[CandleNumber]>CloseBuffer[CandleNumber])
              {
               OCBuffer[CandleNumber]=NormalizeDouble((OpenBuffer[CandleNumber]-CloseBuffer[CandleNumber])*100000,_Digits);
              }

            else if(CloseBuffer[CandleNumber]>OpenBuffer[CandleNumber])
              {
               OCBuffer[CandleNumber]=NormalizeDouble((CloseBuffer[CandleNumber]-OpenBuffer[CandleNumber])*100000,_Digits);
              }

            else if(OpenBuffer[CandleNumber]==CloseBuffer[CandleNumber])
              {
               OCBuffer[CandleNumber]=NormalizeDouble((OpenBuffer[CandleNumber]-CloseBuffer[CandleNumber])*100000,_Digits);
              }

            string QueryOHCL;
            //Пишем в MySQL данные прилетевшего тика
            QueryOHCL="INSERT INTO `ohlc` (O, H, L, C, CandleNumber, MAINAQUALITY, SPREAD, HL, OC, TICKSINCANDLE) VALUES ("+(string)OpenBuffer[CandleNumber]+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber]+", "+(string)spread+", "+(string)HLBuffer[CandleNumber]+", "+(string)OCBuffer[CandleNumber]+", "+(string)ticks+")";

            if(MySqlExecute(DB,QueryOHCL))
              {}

/*  {
               Print("Succeeded: ",QueryOHCL);
              }
            else
              {
               Print("Error: ",MySqlErrorDescription);
               Print("Query: ",QueryOHCL);
              }*/
           }

         //---
         ticksInCandle[CandleNumber]=ticks;
         ticks=0;
         CandleNumber++;
         OpenBuffer[CandleNumber]=CurrentTick;
         // текущая котировка будет являться максимальной ценой свечи
         HighBuffer[CandleNumber]=CurrentTick;
         // текущая котировка будет являться минимальной ценой свечи
         LowBuffer[CandleNumber]=CurrentTick;
         // текущая котировка пока является ценой закрытия текущей свечи
         CloseBuffer[CandleNumber]=CurrentTick;
         Currentinaquality=(HighBuffer[CandleNumber]-LowBuffer[CandleNumber]);
         Comment(StringFormat("firstStart=%G\nCurrentTick=%G\nCandleNumber=%G,\nOpenBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\ninaquality=%G\nCurrentinaquality=%G",firstStart,CurrentTick,CandleNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],inaquality,Currentinaquality));
        }
      Currentinaquality=(HighBuffer[CandleNumber]-LowBuffer[CandleNumber]);
      Comment(StringFormat("firstStart=%G\nCurrentTick=%G\nCandleNumber=%G,\nOpenBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\ninaquality=%G\nCurrentinaquality=%G",firstStart,CurrentTick,CandleNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],inaquality,Currentinaquality));

     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   MySqlDisconnect(DB);
   Print("Disconnected. done!");
  }
//+------------------------------------------------------------------+
