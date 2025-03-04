//+------------------------------------------------------------------+
//|                                                      Ticker |
//|                                      Copyright 2012, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include <MQLMySQL.mqh>
#property strict
//задае уникальный номер советника
#define MAGICMA  MathRand();
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Generic\HashMap.mqh>

CPositionInfo posinf;
CTrade trade;
//устанавливаем размер лота для откртия позиций
input bool     NewOrderIfLockOpen=false;
input double   InpLots=0.2;
input double   InpMaximumRisk=0.02;                  // Maximal Risk in Percents
input double   InpDecreaseFactor=3;                  // Faktor Umensheniya
input int      InpTrailingStop=20;                   // Trailing Stop Level (in pips)
input int      InpTakeProft=0;                       // Trailing Stop Level (in pips)
input int      InpK1=0;                             // Koefficient Ruchnoy podstroyky inaquality бара
input int      KK_InpK1=2;                         //Корректировочный коэффициент при расчете Inaquality по среднестатистическому между High и Low последних n баров
input int      CandelesPeriodCalculation=100;         // Период за который рассчитываем средестатистичнский размер свечи (разницу между срежнестатистическими High и Low)
input bool     InpBarsOverlappingPercentageFlag=true; //сжатие баров. Если false сжимаем статически , новый бар открываем только если разница между High текущего и предыдущего баров или разница между low текущего и предыдущего баров >= Inaquality
input double   InpBarsOverlappingPercentage=1.3;     // Процент перекрытия предыдущего бара, который считаем как показатель флэта, выше уже не флэт, выше открываем новый бар
enum strategies
  {
   CM=0,     // CrossMA
   CCM=1,     // CandlesCrossMa

  };

//--- input parameters
input strategies tradeStrategy=CCM;

//устанавливаем примерный уровень коммисии взимаемой брокером
int InpComission=3;
//устанавливаем примерный спрэд,взимаемый брокером
int InpSpreadDeviation=5;
//_____________переменные для индикаторных вычислений________________
//переменный для расчет значений скользящих средних
double MA1,MA2;
//Параметр обозначающий разницу между максимумом и минимумом текущей свечи.
//Если разница между максимумом и минимумом больше или равно inaquality, значение текущего тика присваивается
//цене закрытия текущей свечи. , расчитывается на каждом тике
double Inaquality,CurrentTrailingStop;

//--- Параметры первой скользящей средней
input int            InpMAPeriod1=5;         // Period
//, обязательно должен быть меньше чем у второй скользящей средней
input ENUM_MA_METHOD InpMAMethod1=MODE_LWMA;  // Method
//--- indicator buffers
double               MALineBuffer1[];
//--- Параметры второй сколльзящей средней
input int            InpMAPeriod2=8;         // Period
//, обязательно должен быть больше чем у первой скользящей средней
input ENUM_MA_METHOD InpMAMethod2=MODE_LWMA;  // Method
//--- indicator buffers
double               MALineBuffer2[];

//переменная служащая для перебора всех значений элементов массивов
int i=0;
int i1=0;
int i2=0;
int optimization_needed=0;

//переменная firstStart позволяет определить первый раз прилетает новый тик или нет,
//если переменная равна 0 - значит первый, если 1 - значит второй или более
uchar firstStart=0;

//Номера рассчитанных точек для скользящей средней
int MA1Number = 0;
int MA2Number = 0;


//переменные позволяющие определить произошел уже первый расчет скользящих или нет, т.к. пока еще недостаточно свечей на графике после старата работы робота
bool firstMA1Number=false;
bool firstMA2Number=false;
//статистические переменные
double ProfitMin=0;
double ProfitMax=0;

//использовать ли стополосс
bool StoplossOnOff=true;
//пермененная для временного хранения тикета позиции
int tmpTicket=0;
double   SummProfit=0;
//использовать ли Vault
bool Vault=true;
int InpVaultDistance=15;
//+------------------------------------------------------------------+
//|                                                                  |
//|                            Varyables                             |
//|                                                                  |
//+------------------------------------------------------------------+
double   Var_Lots=InpLots;
double   Var_MaximumRisk=InpMaximumRisk;
double   Var_DecreaseFactor=InpDecreaseFactor;
int      Var_TrailingStop=InpTrailingStop;
int      Var_TakeProfit=InpTakeProft;
int      Var_K1=InpK1;
int      Var_Comission=InpComission;
int      Var_SpreadDeviation=InpSpreadDeviation;
int      Var_VaultDistance=InpVaultDistance;
int      Var_MAPeriod1=InpMAPeriod1;
int      Var_MAPeriod2=InpMAPeriod2;
int      Var_Profit=0;

double   Var_InpBarsOverlappingPercentage=InpBarsOverlappingPercentage;
//+----------------------------------------------------- -------------+'
//|                                                                  |
//|                                  Statistics                      |
//|                                                                  |
//+------------------------------------------------------------------+
int commpressedBars=0; //Compressed bars with the same high and low
int commpressedIdenticalBars=0;
//+------------------------------------------------------------------+
//|                         Statistics: ticks                        |
//+------------------------------------------------------------------+
//значения текущего пришедшего тика по ценам спроса и предложения
double CurrentTickBID,CurrentTickASK;

//время прошедшее с момента формирования прошлого тика в секундах
int pause=0;
//время прошедшее с момента старта системы в миллисекундах
ulong startMicSec=0;
//+------------------------------------------------------------------+
//|                         Statistics: candles                      |
//+------------------------------------------------------------------+
//используются для хранения цен OHLC отображаемых свечей, массив
double OpenBuffer[],HighBuffer[],LowBuffer[],CloseBuffer[];
//Хранит номер текущей свечи
int CandleNumber=0;
//разница между скользящими средними
double MaInaquality[];
int MaInaqualityNumber=0;
//расстояние между HIGH и LOW свечи
double HL=0;
//расстояние между OPEN и CLOSE свечи

double OC=0;
//количество тиков в свече
int TicksInCandle=0;
//сработал ли VAULT, false - еще пока не сработал? true - уже сработал и предполагается что закрылось пол позиции
bool Flag_Vault=false;

//+------------------------------------------------------------------+
//|                         Statistics: trends                       |
//+------------------------------------------------------------------+
//порядковый номер тренда
int TrendNumber=0;
//Время формирования тренда (относительно сигналов MA)
int TrendTime=0;
//Прибыль в пунктах, полученная с тренда (относительно сигналов МА)
int TrendProfit=0;
//Высота (размер) тренда в пунктах (относительно сигналов MA)
int TrendSize=0;
//значение точки предыдущего пересечения скользящих
double PreviousIntersectionValue=0;
//Прибылен ли тренд
int ProfitableTrend=0;
//Тип закрытия позиции, 0 - новый сигнал МА, 1 - Стоплосс, 2 - новый сигнал МА с выполнением при этом алгоритма Vault, 3 - по алгоритму Vault с закрытием вторичного ордера по СТОПЛОССу
int ClosingType=0;
//Количество срабатываний трэйлингстопа за тренд
int TrailingCounts=0;
//оличество тиков в треэнде (относительно сигналов МА)
int TrendTickCounts=0;
//наличие первого закрытого ордера на тренд
int Order1=0;
//Время открытия ордера
int Order1_OpenDateTime=0;
//время закрытия ордера
int Order1_CloseDateTime=0;
//время жизни ордера
int Order1_LifeTime=0;
//К какой фазе алгоритма VAULT относится ордер, 0 - ордер закрыт без открытия Vault, 1 - первый закрывающий половину лота, 2 - второй закрывающий остаток лота
int Order1_VaultPhase=0;
//номер тикета первого закрытого ордера
int Order1_PositionTicket=0;
//Тип первого закрытого ордера
int Order1_Type=0;
//Размер лота первого закрытого ордера в тренде
int Order1_Lot=0;
//Размер прибыли в пунктах первого закрытого ордера
int Order1_Profit=0;
//наличие второго закрытого ордера на тренд
int Order2=0;
//Время открытия второго ордера
int Order2_OpenDateTime=0;
//время закрытия второго ордера
int Order2_CloseDateTime=0;
//время жизни второго ордера
int Order2_LifeTime=0;
//К какой фазе алгоритма VAULT относится ордер, 0 - ордер закрыт без открытия Vault, 1 - первый закрывающий половину лота, 2 - второй закрывающий остаток лота
int Order2_VaultPhase=0;
//номер тикета второго закрытого ордера
int Order2_PositionTicket=0;
//Тип второго закрытого ордера
int Order2_Type=0;
//Размер лота второго закрытого ордера в тренде
int Order2_Lot=0;
//Размер прибыли в пунктах второго закрытого ордера
int Order2_Profit=0;
//+------------------------------------------------------------------+
//|                         Statistics: orders                       |
//+------------------------------------------------------------------+
//Время открытия ордера
int OpenDateTime=0;
//время закрытия ордера
int CloseDateTime=0;
//время жизни ордера
int OrderLifeTime=0;
//К какой фазе алгоритма VAULT относится ордер, 0 - просто открытый первичный ордер, 1 - первый закрывающий половину лота, 2 - второй закрывающий остаток лота
int VaultOrderPhase=0;

//время формирования свечи в секундах
int CandleCreationTime=0;
//Количество тиков в свече в соотношении к времени формирования свечи в секундах
float Koeff_TicksInCandle_div_CandleCreationTime=0;
//Высота тренда в пунктах между сигналами скользящих
int TrendHeight=0;
//Коэффициент корректировки 1 (спрэд+коммисия)
int K1;
//Коэффициент корректировки 2 (минимально необходимая прибыль)
int K2;
//Максимальный профит с тренда - разница между точками пересечения MA с учетом (или без учета) задержки в пунктах на открытие позиции
int TrendMaxProfit=0;
//Неэффективность модуля сигналов - разница в пунктах между максимальным расстоянием тренда и максимального профита с тренда. (Больше разница, тем менее эффективней тренд)
int NeEff_MaSign=0;
//Количество тиков в тренде
int TicksInTrend=0;
//Количество свечей в тренде
int CandlesInTrend=0;
//Свечной угол тренда - соотношение количества свеч в тренде к общей высоте тренда
float TrendCandlesAngle=0;
//Количество пересечений скользящих
int MaIntersectionsCount=0;
//Свеча поддержки или сопротивления тренда - Свеча, количество тиков в которой в половине свечи в сторону тренда больше (восходящая/нисходящая)  чем в другой половине свечи. Если равно 1 то свечаподдержки тренда, 0 - сопротивления
int TrendCandle_Support_Resistance=0;
//Ретроспективный угол тренда - соотношение количества пунктов в тренде между сигналами скользящих к количеству свечей в тренде
int RetroTrendAngle=0;
//Текущий угол тренда - соотношение текущего количества пройденных пунктов в тренде к текущему количеству свечй
int CurrentTrendAngle=0;
//Значение начальной точки тренда (сигнал скользящих)
float TrendStartPoint=0;
//Значение конечной точки тренда (сигнал скользящих)
float TrendEndPoint=0;
//статические переменные для учета того, сколько стполоссов сработало на позиция покупки и сколько на позициях продажи
double CurrentStopLossBuy;
double CurrentStopLossSell;
//+------------------------------------------------------------------+
//|                             Trade module                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                             Database module                      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   Database module:переменные для подключения к БД MySQL          |
//+------------------------------------------------------------------+
string Host,User,Password,Database,Socket; // database credentials
int Port,ClientFlag;
int DB; // database identifier
string Query,QueryMA1,QueryMA2;
//переменные для перебора при выоплнении Select для получения значения переменных управляющих параметров
int l,Rows,Cursor;
//+------------------------------------------------------------------+
//|   Database module:управление внешне изменяемыми параметрами      |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------------------------------+
//| Инициализируем хэшмап хранения данных индикатора меры энтропии рынка                     |
//+------------------------------------------------------------------------------------------+
CHashMap<double, int> entropy;


//--- calculation
void CalculateSMA1()
  {
//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==Var_MAPeriod1) && (firstMA1Number==false))
     {
      double firstValue1=0;
      for(i=0;i<Var_MAPeriod1;i++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue1=NormalizeDouble(firstValue1/Var_MAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;
      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
      MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;
     }
   if((CandleNumber-1)>Var_MAPeriod1)
     {
      //тест_стандартная формула расчета МА
      double firstValue1=0;
      for(i1=(CandleNumber-Var_MAPeriod1);i1<CandleNumber;i1++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i1],_Digits);
        }
      firstValue1=NormalizeDouble(firstValue1/Var_MAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA1))
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
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
   if(((CandleNumber-1)==Var_MAPeriod2) && (firstMA2Number==false))// first calculation
     {
      double firstValue2=0;
      for(i=0;i<Var_MAPeriod2;i++)
        {
         firstValue2+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/Var_MAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
      MA2=MALineBuffer2[MA2Number];
      MA2Number++;
      firstMA2Number=true;

     }
   if((CandleNumber-1)>Var_MAPeriod2)
     {
      //тест_стандартная формула расчета МА
      double firstValue2=0;
      for(i2=(CandleNumber-Var_MAPeriod2);i2<CandleNumber;i2++)

        {
         firstValue2+=NormalizeDouble(CloseBuffer[i2],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/Var_MAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
      MA2=MALineBuffer2[MA2Number];
      MA2Number++;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateLWMA1()
  {
//Print("CalculateLWMA1: ");
//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==Var_MAPeriod1) && (firstMA1Number==false))
     {
      int  weightsum=0;
      double firstValue1=0;
      for(i=0;i<Var_MAPeriod1;i++)
        {
         //весовой коэффициент равный номеру текущему значению Candlenumber
         int k=InpMAPeriod1-i;
         firstValue1+=CloseBuffer[i]*k;
         weightsum+=k;
        }

      firstValue1=NormalizeDouble(firstValue1/(double)weightsum,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
      MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;

     }
   if((CandleNumber-1)>Var_MAPeriod1)
     {
      //Print("_______________Zero divide:Start MA_debug interation");
      //тест_стандартная формула расчета МА
      int MAincr=1;
      int  weightsum=0;
      double firstValue1=0;
      for(i1=(CandleNumber-Var_MAPeriod1);i1<CandleNumber;i1++)
        {
         int k=MAincr;
         firstValue1+=CloseBuffer[i1]*k;
         weightsum+=MAincr;
         MAincr++;
         //Print("MAincr= ",MAincr);
        }

      //Print("weightsum(final)= ",weightsum);
      //Print("(double)weightsum(final)= ",(double)weightsum);

      firstValue1=NormalizeDouble(firstValue1/(double)weightsum,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;
      MA1=MALineBuffer1[MA1Number];
      //Print("MA1: ",MA1);
      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      MA1Number++;
      if(MySqlExecute(DB,QueryMA1))

        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
      //Print("_______________Zero divide:End MA_debug interation");
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateLWMA2()
  {

//вычисление первого значения Moving Average. Происходит если количество свеч равно периоду МА1 и ранее первое значение  МА1 не вычислялось
   if(((CandleNumber-1)==Var_MAPeriod2) && (firstMA2Number==false))
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
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
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
      for(i2=(CandleNumber-Var_MAPeriod2);i2<CandleNumber;i2++)
        {
         int k=MAincr;
         firstValue2+=CloseBuffer[i2]*k;
         weightsum+=MAincr;
         MAincr++;
        }

      firstValue2=NormalizeDouble(firstValue2/weightsum,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
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
      double SmoothFactor=2.0/(1.0+Var_MAPeriod1);
      double firstValue1=0;

      for(i=0;i<Var_MAPeriod1;i++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue1=NormalizeDouble(firstValue1/Var_MAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
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
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
      MA1=MALineBuffer1[MA1Number];
      MA1Number++;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculateEMA2()
  {

   if(((CandleNumber-1)==Var_MAPeriod2) && (firstMA2Number==false))
     {
      double SmoothFactor=2.0/(1.0+Var_MAPeriod2);
      double firstValue2=0;

      for(i=0;i<InpMAPeriod2;i++)
        {
         firstValue2+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue2=NormalizeDouble(firstValue2/Var_MAPeriod2,_Digits);
      MALineBuffer2[MA2Number]=firstValue2;
      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";

      if(MySqlExecute(DB,QueryMA2))
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
      MA2=MALineBuffer2[MA2Number];
      MA2Number++;
      firstMA2Number=true;

     }
   if((CandleNumber-1)>Var_MAPeriod2)
     {

      double SmoothFactor=2.0/(1.0+InpMAPeriod2);
      /*   Print("CloseBuffer[CandleNumber]: ",CloseBuffer[CandleNumber]);
            Print("MALineBuffer2[MA2Number-1]: ",MALineBuffer2[MA2Number-1]);
            Print("1-SmoothFactor: ",1-SmoothFactor);
            Print("((MALineBuffer2[MA2Number-1])*(1-SmoothFactor): ",((MALineBuffer2[MA2Number-1])*(1-SmoothFactor)));
      */
      MALineBuffer2[MA2Number]=(CloseBuffer[CandleNumber]*SmoothFactor)+((MALineBuffer2[MA2Number-1])*(1-SmoothFactor));
      //   Print("MALineBuffer2[MA2Number]: ",MALineBuffer2[MA2Number]);

      QueryMA2="INSERT INTO `ma2_data` (MaPERIOD2, MA2VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod2+", "+(string)MALineBuffer2[MA2Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA2))
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
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
   if(((CandleNumber-1)==Var_MAPeriod1) && (firstMA1Number==false))
     {

      double firstValue1=0;
      for(i=0;i<Var_MAPeriod1;i++)
        {
         firstValue1+=NormalizeDouble(CloseBuffer[i],_Digits);
        }

      firstValue1=NormalizeDouble(firstValue1/Var_MAPeriod1,_Digits);
      MALineBuffer1[MA1Number]=firstValue1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)Var_MAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
      MA1=MALineBuffer1[MA1Number];
      MA1Number++;
      firstMA1Number=true;

     }
   if((CandleNumber-1)>InpMAPeriod1)
     {

      //тест_стандартная формула расчета МА
      MALineBuffer1[MA1Number]=((MALineBuffer1[MA1Number-1]*(Var_MAPeriod1-1))+CloseBuffer[CandleNumber])/Var_MAPeriod1;

      QueryMA1="INSERT INTO `ma1_data` (MaPERIOD1, MA1VALUE, CandleNumber) VALUES ("+(string)InpMAPeriod1+", "+(string)MALineBuffer1[MA1Number]+", "+(string)CandleNumber+")";
      if(MySqlExecute(DB,QueryMA1))
        {
         //Print("Succeeded: ",QueryMA1);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA1);
        }
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
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
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
        {
         //Print("Succeeded: ",QueryMA2);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",QueryMA2);
        }
      MA2=MALineBuffer2[MA2Number];
      MA2Number++;
     }

  }
//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
//функция для расчета оптимального значения лота для открытия позиции
double LotsOptimized()
  {
   double lot=InpLots;
//--- return lot size
   if(lot<0.1)
      lot=0.1;
//return(lot);
   return(0.02);
  }

//+------------------------------------------------------------------+
//| Trading Function                                       |
//+------------------------------------------------------------------+
//функция для принятия торовых решений в части закрытия текущей позиции и открытия новой исходя из наличия сигналов пересечения скользящих средних
void CheckPositions(void)
  {


//проверяем рассчитавалась ли разница между скользящими средними, если нет, то не имеет смысла дальнейшее выполнение кода функции CheckPositions()
   if(MaInaqualityNumber<=0)
     {
      Print("CheckPositions:Вторая скользящая средняя еще не рассчитывалась,MaInaqualityNumber=",MaInaqualityNumber);
      return;
     }
//Print("CheckPositions");
//--- check signals
// ENUM_ORDER_TYPE signal=WRONG_VALUE;

   if((MaInaquality[MaInaqualityNumber]<0 && MaInaquality[MaInaqualityNumber-1]<0) || (MaInaquality[MaInaqualityNumber]>0 && MaInaquality[MaInaqualityNumber-1]>0))
     {
      return;
     }

   int PositionTicket=NULL;
   switch(tradeStrategy)
     {

      case CM:

         //SELL - сигнал
         if(MaInaquality[MaInaqualityNumber]>0 && MaInaquality[MaInaqualityNumber-1]<0)
           {
            //значению цены в последнем пересечении скользящих задаем значение текущего тика
            PreviousIntersectionValue=CurrentTickBID;
            //Если есть открытые позиции
            if(PositionsTotal()!=0)
              {
               //выбираем текущую открытую позицию по символу для работы с ним
               if(posinf.Select(_Symbol))
                 {
                  tmpTicket=(int)PositionGetTicket(0);
                  //выполняем операцию закрытия позиции с одновременной проверкой успешности
                  if(!trade.PositionClose(_Symbol,40))
                    {
                     Print("Position close failed:",trade.ResultRetcodeDescription());
                     //continue;
                    }
                  else
                    {
                     posinf.Select(_Symbol);
                     /*Print("CheckPositions():SELL:BUY-Position Closed:TimeCurrent()=",TimeCurrent());
                                    Print("CheckPositions():SELL:BUY-Position Closed:TimeLocal()=",TimeLocal());
                                    Print("CheckPositions():SELL:BUY-Position Closed:PositionTicket=",tmpTicket);*/
                     //меняем флаг указывающий на то что метод управления рисками можно использовать
                     Flag_Vault=false;
                    }
                 }
               else
                 {
                  Print("SELL-SIGNAL:Position Closed:SELL:ERROR:Posistion Select error",GetLastError());
                 }
              }
            //если нет открытых позиций
            if(PositionsTotal()==0)
              {
               //меняем флаг указывающий на то что метод управления рисками можно использовать
               Flag_Vault=false;

               //открываем новую позицию на SELL  с одновременной проверкой успешности выполнения
               if(!trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,LotsOptimized(),SymbolInfoDouble(_Symbol,SYMBOL_BID),0,Var_TakeProfit))
                 {
                  Print("Position open failed:",trade.ResultRetcodeDescription());
                 }
               else
                 {
                  posinf.Select(_Symbol);
                  /* Print("CheckPositions():SELL:BUY-Position Closed:TimeCurrent()=",TimeCurrent());
                              Print("CheckPositions():SELL:BUY-Position Closed:TimeLocal()=",TimeLocal());
                              Print("CheckPositions():SELL:BUY-Position Closed:PositionTicket=",PositionGetTicket(0));*/

                  //статистика. увеличиваем счетчик трендов
                  TrendNumber++;
                  /*  //Пишем в MySQL данные завершенного тренда
                           Query="INSERT INTO `trends` (TRENDNUMBER,TRENDPROFIT,TRENDSIZE,PROFITABLETREND,CLOSINGTYPE,TRAILINGSTOPSIZE_MOVEDSUMMARY,TRAILNGCOUNTS,TRENDTICKCOUNT,ORDER1,ORDER1_PositionTicket,ORDER1_TYPE,ORDER1_LOT,ORDER1_PROFIT,ORDER2,ORDER2_PositionTicket,ORDER2_TYPE,ORDER2_LOT,ORDER2_PROFIT) VALUES ("+"now()"+", "+(string)TrendNumber+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber]+", "+(string)SpreadDeviation+", "+(string)TicksInCandle+")";
                           if(MySqlExecute(DB,Query))
                             {
                              Print("Succeeded: ",Query);
                             }
                           else
                             {
                              Print("Error: ",MySqlErrorDescription);
                              Print("Query: ",Query);

                              TrendProfit=0;
                             }
                             */
                 }
              }
           }
         //BUY - сигнал
         if(MaInaquality[MaInaqualityNumber]<0 && MaInaquality[MaInaqualityNumber-1]>0)
           {
            //значению цены в последнем пересечении скользящих задаем значение текущего тика
            PreviousIntersectionValue=CurrentTickBID;
            //first closing Current BUY-position if it opened
            //Если нет открытых позиций
            if(PositionsTotal()!=0)
              {
               //выбираем текущую открытую позицию по символу для работы с ним
               if(posinf.Select(_Symbol))
                 {
                  tmpTicket=(int)PositionGetTicket(0);
                  //выполняем операцию закрытия позиции с одновременной проверкой успешности
                  if(!trade.PositionClose(_Symbol,40)) ///ЕСЛИ BUY
                    {
                     Print("Position close failed:",trade.ResultRetcodeDescription());
                     //continue;
                    }
                  else
                    {
                     posinf.Select(_Symbol);
                     /*Print("CheckPositions():BUY:SELL-Position Closed::TimeCurrent()=",TimeCurrent());
                                    Print("CheckPositions():BUY:SELL-Position Closed::TimeLocal()=",TimeLocal());
                                    Print("CheckPositions():BUY:SELL-Position Closed:PositionTicket=",tmpTicket);*/
                     //меняем флаг указывающий на то что метод управления рисками можно использовать
                     Flag_Vault=false;
                    }
                  //статистика. увеличиваем счетчик трендов
                  TrendNumber++;
                  /*   //Пишем в MySQL данные завершенного тренда
                                 Query="INSERT INTO `trends` (TRENDNUMBER,TRENDPROFIT,TRENDSIZE,PROFITABLETREND,CLOSINGTYPE,TRAILINGSTOPSIZE_MOVEDSUMMARY,TRAILNGCOUNTS,TRENDTICKCOUNT,ORDER1,ORDER1_PositionTicket,ORDER1_TYPE,ORDER1_LOT,ORDER1_PROFIT,ORDER2,ORDER2_PositionTicket,ORDER2_TYPE,ORDER2_LOT,ORDER2_PROFIT) VALUES ("+"now()"+", "+(string)TrendNumber+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber]+", "+(string)SpreadDeviation+", "+(string)TicksInCandle+")";
                                 if(MySqlExecute(DB,Query))
                                   {
                                    Print("Succeeded: ",Query);
                                   }
                                 else
                                   {
                                    Print("Error: ",MySqlErrorDescription);
                                    Print("Query: ",Query);

                                    TrendProfit=0;
                                   }
                                   */

                 }
               else
                 {
                  Print("BUY-SIGNAL:Position Closed:SELL:0:ERROR:1:OrderSelect error",GetLastError());
                 }
              }
            //если нет открытых позиций
            if(PositionsTotal()==0)
              {
               //меняем флаг указывающий на то что метод управления рисками можно использовать
               Flag_Vault=false;
               //просто открываем новый ордер на BUY с одновременной проверкой успешности
               if(!trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,LotsOptimized(),SymbolInfoDouble(_Symbol,SYMBOL_ASK),0,Var_TakeProfit))
                 {
                  Print("Position open failed:",trade.ResultRetcodeDescription());
                 }
               else
                 {
                  posinf.Select(_Symbol);
                  /*Print("CheckPositions():BUY:SELL-Position Closed::TimeCurrent()=",TimeCurrent());
                              Print("CheckPositions():BUY:SELL-Position Closed::TimeLocal()=",TimeLocal());
                              Print("CheckPositions():BUY:SELL-Position Closed:PositionTicket=",PositionGetTicket(0));*/
                  Flag_Vault=false;
                 }
              }
           }
         break;

      //

      case CCM:
         //+------------------------------------------------------------------+
         //|       Candle-Cross-Ma strategy                                   |
         //+------------------------------------------------------------------+



         //SELL - сигнал
         //Свеча падающая и закрылась ниже MA1
         if(CloseBuffer[CandleNumber] < OpenBuffer[CandleNumber] && CloseBuffer[CandleNumber] < MaInaquality[MaInaqualityNumber])
           {
            //значению цены в последнем пересечении скользящих задаем значение текущего тика
            PreviousIntersectionValue=CurrentTickBID;
            //Если есть открытые позиции
            if(PositionsTotal()!=0)
              {
               //выбираем текущую открытую позицию по символу для работы с ним
               if(posinf.Select(_Symbol))
                 {
                  tmpTicket=(int)PositionGetTicket(0);
                  //выполняем операцию закрытия позиции с одновременной проверкой успешности
                  if(!trade.PositionClose(_Symbol,40))
                    {
                     Print("Position close failed:",trade.ResultRetcodeDescription());
                     //continue;
                    }
                  else
                    {
                     posinf.Select(_Symbol);
                     /*Print("CheckPositions():SELL:BUY-Position Closed:TimeCurrent()=",TimeCurrent());
                                    Print("CheckPositions():SELL:BUY-Position Closed:TimeLocal()=",TimeLocal());
                                    Print("CheckPositions():SELL:BUY-Position Closed:PositionTicket=",tmpTicket);*/
                     //меняем флаг указывающий на то что метод управления рисками можно использовать
                     Flag_Vault=false;
                    }
                 }
               else
                 {
                  Print("SELL-SIGNAL:Position Closed:SELL:ERROR:Posistion Select error",GetLastError());
                 }
              }
            //если нет открытых позиций
            if(PositionsTotal()==0)
              {
               //меняем флаг указывающий на то что метод управления рисками можно использовать
               Flag_Vault=false;

               //открываем новую позицию на SELL  с одновременной проверкой успешности выполнения
               if(!trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,LotsOptimized(),SymbolInfoDouble(_Symbol,SYMBOL_BID),0,Var_TakeProfit))
                 {
                  Print("Position open failed:",trade.ResultRetcodeDescription());
                 }
               else
                 {
                  posinf.Select(_Symbol);
                  /* Print("CheckPositions():SELL:BUY-Position Closed:TimeCurrent()=",TimeCurrent());
                              Print("CheckPositions():SELL:BUY-Position Closed:TimeLocal()=",TimeLocal());
                              Print("CheckPositions():SELL:BUY-Position Closed:PositionTicket=",PositionGetTicket(0));*/

                  //статистика. увеличиваем счетчик трендов
                  TrendNumber++;
                  /*  //Пишем в MySQL данные завершенного тренда
                           Query="INSERT INTO `trends` (TRENDNUMBER,TRENDPROFIT,TRENDSIZE,PROFITABLETREND,CLOSINGTYPE,TRAILINGSTOPSIZE_MOVEDSUMMARY,TRAILNGCOUNTS,TRENDTICKCOUNT,ORDER1,ORDER1_PositionTicket,ORDER1_TYPE,ORDER1_LOT,ORDER1_PROFIT,ORDER2,ORDER2_PositionTicket,ORDER2_TYPE,ORDER2_LOT,ORDER2_PROFIT) VALUES ("+"now()"+", "+(string)TrendNumber+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber]+", "+(string)SpreadDeviation+", "+(string)TicksInCandle+")";
                           if(MySqlExecute(DB,Query))
                             {
                              Print("Succeeded: ",Query);
                             }
                           else
                             {
                              Print("Error: ",MySqlErrorDescription);
                              Print("Query: ",Query);

                              TrendProfit=0;
                             }
                             */
                 }
              }
           }
         //BUY - сигнал
         //Свеча осходящая и закрылась выше MA1
         if(CloseBuffer[CandleNumber] > OpenBuffer[CandleNumber] && CloseBuffer[CandleNumber] > MaInaquality[MaInaqualityNumber])
           {
            //значению цены в последнем пересечении скользящих задаем значение текущего тика
            PreviousIntersectionValue=CurrentTickBID;
            //first closing Current BUY-position if it opened
            //Если нет открытых позиций
            if(PositionsTotal()!=0)
              {
               //выбираем текущую открытую позицию по символу для работы с ним
               if(posinf.Select(_Symbol))
                 {
                  tmpTicket=(int)PositionGetTicket(0);
                  //выполняем операцию закрытия позиции с одновременной проверкой успешности
                  if(!trade.PositionClose(_Symbol,40)) ///ЕСЛИ BUY
                    {
                     Print("Position close failed:",trade.ResultRetcodeDescription());
                     //continue;
                    }
                  else
                    {
                     posinf.Select(_Symbol);
                     /*Print("CheckPositions():BUY:SELL-Position Closed::TimeCurrent()=",TimeCurrent());
                                    Print("CheckPositions():BUY:SELL-Position Closed::TimeLocal()=",TimeLocal());
                                    Print("CheckPositions():BUY:SELL-Position Closed:PositionTicket=",tmpTicket);*/
                     //меняем флаг указывающий на то что метод управления рисками можно использовать
                     Flag_Vault=false;
                    }
                  //статистика. увеличиваем счетчик трендов
                  TrendNumber++;
                  /*   //Пишем в MySQL данные завершенного тренда
                                 Query="INSERT INTO `trends` (TRENDNUMBER,TRENDPROFIT,TRENDSIZE,PROFITABLETREND,CLOSINGTYPE,TRAILINGSTOPSIZE_MOVEDSUMMARY,TRAILNGCOUNTS,TRENDTICKCOUNT,ORDER1,ORDER1_PositionTicket,ORDER1_TYPE,ORDER1_LOT,ORDER1_PROFIT,ORDER2,ORDER2_PositionTicket,ORDER2_TYPE,ORDER2_LOT,ORDER2_PROFIT) VALUES ("+"now()"+", "+(string)TrendNumber+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber]+", "+(string)SpreadDeviation+", "+(string)TicksInCandle+")";
                                 if(MySqlExecute(DB,Query))
                                   {
                                    Print("Succeeded: ",Query);
                                   }
                                 else
                                   {
                                    Print("Error: ",MySqlErrorDescription);
                                    Print("Query: ",Query);

                                    TrendProfit=0;
                                   }
                                   */

                 }
               else
                 {
                  Print("BUY-SIGNAL:Position Closed:SELL:0:ERROR:1:OrderSelect error",GetLastError());
                 }
              }
            //если нет открытых позиций
            if(PositionsTotal()==0)
              {
               //меняем флаг указывающий на то что метод управления рисками можно использовать
               Flag_Vault=false;
               //просто открываем новый ордер на BUY с одновременной проверкой успешности
               if(!trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,LotsOptimized(),SymbolInfoDouble(_Symbol,SYMBOL_ASK),0,Var_TakeProfit))
                 {
                  Print("Position open failed:",trade.ResultRetcodeDescription());
                 }
               else
                 {
                  posinf.Select(_Symbol);
                  /*Print("CheckPositions():BUY:SELL-Position Closed::TimeCurrent()=",TimeCurrent());
                              Print("CheckPositions():BUY:SELL-Position Closed::TimeLocal()=",TimeLocal());
                              Print("CheckPositions():BUY:SELL-Position Closed:PositionTicket=",PositionGetTicket(0));*/
                  Flag_Vault=false;
                 }
              }
           }

         break;

     }
//проверка на наличие сигнала BUY или SELL, иначе выходим из функции


//+------------------------------------------------------------------+
//|             Проверяем нужна ли оптимизация                       |
//+------------------------------------------------------------------+
//запрашиваем торговую историю
   HistorySelect(0,TimeCurrent());

//создаем объекты
   uint     total=HistoryDealsTotal();
   Print("HistoryDealsTotal: ",total);
   ulong    ticket=0;
   double   profit;
   long     type;
   long     entry;
   double prevSummaryProfit=SummProfit;

//--- for all deals
   for(uint e=total;e>total-20;e--)
     {
      //--- try to get deals ticket
      if((ticket=HistoryDealGetTicket(e))>0)
        {
         //Print("ticket: ",ticket);
         //--- get deals properties
         //price =HistoryDealGetDouble(ticket,DEAL_PRICE);
         //time  =(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
         //symbol=HistoryDealGetString(ticket,DEAL_SYMBOL);
         type=HistoryDealGetInteger(ticket,DEAL_TYPE);
         // Print("type: ",type);
         entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         // Print("entry: ",entry);
         profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
         // Print("profit: ",profit);
         SummProfit+=profit;
         // Print("SummProfit: ",SummProfit);
        }
     }

//смотрим в таблице, идет ли еще процесс оптимизации параметров во внешней программе, если равно 1 значит пишем запрос оптимизации в таблицу

   Query="SELECT optimization_needed FROM optimization_request;";

//Print("SQL>",Query);
   Cursor=MySqlCursorOpen(DB,Query);
   if(Cursor>=0)
     {
      Rows=MySqlCursorRows(Cursor);
      Print("SELECT optimization_needed:",Rows,"row(s) selected");
      for(l=0; l<Rows;l++)
         if(MySqlCursorFetchRow(Cursor))
           {
            optimization_needed=MySqlGetFieldAsInt(Cursor,0);
            Print("optimization_needed=",optimization_needed);
           }
      MySqlCursorClose(Cursor);
     }
   else
     {
      Print("Cursor openning failed. Error: ",MySqlErrorDescription);
     }

   if(SummProfit<=0 && optimization_needed==0 && CandleNumber>40)
     {

      //
      Query="UPDATE optimization_request SET optimization_needed=1, request_datetime=now(), last_summary_profit="+(string)prevSummaryProfit+" ORDER BY number DESC LIMIT 1;";

      if(MySqlExecute(DB,Query))
        {
         Print("Optimizatation Request Succeeded : ",Query);
        }
      else
        {
         Print("67:Error: ",MySqlErrorDescription);
         Print("67:Query: ",Query);
        }
     }

   if(optimization_needed==3)
     {
      Print("optimization_needed(3)=",optimization_needed);

      Query="SELECT Inaquality,LWMA1,LWMA2,TP,TrStop,VltDist,MAX(Profit) FROM ask_bid_result ;";

      //Print("SQL>",Query);
      Cursor=MySqlCursorOpen(DB,Query);
      if(Cursor>=0)
        {
         Rows=MySqlCursorRows(Cursor);
         Print("SELECT optimization_needed:",Rows,"row(s) selected");
         for(l=0; l<Rows;l++)
            if(MySqlCursorFetchRow(Cursor))
              {
               Var_K1=MySqlGetFieldAsInt(Cursor,0);
               Print("Var_K1=",Var_K1);
               Var_MAPeriod1=MySqlGetFieldAsInt(Cursor,1);
               Print("Var_MAPeriod1=",Var_MAPeriod1);
               Var_MAPeriod2=MySqlGetFieldAsInt(Cursor,2);
               Print("Var_MAPeriod2=",Var_MAPeriod2);
               Var_TakeProfit=MySqlGetFieldAsInt(Cursor,3);
               Print("Var_TakeProfit=",Var_TakeProfit);
               Var_TrailingStop=MySqlGetFieldAsInt(Cursor,4);
               Print("Var_TrailingStop=",Var_TrailingStop);
               Var_VaultDistance=MySqlGetFieldAsInt(Cursor,5);
               Print("Var_VaultDistance=",Var_VaultDistance);
               Var_Profit=MySqlGetFieldAsInt(Cursor,6);
               Print("Var_Profit=",Var_Profit);
              }
         MySqlCursorClose(Cursor);
        }
      else
        {
         Print("Cursor openning failed. Error: ",MySqlErrorDescription);
        }

      //Вставляем в optimization_result для истории
      Query="INSERT INTO `optimization_results` (request_datetime,result_datetime,last_summary_profit,ma1_period,ma2_period,K1,vaultdistance,trailingstop,takeprofit,comission,spreaddeviation)"
            " VALUES ((select request_datetime from optimization_request ORDER BY number DESC LIMIT 1),"+"now()"+","+(string)Var_Profit+","+(string)Var_MAPeriod1+", "+(string)Var_MAPeriod2+", "+(string)Var_K1+", "
            +(string)Var_VaultDistance+", "+(string)Var_TrailingStop+", "+(string)Var_TakeProfit+", "+(string)Var_Comission+", "+(string)Var_SpreadDeviation+");";

      if(MySqlExecute(DB,Query))
        {
         Print("199Succeeded: ",Query);
        }
      else
        {
         Print("99Error: ",MySqlErrorDescription);
         Print("99Query: ",Query);
        }

      //пишем в базу что оптимизацию можно считать выполненной
      Query="UPDATE optimization_request SET  optimization_needed=0, request_datetime="+"now()"+", last_summary_profit=0 WHERE  number = 1;";
      if(MySqlExecute(DB,Query))
        {
         //Print("8INSERT INTO `optimization_request`:Succeeded: ",Query);
        }
      else
        {
         Print("8Error: ",MySqlErrorDescription);
         Print("8Query: ",Query);
        }

     }
   Print("SummaryPositionsProfit: ",SummProfit);

//+------------------------------------------------------------------+
//|       конец блока проверки необходимости оптимизации             |
//+------------------------------------------------------------------+

   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit()
  {

   Print(MySqlVersion());
   string INI=TerminalInfoString(TERMINAL_PATH)+"\\MQL5\\Scripts\\MyConnection.ini";

// reading database credentials from INI file
   Host="127.0.0.1";
   User="root";
   Password = "Qw123456";
   Database = "";
   Port     = 3306;
   Socket="0";
   ClientFlag=0;

// open database connection
   Print("1Connecting...");
   DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
   if(DB==-1)
     {
      Print("0:Connection failed! Error: "+MySqlErrorDescription);
     }
   else
     {
      Print("Connected! DBID#",DB);
     }

//+------------------------------------------------------------------+
//|            Create database for current Symbol                    |
//+------------------------------------------------------------------+
//удаляем все значения из таблицы eurusd
   Query="CREATE DATABASE IF NOT EXISTS `"+Symbol()+"` CHARACTER SET utf8 COLLATE utf8_general_ci;";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|            Select database for current Symbol                    |
//+------------------------------------------------------------------+
   Query="USE `"+Symbol()+"`;";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }

//+------------------------------------------------------------------+
//|                         Truncate table "ticks"                   |
//+------------------------------------------------------------------+
//удаляем все значения из таблицы ticks
   Query="TRUNCATE TABLE `ticks`;";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                         Truncate table "TradingVariables"                   |
//+------------------------------------------------------------------+
//удаляем все значения из таблицы ticks
   Query="TRUNCATE TABLE `TradingVariables`;";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "candles"      |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `candles`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }

//+------------------------------------------------------------------+
//|                      Truncate table "trends"                     |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `trends`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "orders"                     |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `orders`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "ma1_data"                   |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `ma1_data`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "ma2_data"                   |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `ma2_data`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "rsi"                        |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `rsi`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "ASK_BID_result"                 |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `ASK_BID_result`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "stochastic"                 |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `stochastic`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "optimiz_request"                 |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `optimization_request`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                      Truncate table "optimization_results"                 |
//+------------------------------------------------------------------+
   Query="TRUNCATE TABLE `optimization_results`";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }

//+------------------------------------------------------------------+
//|                Creating Table for ticks statistics               |
//+------------------------------------------------------------------+
   Query="CREATE TABLE IF NOT EXISTS ticks (number int(11) NOT NULL AUTO_INCREMENT,DATETIME datetime DEFAULT NULL,BID double DEFAULT NULL,ASK double DEFAULT NULL,SPREAD int(11) DEFAULT NULL,"
         "PAUSE int(11) DEFAULT NULL,PRIMARY KEY (number),CANDLENUMBER int(11) DEFAULT 0, COMISSION int(11) DEFAULT NULL) ENGINE = MEMORY CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT = DYNAMIC;";

   if(MySqlExecute(DB,Query))
     {
      // Print("1Succeeded: ",Query);
     }
   else
     {
      Print("1Error: ",MySqlErrorDescription);
      Print("1Query: ",Query);
     }
//+------------------------------------------------------------------+
//|              Creating Table for candles statistics               |
//+------------------------------------------------------------------+
   Query="CREATE TABLE IF NOT EXISTS candles (number int(11) NOT NULL AUTO_INCREMENT,DATETIME datetime DEFAULT NULL,O float DEFAULT NULL,H float DEFAULT NULL,L float DEFAULT NULL,C float DEFAULT NULL,Candlenumber int(11) DEFAULT NULL,"
         "MAINAQUALITY int(11) DEFAULT NULL,SPREAD int(11) DEFAULT NULL,OC int(11) DEFAULT NULL,HL int(11) DEFAULT NULL,TICKSINCANDLE int(11) DEFAULT NULL,"
         "PRIMARY KEY (number)) ENGINE = MEMORY AUTO_INCREMENT = 1 CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT = DYNAMIC;";

   if(MySqlExecute(DB,Query))
     {
      // Print("2Succeeded: ",Query);
     }
   else
     {
      Print("2Error: ",MySqlErrorDescription);
      Print("2Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                Creating Table for ma1_data statistics            |
//+------------------------------------------------------------------+
   Query="CREATE TABLE IF NOT EXISTS ma1_data (number int(11) NOT NULL AUTO_INCREMENT,DATETIME datetime DEFAULT NULL,MAPERIOD1 int(11) DEFAULT NULL,MA1VALUE double DEFAULT NULL,CANDLENUMBER int(11) DEFAULT NULL,"
         "PRIMARY KEY (number)) ENGINE = MEMORY CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT = DYNAMIC;";

   if(MySqlExecute(DB,Query))
     {
      // Print("3Succeeded: ",Query);
     }
   else
     {
      Print("3Error: ",MySqlErrorDescription);
      Print("3Query: ",Query);
     }
//+------------------------------------------------------------------+
//|                Creating Table for ma2_data statistics            |
//+------------------------------------------------------------------+
   Query="CREATE TABLE IF NOT EXISTS ma2_data (number int(11) NOT NULL AUTO_INCREMENT,DATETIME datetime DEFAULT NULL,MAPERIOD2 int(11) DEFAULT NULL,MA2VALUE double DEFAULT NULL,CANDLENUMBER int(11) DEFAULT NULL,"
         "PRIMARY KEY (number)) ENGINE = MEMORY CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT = DYNAMIC;";

   if(MySqlExecute(DB,Query))
     {
      // Print("4Succeeded: ",Query);
     }
   else
     {
      Print("4Error: ",MySqlErrorDescription);
      Print("4Query: ",Query);
     }

//+------------------------------------------------------------------+
//|                Creating Table for TradingVariables               |
//+------------------------------------------------------------------+
   Query="CREATE TABLE IF NOT EXISTS TradingVariables (number int(11) NOT NULL AUTO_INCREMENT,comission int(11) DEFAULT 3,"
         "PRIMARY KEY (number)) ENGINE = MEMORY CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT = DYNAMIC;";

   if(MySqlExecute(DB,Query))
     {
      // Print("5Succeeded: ",Query);
     }
   else
     {
      Print("5Error: ",MySqlErrorDescription);
      Print("5Query: ",Query);
     }
   Query="INSERT INTO `TradingVariables` (comission) VALUES ("+(string)Var_Comission+")";
   startMicSec=GetTickCount();
   if(MySqlExecute(DB,Query))
     {
      //   Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
     }
//+------------------------------------------------------------------+
//|              Creating Table for trends statistics                |
//+------------------------------------------------------------------+
   Query="CREATE TABLE IF NOT EXISTS trends (number int(11) NOT NULL AUTO_INCREMENT,"
         "TRENDNUMBER int(11) DEFAULT NULL,TRENDTIME int(11) DEFAULT NULL,TRENDPROFIT int(11) DEFAULT NULL,TRENDSIZE int(11) DEFAULT NULL,PROFITABLETREND int(11) DEFAULT NULL,VAULTFLAG int(11) DEFAULT NULL,"
         "TRAILINGSTOPSIZE_MOVEDSUMMARY int(11) DEFAULT NULL,TRAILNGCOUNTS int(11) DEFAULT NULL,TRENDTICKCOUNT int(11) DEFAULT NULL, VAULT_FLAG int(11) DEFAULT NULL,"
         "ORDER1 int(11) DEFAULT NULL,ORDER1_OPENDATETIME datetime DEFAULT NULL,ORDER1_CLOSEDATETIME datetime DEFAULT NULL,ORDER1_LIFEETIME datetime DEFAULT NULL,ORDER1_ORDERTYPE int(11) DEFAULT NULL,"
         "ORDER1_PositionTicket int(11) DEFAULT NULL,ORDER1_TYPE int(11) DEFAULT NULL,ORDER1_LOT float(11) DEFAULT NULL,ORDER1_PROFIT int(11) DEFAULT NULL,ORDER1_VAULTPHASE int(11) DEFAULT NULL,"
         "ORDER2 int(11) DEFAULT NULL,ORDER2_OPENDATETIME datetime DEFAULT NULL,ORDER2_CLOSEDATETIME datetime DEFAULT NULL,ORDER2_LIFEETIME datetime DEFAULT NULL,ORDER2_ORDERTYPE int(11) DEFAULT NULL,"
         "ORDER2_PositionTicket int(11) DEFAULT NULL,ORDER2_TYPE int(11) DEFAULT NULL,ORDER2_LOT float(11) DEFAULT NULL,ORDER2_PROFIT int(11) DEFAULT NULL,ORDER2_VAULTPHASE int(11) DEFAULT NULL,"
         "PRIMARY KEY (number)) ENGINE = MEMORY AUTO_INCREMENT = 1 CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT = DYNAMIC;";

   if(MySqlExecute(DB,Query))
     {
      // Print("6Succeeded: ",Query);
     }
   else
     {
      Print("6Error: ",MySqlErrorDescription);
      Print("6Query: ",Query);
     }

//+------------------------------------------------------------------+
//|              Creating Table for optimization requests            |
//+------------------------------------------------------------------+

   Query="CREATE TABLE "+Symbol()+".optimization_request (number int(11) NOT NULL AUTO_INCREMENT, optimization_needed tinyint(4) DEFAULT 0, request_datetime datetime DEFAULT NULL, last_summary_profit tinyint(4) DEFAULT 0, "
         "PRIMARY KEY (number)) ENGINE = MEMORY, AVG_ROW_LENGTH = 13, CHARACTER SET utf8,COLLATE utf8_general_ci;";

   if(MySqlExecute(DB,Query))
     {
      // Print("7Succeeded: ",Query);
     }
   else
     {
      Print("7Error: ",MySqlErrorDescription);
      Print("7Query: ",Query);
     }

   Query="INSERT INTO `optimization_request` (number,optimization_needed,request_datetime,last_summary_profit) VALUES (1,0,"+"now()"+",0"+");";
   if(MySqlExecute(DB,Query))
     {
      //Print("8INSERT INTO `optimization_request`:Succeeded: ",Query);
     }
   else
     {
      Print("8Error: ",MySqlErrorDescription);
      Print("8Query: ",Query);
     }

//+------------------------------------------------------------------+
//|          Creating Table for optimization results                 |
//+------------------------------------------------------------------+



   Query="CREATE TABLE optimization_results (Number int(11) NOT NULL AUTO_INCREMENT, request_datetime datetime DEFAULT NULL, result_datetime datetime DEFAULT NULL, last_summary_profit int(11) DEFAULT NULL,"
         "ma1_period tinyint(4) DEFAULT 5, ma2_period tinyint(4) DEFAULT 14, K1 tinyint(4) DEFAULT 30, vaultdistance tinyint(4) DEFAULT 15, trailingstop tinyint(4) DEFAULT 20, takeprofit tinyint(4) DEFAULT 0, comission tinyint(4) DEFAULT 3,"
         "spreaddeviation tinyint(4) DEFAULT 5, PRIMARY KEY (Number))ENGINE = MEMORY, AVG_ROW_LENGTH = 782, CHARACTER SET utf8, COLLATE utf8_general_ci;";

   if(MySqlExecute(DB,Query))
     {
      Print("94Succeeded: ",Query);
     }
   else
     {
      Print("94Error: ",MySqlErrorDescription);
      Print("94Query: ",Query);
     }

   Query="INSERT INTO `optimization_results` (request_datetime,result_datetime,last_summary_profit,ma1_period,ma2_period,K1,vaultdistance,trailingstop,takeprofit,comission,spreaddeviation)"
         " VALUES ((select request_datetime from optimization_request ORDER BY number DESC LIMIT 1),"+"now()"+",0,5,9,25,16,21,0,4,6"+");";
   if(MySqlExecute(DB,Query))
     {
      Print("10Succeeded: ",Query);
     }
   else
     {
      Print("10Error: ",MySqlErrorDescription);
      Print("10Query: ",Query);
     }





  }





//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {



//увеличиваем переменную хранящую количество тиков в свече на единицу
   TicksInCandle++;

//переменная CurrentTickBID - значение цены предложения для текущего тика
  // CurrentTickBID=SymbolInfoDouble(Symbol(),SYMBOL_BID);
//округляем значение до требуемого количества знаков после запятой
   CurrentTickBID=NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_BID),_Digits);
//переменная CurrentTickASK - значение цены спроса для текущего тика
   CurrentTickASK=SymbolInfoDouble(Symbol(),SYMBOL_ASK);
//округляем значение до требуемого количества знаков после запятой
   CurrentTickASK=NormalizeDouble(CurrentTickASK,_Digits);
//переменная для хранения значения спрэда (разница между ценами предоложения и спроса
   Var_SpreadDeviation=(int)SymbolInfoInteger(Symbol(),SYMBOL_SPREAD);
//Print("SpreadDeviation=",SpreadDeviation);

/*
   if(entropy.ContainsKey(CurrentTickBID))
     {
         Print("entropy.ContainsKey(CurrentTickBID) = ",CurrentTickBID);
         
     }
*/

//Print("comission=",comission);
//+------------------------------------------------------------------+
//|Inserting spreaddeviation and comission in TradingVariables table |
//+------------------------------------------------------------------+
//вданном блоке дополнительно используется проверка на предмет того отвалилось ли подключение к базе по таймауту после выходных (два дня простоя), Кроме того в этом случае проводится подключение к базе снова.
   Query="UPDATE tradingvariables SET  comission = "+(string)Var_Comission+" WHERE  number = 1"+";";
   if(MySqlExecute(DB,Query))
     {
      //Print("11Succeeded: ",Query);
     }
   else
     {
      Print("11Error: ",MySqlErrorDescription);
      Print("11Query: ",Query);
      MySqlDisconnect(DB);

      DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
      //+------------------------------------------------------------------+
      //|            Select database for current Symbol                    |
      //+------------------------------------------------------------------+
      Query="USE `"+Symbol()+"`;";
      if(MySqlExecute(DB,Query))
        {
         Print("Succeeded: ",Query);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",Query);
        }
      //Переподключение если связь оборвалась????
      if(DB==-1)
        {
         Print("MySqlErrorDescription: "+MySqlErrorDescription);
         while(DB==-1)
           {
            Print("2Connecting...");
            DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
            Print("MySqlErrorDescription: ",MySqlErrorDescription);
           }
        }
      else
        {
         Print("Reconnected on new tick. DBID#",DB);
        }
     }
//расчет переменной используемой для завершения формирования текущей свечи и начала формирования новой. Если разница (расстояние) между текущими
//HighBuffer[CandleNumber] и LowBuffer[CandleNumber] больше или равна inaquality, то сначинается строится новая свеча, а текущая заверщает отрисовываться.
   Inaquality=NormalizeDouble((_Point*Var_K1),_Digits);

//Print("k1=",k1);
//Print("_Point*k1=",_Point*k1);
// Print("_Point=",_Point);
// Print("inaquality=",inaquality);

//+------------------------------------------------------------------+
//|                         Vault                                    |  //Блок управления рисками. Если профит (в пунктах) по позиции доходит до заданного в переменной VaultDistance,
//|                                                                  |   то половина прибыли закрывается половиной текущего открытого по позиции лота
//+------------------------------------------------------------------+
   if(PositionsTotal()!=0)
     {
      //включено ли использование метода управления рисками Vault
      if(Vault)
        {
         //Print("Vault:CONTROL0");

         //выбираем текущую открытую позицию
         if(posinf.Select(_Symbol))
           {
            //сохраняем номер текущей открытой позиции в перменную, чтобы потом вывести в отладку ее номер, т.к. после закрытия половины лота в позиции ее номер изменится. Применяется только единожды для каждой позиции
            tmpTicket=(int)PositionGetTicket(0);
            //Print("Vault:CONTROL1");
            //если текущая открытая позиция на SELL
            if(posinf.PositionType()==POSITION_TYPE_SELL)
              {
               //Print("Vault:CONTROL2:SELL");
               /*    Print("Vault:CONTROL2:SELL:Flag_Vault=",Flag_Vault);
                              Print("Vault:CONTROL2:SELL:VaultDistance=",VaultDistance);
                              Print("Vault:CONTROL2:SELL:CurrentTickASK=",CurrentTickASK);
                              Print("Vault:CONTROL2:SELL:PreviousIntersectionValue=",PreviousIntersectionValue);
                              Print("Vault:CONTROL2:SELL:SpreadDeviation=",SpreadDeviation);
                              Print("Vault:CONTROL2:SELL:сomission=",comission);
                              Print("Vault:CONTROL2:SELL:((CurrentTickASK-PreviousIntersectionValue)*100000)=",((PreviousIntersectionValue-CurrentTickASK)*100000));
                              Print("Vault:CONTROL2:SELL:(((PreviousIntersectionValue-CurrentTickASK)*100000)+SpreadDeviation+сomission)=",(((PreviousIntersectionValue-CurrentTickASK)*100000)+SpreadDeviation+comission));
                              //_08.08.2018//if((!Flag_Vault) && ((((CurrentTickASK-PreviousIntersectionValue)*100000)-SpreadDeviation-сomission)>VaultDistance))*/
               //Проверяем, если Flag_Vault!=true - значит метод еще не применялся,PreviousIntersectionValue - предыдущее пересечение скользящих, "-SpreadDeviation+comission" - количество пунктов заложенного убытка в каждую позицию
               if((!Flag_Vault) && ((((PreviousIntersectionValue-CurrentTickASK)*100000)-Var_SpreadDeviation+Var_Comission)>Var_VaultDistance))
                 {
                  //Print("Vault:SELL:VAULTSIGNAL");

                  //закрываем половину текущей позиции на SELL, встречной позицией на BUY открытием новой позиции с половиной лота от текущей позиции с одновременной проверкой успешности или неуспешности с возвратом кода ошибки
                  if(!trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,(PositionGetDouble(POSITION_VOLUME))/2,SymbolInfoDouble(_Symbol,SYMBOL_ASK),0,0))
                    {
                     //если не удалось закрыть половину позици
                     Print("Vault:SELL:VAULTSIGNAL: Position/2 close failed:",trade.ResultRetcodeDescription());
                     Print("Vault:SELL:VAULTSIGNAL: Position/2 close failed:PositionTicket=",tmpTicket);
                     Print("Vault:SELL:VAULTSIGNAL: Position/2 close failed:TimeCurrent()=",TimeCurrent());
                     Print("Vault:SELL:VAULTSIGNAL: Position/2 close failed:TimeLocal()=",TimeLocal());
                    }
                  else
                    {
                     //выбираем заново переформированную позицию с новым номером тикета после успешного закрытия половины позиции для дальнейшей работы с ней
                     // posinf.Select(_Symbol);
                     //Print("Vault:SELL:VAULTSIGNAL: Position/2 closed: NEW PositionTicket=",PositionGetTicket(0));
                     /*                Print("Vault:SELL:VAULTSIGNAL: Position/2 Position Closed:TimeCurrent()=",TimeCurrent());
                                          Print("Vault:SELL:VAULTSIGNAL: Position/2 Closed:TimeLocal()=",TimeLocal());
                                          Print("Vault:SELL:VAULTSIGNAL: Position/2 Closed");*/
                    }
                  //пишет в переменную что для текущей открытой позиции применили метод управления рисками и для текущей открытой позиции больше испольщовать его нельзя
                  Flag_Vault=true;
                  //Print("Vault:CONTROL2:SELL:Flag_Vault=true;");
                 }
              }
            //если текущая открытая позиция на BUY
            if(posinf.PositionType()==POSITION_TYPE_BUY)
              {
               //Print("Vault:CONTROL2:BUY");
               /*         Print("Vault:CONTROL2:BUY:Flag_Vault=",Flag_Vault);
                              Print("Vault:CONTROL2:BUY:VaultDistance=",VaultDistance);
                              Print("Vault:CONTROL2:BUY:CurrentTickBID=",CurrentTickBID);
                              Print("Vault:CONTROL2:BUY:PreviousIntersectionValue=",PreviousIntersectionValue);
                              Print("Vault:CONTROL2:BUY:SpreadDeviation=",SpreadDeviation);
                              Print("Vault:CONTROL2:BUY:сomission=",comission);
                              Print("Vault:CONTROL2:BUY:((CurrentTickBID-PreviousIntersectionValue)*100000)=",((CurrentTickBID-PreviousIntersectionValue)*100000));
                              Print("Vault:CONTROL2:BUY:(((CurrentTickBID-PreviousIntersectionValue)*100000)-SpreadDeviation-сomission)=",(((CurrentTickBID-PreviousIntersectionValue)*100000)-SpreadDeviation-comission));
                              //_08.08.2018//if((!Flag_Vault) && ((((CurrentTickBID-PreviousIntersectionValue)*(-1)*100000)-SpreadDeviation-сomission)>VaultDistance))*/
               //Проверяем, если Flag_Vault!=true - значит метод еще не применялся,PreviousIntersectionValue - предыдущее пересечение скользящих, "-SpreadDeviation+comission" - количество пунктов заложенного убытка в каждую позицию
               if((!Flag_Vault) && ((((CurrentTickBID-PreviousIntersectionValue)*100000)-Var_SpreadDeviation+Var_Comission)>Var_VaultDistance))
                 {
                  //Print("Vault:BUY:VAULTSIGNAL");
                  //закрываем половину текущей позиции на BUY, встречной позицией на SELL открытием новой позиции с половиной лота от текущей позиции с одновременной проверкой успешности или неуспешности с возвратом кода ошибки
                  if(!trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,(PositionGetDouble(POSITION_VOLUME))/2,SymbolInfoDouble(_Symbol,SYMBOL_BID),0,0))
                    {
                     //если не удалось закрыть половину позици

                     Print("Vault:BUY:VAULTSIGNAL: Position/2 close failed:",trade.ResultRetcodeDescription());
                     Print("Vault:BUY:VAULTSIGNAL: Position/2 close failed:PositionTicket=",tmpTicket);
                     Print("Vault:BUY:VAULTSIGNAL: Position/2 close failed:TimeCurrent()=",TimeCurrent());
                     Print("Vault:BUY:VAULTSIGNAL: Position/2 close failed:TimeLocal()=",TimeLocal());
                    }
                  else
                    {
                     //выбираем заново переформированную позицию с новым номером тикета после успешного закрытия половины позиции для дальнейшей работы с ней

                     // posinf.Select(_Symbol);
                     /*  Print("Vault:SELL:VAULTSIGNAL: Position/2 closed: NEW PositionTicket=",PositionGetTicket(0));
                                          Print("Vault:SELL:VAULTSIGNAL: Position/2 closed:TimeCurrent()=",TimeCurrent());
                                          Print("Vault:SELL:VAULTSIGNAL: Position/2 closed:TimeLocal()=",TimeLocal());
                                          Print("Vault:SELL:VAULTSIGNAL: Position/2 closed");*/
                    }
                  //пишет в переменную что для текущей открытой позиции применили метод управления рисками и для текущей открытой позиции больше испольщовать его нельзя
                  Flag_Vault=true;
                  //Print("Vault:CONTROL2:BUY:Flag_Vault=true;");
                 }
              }
           }
        }

      //+------------------------------------------------------------------+
      //|                         CurrentTrailingStop                      |
      //+------------------------------------------------------------------+
      //если StoplossOnOff==true значит используем метод подтягивания стоплосса на указанное в пунктах в переменной CurrentTrailingStop расстояние.
      //Если цена касается текущего установленного в позиции уровня TrailingStop то позиция автоматически закрывается


      if(StoplossOnOff==true)
        {
         //Print("StoplossOnOff==true:CONTROL0");
         //Print("StoplossOnOff==true:CONTROL0:InpTrailingStop=",InpTrailingStop);
         //Print("StoplossOnOff==true:CONTROL0:SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL)=",SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL));
         //проверяем что входное значение InpTrailingStop не меньше значения разрешенного брокером в переменной терминала SYMBOL_TRADE_STOPS_LEVEL, иначе делаем значение CurrentTrailingStop равным SYMBOL_TRADE_STOPS_LEVEL
         if(Var_TrailingStop<=SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL))
           {
            //делаем значение CurrentTrailingStop равным SYMBOL_TRADE_STOPS_LEVEL
            CurrentTrailingStop=SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL)*Point();
           }
         else
           {
            //если InpTrailingStop то используемый уровень CurrentTrailingStop переводим в значение в цене а не пунктах (умножаем, к примеру, на Point() равный, для EURUSD, 0,00001, для каждой валютной пары свой размер Point()
            CurrentTrailingStop=Var_TrailingStop*Point();
           }

         if(Var_TrailingStop>0)
           {
            //если текущая позиция на SELL
            if(posinf.PositionType()==POSITION_TYPE_SELL)
              {
               //Если стоплосс по позиции равен нулю, то есть выставляется первый раз за время работы робота, то устанавливаем стоплосс позиции первый раз,
               //а все остальные разы будем просто сдвигать вслед за ценой вверх или вниз
               if(PositionGetDouble(POSITION_SL)==0)
                 {
                  /*Print("StoplossOnOff==true:POSITION_TYPE_SELL:CurrentTrailingStop=",CurrentTrailingStop);
                                    Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)=",SymbolInfoDouble(Symbol(),SYMBOL_ASK));
                                    Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop);*/
                  //собственно выполняем вызов функции непосредственно устанавливающей уроень стоплосса на расчетный с одновременной проверкой результата выполнения и выводом ошикби в лог по необходимости
                  if(!trade.PositionModify(_Symbol,SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop,0))
                    {
                     /*
                                          Print("TS:1:",trade.ResultRetcodeDescription());
                                          Print("StoplossOnOff==true:POSITION_TYPE_SELL:CurrentTrailingStop=",CurrentTrailingStop);
                                          Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)=",SymbolInfoDouble(Symbol(),SYMBOL_ASK));
                                          Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop);
                                        */
                    }
                  else
                    {
                     //Print("TS:1:StoplossOnOff==true:POSITION_TYPE_SELL:Succeed");
                    }
                 }
               //проверяем на условие, требуется ли подтягивать стоплосс. Если цена открытия позиции минус текущая цена спроса больше расстояния CurrentTrailingStop, значит подтягиваем вслед за движением цены
               //1   if(NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN)-SymbolInfoDouble(Symbol(),SYMBOL_ASK),_Digits)>CurrentTrailingStop)
               //1 {
               /* Print("StoplossOnOff==true:POSITION_TYPE_SELL:CurrentTrailingStop=",CurrentTrailingStop);
                                 Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)=",SymbolInfoDouble(Symbol(),SYMBOL_ASK));
                                 Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop);*/

               //проверяем на условие, требуется ли подтягивать стоплосс. Если текущее значение (расстояние в пунктах) стоплосса больше чем сумма цены спроса плюс расстояние (CurrentTrailingStop)
               // для стоплосса значит подтягиваем стоплосс вслед за движением цены
               if(PositionGetDouble(POSITION_SL)>SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop)
                 {
                  /*Print("StoplossOnOff==true:POSITION_TYPE_SELL:CurrentTrailingStop=",CurrentTrailingStop);
                                    Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)=",SymbolInfoDouble(Symbol(),SYMBOL_ASK));
                                    Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop);*/
                  //собственно выполняем вызов функции непосредственно устанавливающей уроень стоплосса на расчетный с одновременной проверкой результата выполнения и выводом ошикби в лог по необходимости
                  if(!trade.PositionModify(_Symbol,SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop,0))
                    {
                     /*
                                          Print("TS:2:",trade.ResultRetcodeDescription());
                                          Print("StoplossOnOff==true:POSITION_TYPE_SELL:CurrentTrailingStop=",CurrentTrailingStop);
                                          Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)=",SymbolInfoDouble(Symbol(),SYMBOL_ASK));
                                          Print("StoplossOnOff==true:POSITION_TYPE_SELL:SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_ASK)+CurrentTrailingStop);
                                         */
                    }
                  else
                    {
                     //Print("TS:2:StoplossOnOff==true:POSITION_TYPE_SELL:Succeed");
                    }
                 }
               //1 }
              }
            //если текущая позиция на BUY
            if(posinf.PositionType()==POSITION_TYPE_BUY)
              {
               //Если стоплосс по позиции равен нулю, то есть выставляется первый раз за время работы робота, то устанавливаем стоплосс позиции первый раз,
               //а все остальные разы будем просто сдвигать вслед за ценой вверх или вниз
               if(PositionGetDouble(POSITION_SL)==0)
                 {
                  /* Print("StoplossOnOff==true:POSITION_TYPE_BUY:CurrentTrailingStop=",CurrentTrailingStop);
                                    Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)=",SymbolInfoDouble(Symbol(),SYMBOL_BID));
                                    Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop);*/
                  //собственно выполняем вызов функции непосредственно устанавливающей уроень стоплосса на расчетный с одновременной проверкой результата выполнения и выводом ошикби в лог по необходимости
                  if(!trade.PositionModify(_Symbol,SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop,0))
                    {
                     /*
                                          Print("TS:3:",trade.ResultRetcodeDescription());
                                          Print("StoplossOnOff==true:POSITION_TYPE_BUY:CurrentTrailingStop=",CurrentTrailingStop);
                                          Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)=",SymbolInfoDouble(Symbol(),SYMBOL_BID));
                                          Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop);
                                          */
                    }
                  else
                    {
                     //Print("TS:3:StoplossOnOff==true:POSITION_TYPE_BUY:Succeed");
                    }
                 }
               //проверяем на условие, требуется ли подтягивать стоплосс. Если цена открытия позиции минус текущая цена предложения больше расстояния CurrentTrailingStop, значит подтягиваем вслед за движением цены
               //2 if(NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_BID)-PositionGetDouble(POSITION_PRICE_OPEN),_Digits)>CurrentTrailingStop)
               //2  {
               /* Print("StoplossOnOff==true:POSITION_TYPE_BUY:CurrentTrailingStop=",CurrentTrailingStop);
                                 Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)=",SymbolInfoDouble(Symbol(),SYMBOL_BID));
                                 Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop);*/
               //проверяем на условие, требуется ли подтягивать стоплосс. Если текущее значение (расстояние в пунктах) стоплосса больше чем сумма цены предложения минус расстояние (CurrentTrailingStop)
               // для стоплосса значит подтягиваем стоплосс вслед за движением цены
               if(PositionGetDouble(POSITION_SL)<SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop || posinf.StopLoss()==0)
                 {
                  /*Print("StoplossOnOff==true:POSITION_TYPE_BUY:CurrentTrailingStop=",CurrentTrailingStop);
                                       Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)=",SymbolInfoDouble(Symbol(),SYMBOL_BID));
                                       Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop);*/
                  //собственно выполняем вызов функции непосредственно устанавливающей уроень стоплосса на расчетный с одновременной проверкой результата выполнения и выводом ошикби в лог по необходимости
                  if(!trade.PositionModify(_Symbol,SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop,0))
                    {

                     /* Print("TS:4:",trade.ResultRetcodeDescription());
                                          Print("StoplossOnOff==true:POSITION_TYPE_BUY:CurrentTrailingStop=",CurrentTrailingStop);
                                          Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)=",SymbolInfoDouble(Symbol(),SYMBOL_BID));
                                          Print("StoplossOnOff==true:POSITION_TYPE_BUY:SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop=",SymbolInfoDouble(Symbol(),SYMBOL_BID)-CurrentTrailingStop);
                     */
                    }
                  else
                    {
                     //Print("TS:4:StoplossOnOff==true:POSITION_TYPE_BUY:Succeed");
                    }
                 }
               //2 }
              }
           }
        }
     }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//если робота только запустили в работу
   if(firstStart==0)
     {
      Print("Symbol()=",Symbol());

      //0      Print("KILL:OrdersTotal()= ",OrdersTotal());
      // for(int x=0;x<=OrdersTotal()-1;x++)
      //+------------------------------------------------------------------+
      //|                                                                  |
      //+------------------------------------------------------------------+
      //закрываем любые открытые позиции если таковые имеются
      if(posinf.Select(_Symbol))
        {
         //0          Print("KILL!!!111");
         if(!trade.PositionClose(_Symbol,40)) ///ЕСЛИ BUY
           {
            Print(trade.ResultRetcodeDescription());
            //continue;
           }
         else
           {
            //              Print("KILL!!!++++");
           }

        }

      //рассчитываем оптимальный Inaquality как среднестатистический размер свечи (разница между среднестатистическими High и Low за N-количество предыдущих свеч) ///TODO??? ВЫНЕСТИ РАСЧЕТ в БЛОК КОДА ПОСЛЕ ФОРМИРОВАНИЯ НОВОЙ СВЕЧИ???

      if(InpK1 ==0)
        {
         double avHigh = 0;
         double avLow = 0;

         for(int i = 0; i< CandelesPeriodCalculation; i++)
           {
            avHigh += iHigh(NULL, PERIOD_CURRENT, i);
           }
         //Print("avHigh = ", avHigh);

         for(int i = 0; i< CandelesPeriodCalculation; i++)
           {
            avLow += iLow(NULL, PERIOD_CURRENT, i);
           }
         // Print("avLow = ", avLow);

         Var_K1 = NormalizeDouble((avHigh - avLow)/CandelesPeriodCalculation, _Digits)/_Point*KK_InpK1;
         Print("Start:Calculated Var_K1 _Inaquality_ = ", Var_K1);

        }

      //пишем в таблицу самый первый пришедший тик
      //+------------------------------------------------------------------+
      //|  Inserting first tick in Table of Symbol Ticks statistics        |
      //+------------------------------------------------------------------+
      Query="INSERT INTO `ticks` (DATETIME,BID,ASK,SPREAD,PAUSE,CANDLENUMBER,COMISSION) VALUES ("+"now()"+", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_BID)+", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_ASK)+", "+(string)SymbolInfoInteger(Symbol(),SYMBOL_SPREAD)+", "+"0"+", "+(string)CandleNumber+", "+(string)Var_Comission+")";
      //получаем количество миллисекунд прошедших с момента старта системы
      startMicSec=GetTickCount();
      if(MySqlExecute(DB,Query))
        {
         //   Print("Succeeded: ",Query);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",Query);
        }
      //инициализируем индикаторные буферы
      ArrayInitialize(OpenBuffer,0);
      ArrayInitialize(HighBuffer,0);
      ArrayInitialize(LowBuffer,0);
      ArrayInitialize(CloseBuffer,0);
      //задлаем размер массивов индикаторных буферов
      ArrayResize(OpenBuffer,5000000);
      ArrayResize(HighBuffer,5000000);
      ArrayResize(LowBuffer,5000000);
      ArrayResize(CloseBuffer,5000000);

      ArrayResize(MALineBuffer1,5000000);
      ArrayResize(MALineBuffer2,5000000);
      ArrayResize(MaInaquality,5000000);

      //разница между скользящими средними, с помощью нее определяем пересечение скользящих а следовательно и сигналы к продаже/покупке
      MaInaquality[0]=0;
      //нумерация в масиве MaInaquality
      MaInaqualityNumber=1;

      // текущая котировка будет являться ценой открытия свечи
      OpenBuffer[CandleNumber]=CurrentTickBID;
      // текущая котировка будет являться максимальной ценой свечи
      HighBuffer[CandleNumber]=CurrentTickBID;
      // текущая котировка будет являться минимальной ценой свечи
      LowBuffer[CandleNumber]=CurrentTickBID;
      // текущая котировка пока является ценой закрытия текущей свечи
      CloseBuffer[CandleNumber]=CurrentTickBID;
      // инкрементим firstStart для того чтобы он повторно не вызвался
      firstStart++;
     } // !if(firstStart==0)
//если очередной пришедший тик не является первым
   else
     {

      // текущая котировка пока является ценой закрытия текущей свечи
      CloseBuffer[CandleNumber]=CurrentTickBID;
      // если текущая котировка больше максимальной цены текущей свечи, то это будет новое значение максимальной цены свечи
      if(CurrentTickBID>HighBuffer[CandleNumber])
         //Print("Control: 00: if(CurrentTickBID>HighBuffer[CandleNumber]);HighBuffer[CandleNumber]=CurrentTickBID;");
         HighBuffer[CandleNumber]=CurrentTickBID;
      // если текущая котировка меньше минимальной цены текущей свечи, то это будет новое значение минимальной цены свечи
      if(CurrentTickBID<LowBuffer[CandleNumber])
         // Print("Control: 11:   if(CurrentTickBID<LowBuffer[CandleNumber]);LowBuffer[CandleNumber]=CurrentTickBID");
         LowBuffer[CandleNumber]=CurrentTickBID;

      // ObjectsDeleteAll();

      //+------------------------------------------------------------------+
      //|  Inserting newly tick in Table of Symbol Ticks statistics        |
      //+------------------------------------------------------------------+
      Query="INSERT INTO `ticks` (DATETIME,BID,ASK,SPREAD,PAUSE,CANDLENUMBER,COMISSION) VALUES ("+"now()"+", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_BID)+", "+(string)SymbolInfoDouble(Symbol(),SYMBOL_ASK)+", "+(string)SymbolInfoInteger(Symbol(),SYMBOL_SPREAD)+", "+(string)(GetTickCount()-startMicSec)+", "+(string)CandleNumber+", "+(string)Var_Comission+")";
      startMicSec=GetTickCount();
      if(MySqlExecute(DB,Query))
        {
         // Print("Succeeded: ",Query);
        }
      else
        {
         Print("Error: ",MySqlErrorDescription);
         Print("Query: ",Query);
        }

      //проверка на условие того что поступил сигнал о завершении формирования текущей свечи и начала формирования новой
      // if(((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=Inaquality && CandleNumber==0) || (CandleNumber > 0 && (HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=Inaquality && (HighBuffer[CandleNumber] != HighBuffer[CandleNumber-1]) && (LowBuffer[CandleNumber] != LowBuffer[CandleNumber-1])) || (CandleNumber > 0 && (HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=Inaquality && (HighBuffer[CandleNumber] != HighBuffer[CandleNumber-1]))  || (CandleNumber > 0 && (HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=Inaquality && (LowBuffer[CandleNumber] != LowBuffer[CandleNumber-1])))

      if((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=Inaquality)
        {
         //Print("0onTick() : if((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])>=Inaquality)");
         if(CandleNumber > 0)
           {
            Comment(StringFormat("CurrentTickBID=%G\nCandleNumber=%G\nVar_K1=%G\nVar_MAPeriod1=%G\nVar_MAPeriod2=%G\nVar_TrailingStop=%G\nVar_TakeProfit=%G\nVar_VaultDistance=%G\ncommpressedBars=%G\ncommpressedIdenticalBars=%G\nInaquality=%G\nHighBuffer[CandleNumber]-LowBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber-1]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber-1]=%G\nLowBuffer[CandleNumber]=%G",CurrentTickBID, CandleNumber,Var_K1,Var_MAPeriod1,Var_MAPeriod2,Var_TrailingStop,Var_TakeProfit,Var_VaultDistance,commpressedBars, commpressedIdenticalBars, Inaquality,HighBuffer[CandleNumber]-LowBuffer[CandleNumber],HighBuffer[CandleNumber-1],HighBuffer[CandleNumber],LowBuffer[CandleNumber-1],LowBuffer[CandleNumber]));

            //Сжимаем статически при одинаковых high или low, не по процентам
            if(InpBarsOverlappingPercentageFlag)
              {

               /*Print("Tick Compression: InpBarsOverlappingPercentageFlag:true ");
               Print("Tick Compression: NormalizeDouble(HighBuffer[CandleNumber] - HighBuffer[CandleNumber-1], _Digits) = ", NormalizeDouble(HighBuffer[CandleNumber] - HighBuffer[CandleNumber-1], _Digits));
               Print("Tick Compression: NormalizeDouble(LowBuffer[CandleNumber-1] - LowBuffer[CandleNumber], _Digits) = ", NormalizeDouble(LowBuffer[CandleNumber-1] - LowBuffer[CandleNumber], _Digits));
               Print("Tick Compression: NormalizeDouble(InpBarsOverlappingPercentage*Inaquality, _Digits) = ", NormalizeDouble(InpBarsOverlappingPercentage*Inaquality, _Digits));
               Print("Tick Compression: InpBarsOverlappingPercentage = ", InpBarsOverlappingPercentage);
               Print("Tick Compression: Inaquality = ", Inaquality);
               Print("Tick Compression: commpressedBars = ", commpressedBars);
               */
               if(NormalizeDouble(HighBuffer[CandleNumber] - HighBuffer[CandleNumber-1], _Digits) > NormalizeDouble(InpBarsOverlappingPercentage*Inaquality, _Digits) || NormalizeDouble(LowBuffer[CandleNumber-1] - LowBuffer[CandleNumber], _Digits)  > NormalizeDouble(InpBarsOverlappingPercentage*Inaquality, _Digits))
                 {
                  Comment(StringFormat("CurrentTickBID=%G\nCandleNumber=%G\nVar_K1=%G\nVar_MAPeriod1=%G\nVar_MAPeriod2=%G\nVar_TrailingStop=%G\nVar_TakeProfit=%G\nVar_VaultDistance=%G\ncommpressedBars=%G\ncommpressedIdenticalBars=%G\nInaquality=%G\nHighBuffer[CandleNumber]-LowBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber-1]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber-1]=%G\nLowBuffer[CandleNumber]=%G",CurrentTickBID, CandleNumber,Var_K1,Var_MAPeriod1,Var_MAPeriod2,Var_TrailingStop,Var_TakeProfit,Var_VaultDistance,commpressedBars, commpressedIdenticalBars, Inaquality,HighBuffer[CandleNumber]-LowBuffer[CandleNumber],HighBuffer[CandleNumber-1],HighBuffer[CandleNumber],LowBuffer[CandleNumber-1],LowBuffer[CandleNumber]));
                  //Print("Tick Compression: return:COMPRESSED CANDLE:true");


                  //Print("Tick Compression: return:1__ ___ _____ ____ ____ ___ __ ___");
                  //сжимаем два последних бара если координаты их максимума и минимума перекрываются почти полньстю при непривышении процента InpBarsOverlappingPercentage
                 }
               else
                 {
                  return;
                 }
              }

            if(!InpBarsOverlappingPercentageFlag)
              {

               if(NormalizeDouble(HighBuffer[CandleNumber] - HighBuffer[CandleNumber-1], _Digits) > NormalizeDouble(Inaquality, _Digits) || NormalizeDouble(LowBuffer[CandleNumber-1] - LowBuffer[CandleNumber], _Digits)  > NormalizeDouble(Inaquality, _Digits))
                 {
                  Comment(StringFormat("CurrentTickBID=%G\nCandleNumber=%G\nVar_K1=%G\nVar_MAPeriod1=%G\nVar_MAPeriod2=%G\nVar_TrailingStop=%G\nVar_TakeProfit=%G\nVar_VaultDistance=%G\ncommpressedBars=%G\ncommpressedIdenticalBars=%G\nInaquality=%G\nHighBuffer[CandleNumber]-LowBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber-1]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber-1]=%G\nLowBuffer[CandleNumber]=%G",CurrentTickBID, CandleNumber,Var_K1,Var_MAPeriod1,Var_MAPeriod2,Var_TrailingStop,Var_TakeProfit,Var_VaultDistance,commpressedBars, commpressedIdenticalBars, Inaquality,HighBuffer[CandleNumber]-LowBuffer[CandleNumber],HighBuffer[CandleNumber-1],HighBuffer[CandleNumber],LowBuffer[CandleNumber-1],LowBuffer[CandleNumber]));
                  //Print("Tick Compression: return:COMPRESSED CANDLE2:true");
                  //сжимаем два последних бара если координаты их максимума и минимума перекрываются почти полньстю при непривышении процента InpBarsOverlappingPercentage

                 }
               else
                 {
                  return;
                 }
              }
           }

         //Print("Control:AFTER return");

         CloseBuffer[CandleNumber] = CurrentTickBID;
         //вычисляем значения скользящих средних по формуле/типу заданному в настройках
         switch(InpMAMethod1)
           {
            case MODE_SMA:
               CalculateSMA1();
               break;
            case MODE_LWMA:
               CalculateLWMA1();
               break;
            case MODE_EMA:
               CalculateEMA1();
               break;
            case MODE_SMMA:
               CalculateSmMA1();
               break;
           }
         switch(InpMAMethod2)
           {
            case MODE_SMA:
               CalculateSMA2();
               break;
            case MODE_LWMA:
               CalculateLWMA2();
               break;
            case MODE_EMA:
               CalculateEMA2();
               break;
            case MODE_SMMA:
               CalculateSmMA2();
               break;
           }
         //вычисляем очередную новую разницу между скользящимим средними с округлением о нужного количества чисел после запятой
         MaInaquality[MaInaqualityNumber]=NormalizeDouble((MA2-MA1),_Digits);

         //Print("MA1=",MA1);
         //Print("MA2=",MA2);
         //Print("(MA2-MA1)=",(MA2-MA1));
         //Print("NormalizeDouble((MA2-MA1),_Digits)=",NormalizeDouble((MA2-MA1),_Digits));
         //Print("MaInaqualityNumber=",MaInaqualityNumber);
         //Print("MaInaquality[MaInaqualityNumber]=",MaInaquality[MaInaqualityNumber]);

         //обработка исключительного случая когда значения скользящих одинаковы, что не позволит определить пересечение
         if((CandleNumber)>InpMAPeriod2)
           {
            if(MaInaquality[MaInaqualityNumber]==0)
              {
               if(MaInaquality[MaInaqualityNumber-1]>0)
                 {
                  MaInaquality[MaInaqualityNumber]=1;
                 }
               else
                  if(MaInaquality[MaInaqualityNumber-1]<0)
                    {
                     MaInaquality[MaInaqualityNumber]=-1;
                    }
              }
            //вызываем функцию работы с позициями
            CheckPositions();
           }

         //расчет данных требуемых для сбора статистики характеристик свечей/
         if(OpenBuffer[CandleNumber]>CloseBuffer[CandleNumber])
           {
            OC=NormalizeDouble((OpenBuffer[CandleNumber]-CloseBuffer[CandleNumber])*100000,_Digits);
           }

         else
            if(CloseBuffer[CandleNumber]>OpenBuffer[CandleNumber])
              {
               OC=NormalizeDouble((CloseBuffer[CandleNumber]-OpenBuffer[CandleNumber])*100000,_Digits);
              }

            else
               if(OpenBuffer[CandleNumber]==CloseBuffer[CandleNumber])
                 {
                  OC=NormalizeDouble((OpenBuffer[CandleNumber]-CloseBuffer[CandleNumber])*100000,_Digits);
                 }

         HL=NormalizeDouble((HighBuffer[CandleNumber]-LowBuffer[CandleNumber])*100000,_Digits);

         //Пишем в MySQL данные сформировавшейся свечи
         Query="INSERT INTO `candles` (DATETIME,O,H,L,C,CandleNumber,MAINAQUALITY,SPREAD,OC,HL,TICKSINCANDLE) VALUES ("+"now()"+", "+(string)OpenBuffer[CandleNumber]+", "+(string)HighBuffer[CandleNumber]+", "+(string)LowBuffer[CandleNumber]+", "+(string)CloseBuffer[CandleNumber]+", "+(string)CandleNumber+", "+(string)MaInaquality[MaInaqualityNumber-1]+", "+(string)Var_SpreadDeviation+", "+(string)OC+", "+(string)HL+", "+(string)TicksInCandle+")";
         if(MySqlExecute(DB,Query))
           {
            //Print("Succeeded: ",Query);
           }
         else
           {
            Print("Error: ",MySqlErrorDescription);
            Print("Query: ",Query);
           }
         //инкрементим счетчик сформированных свечей на единицу
         CandleNumber++;
         // текущая котировка будет являться ценой открытия свечи
         OpenBuffer[CandleNumber]=CurrentTickBID;
         // текущая котировка будет являться максимальной ценой свечи
         HighBuffer[CandleNumber]=CurrentTickBID;
         // текущая котировка будет являться минимальной ценой свечи
         LowBuffer[CandleNumber]=CurrentTickBID;
         // текущая котировка пока является ценой закрытия текущей свечи
         CloseBuffer[CandleNumber]=CurrentTickBID;
         //обнуляем счетчик количества тиков в свече.
         TicksInCandle=0;
         //инкрементим индекс для массива  MaInaquality
         MaInaqualityNumber++;
         //выводим одновленные данных в верхний левый угол терминала
         Comment(StringFormat("CurrentTickBID=%G\nCandleNumber=%G\nVar_K1=%G\nVar_MAPeriod1=%G\nVar_MAPeriod2=%G\nVar_TrailingStop=%G\nVar_TakeProfit=%G\nVar_VaultDistance=%G\ncommpressedBars=%G\ncommpressedIdenticalBars=%G\nInaquality=%G\nHighBuffer[CandleNumber]-LowBuffer[CandleNumber]=%G\nHighBuffer[CandleNumber-1]=%G\nHighBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber-1]=%G\nLowBuffer[CandleNumber]=%G",CurrentTickBID, CandleNumber,Var_K1,Var_MAPeriod1,Var_MAPeriod2,Var_TrailingStop,Var_TakeProfit,Var_VaultDistance,commpressedBars, commpressedIdenticalBars, Inaquality,HighBuffer[CandleNumber]-LowBuffer[CandleNumber],HighBuffer[CandleNumber-1],HighBuffer[CandleNumber],LowBuffer[CandleNumber-1],LowBuffer[CandleNumber]));

         //рассчитываем оптимальный Inaquality как среднестатистический размер свечи (разница между среднестатистическими High и Low за N-количество предыдущих свеч) ///TODO??? ВЫНЕСТИ РАСЧЕТ в БЛОК КОДА ПОСЛЕ ФОРМИРОВАНИЯ НОВОЙ СВЕЧИ???

         if(InpK1 == 0)
           {
            double avHigh = 0;
            double avLow = 0;

            for(int i = 0; i< CandelesPeriodCalculation; i++)
              {
               avHigh += iHigh(NULL, PERIOD_CURRENT, i);
              }
            //Print("avHigh = ", avHigh);

            for(int i = 0; i< CandelesPeriodCalculation; i++)
              {
               avLow += iLow(NULL, PERIOD_CURRENT, i);
              }
            // Print("avLow = ", avLow);

            Var_K1 = NormalizeDouble((avHigh - avLow)/CandelesPeriodCalculation, _Digits)/_Point*KK_InpK1;
            Print("END:Calculated Var_K1 _Inaquality_ = ", Var_K1);
            Var_TrailingStop = Var_K1;
            Print("END:Var_TrailingStop = ", Var_TrailingStop);
           }

         //=Vault DEBUG
         Print("Vault:CONTROL2:SELL:Flag_Vault=",Flag_Vault);
         Print("Vault:CONTROL2:SELL:VaultDistance=",Var_VaultDistance);
         Print("Vault:CONTROL2:SELL:CurrentTickASK=",CurrentTickASK);
         Print("Vault:CONTROL2:SELL:PreviousIntersectionValue=",PreviousIntersectionValue);
         Print("Vault:CONTROL2:SELL:SpreadDeviation=",Var_SpreadDeviation);
         Print("Vault:CONTROL2:SELL:Var_Comission=",Var_Comission);
         Print("Vault:CONTROL2:SELL:(CurrentTickASK-PreviousIntersectionValue)=",(PreviousIntersectionValue-CurrentTickASK));
         Print("Vault:CONTROL2:SELL:((CurrentTickASK-PreviousIntersectionValue)*100000)=",((PreviousIntersectionValue-CurrentTickASK)*100000));
         Print("Vault:CONTROL2:SELL:(((PreviousIntersectionValue-CurrentTickASK)*100000)+SpreadDeviation+сomission)=",(((PreviousIntersectionValue-CurrentTickASK)*100000)+Var_SpreadDeviation+Var_Comission));

         /*
         Query="SELECT Inaquality,LWMA1,LWMA2,TP,TrStop,VltDist,Profit FROM ask_bid_result ORDER BY Profit DESC LIMIT 1;";

         //Print("SQL>",Query);
         Cursor=MySqlCursorOpen(DB,Query);
         if(Cursor>=0)
         {
         Rows=MySqlCursorRows(Cursor);
         Print("SELECT optimization_needed:",Rows,"row(s) selected");
         for(l=0; l<Rows;l++)
         if(MySqlCursorFetchRow(Cursor))
         {
          Var_K1=MySqlGetFieldAsInt(Cursor,0);
          Print("Var_K1=",Var_K1);
          Var_MAPeriod1=MySqlGetFieldAsInt(Cursor,0);
          Print("Var_MAPeriod1=",Var_MAPeriod1);
          Var_MAPeriod2=MySqlGetFieldAsInt(Cursor,1);
          Print("Var_MAPeriod2=",Var_MAPeriod2);
          Var_TakeProfit=MySqlGetFieldAsInt(Cursor,2);
          Print("Var_TakeProfit=",Var_TakeProfit);
          Var_TrailingStop=MySqlGetFieldAsInt(Cursor,3);
          Print("Var_TrailingStop=",Var_TrailingStop);
          Var_VaultDistance=MySqlGetFieldAsInt(Cursor,4);
          Print("Var_VaultDistance=",Var_VaultDistance);
          Var_Profit=MySqlGetFieldAsInt(Cursor,5);
          Print("Var_Profit=",Var_Profit);
         }
         MySqlCursorClose(Cursor);
         }
         else
         {
         Print("Cursor openning failed. Error: ",MySqlErrorDescription);
         }
         */
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//отключаемся от базы
   MySqlDisconnect(DB);
   Print("Disconnected. done!");
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
