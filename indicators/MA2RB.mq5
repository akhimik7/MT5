//+------------------------------------------------------------------+
//     PS
//
//+------------------------------------------------------------------+
#property copyright "алхимик"
#property description "Индикатор строит 'тиковые свечи' фиксированной разницы между High и Low"
#property version   "1.00"
//индикатор выводится в отдельное окно
#property indicator_separate_window
// используется одно графическое построение - цветные свечи
#property indicator_plots 1
// для свечей индикатора необходимо 4 буфера для цен OHLC и один - для индекса цвета
#property indicator_buffers 1
//задание типа графического построения - цветные свечи
//#property indicator_type1 DRAW_COLOR_CANDLES
#property indicator_type1 DRAW_LINE
//#property indicator_type3 DRAW_LINE

#property indicator_color1  Gray

//input ENUM_MA_METHOD InpMAMethod2=MODE_LWMA;  // Method

//--- indicator buffers
double               MA2LineBuffer2[];

//+---------------------------------------

//Хранит номер текущей свечи
int CandleNumber=0;
// переменная ticks_stored - хранит количество накопленных и сохраненных тиков и соответственно
// порядковый номер  индексов для массива TicksBuffer[]
int ticks_stored=0;
//массивы OpenBuffer[], HighBuffer[], LowBuffer[] и CloseBuffer[]
//используются для хранения цен OHLC отображаемых свечей, массив
double OpenBuffer[],HighBuffer[],LowBuffer[],CloseBuffer[],ColorIndexBuffer[];
int OHLCNumber=0;
bool firstStart=true;

//---
#include <MQLMySQL.mqh>
string Host,User,Password,Database,Socket; // database credentials
int Port,ClientFlag;
int DB; // database identifier

int number=0;

int MA2Number=0;
//int MA2Number=0;
//+------------------------------------------------------------------+
//функция OnInit()
//+------------------------------------------------------------------+
void OnInit()
  {

//--- indicator buffers mapping
   SetIndexBuffer(0,MA2LineBuffer2,INDICATOR_DATA);

//индексация в массиве MA1LineBuffer1 будет производиться как в таймсериях
   ArraySetAsSeries(MA2LineBuffer2,false);

//нулевые значения в графическом построении 2 (цены Low) не отрисовываются
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0);

//---- sets drawing line empty value--
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0.0);
//---- sets drawing line empty value--

   Print(MySqlVersion());

// reading database credentials from INI file
   Host = "127.0.0.1";
   User = "root";
   Password = "Qw123456";
   Database = Symbol();
   Port     = 3306;
   Socket   = "0";
   ClientFlag=0; //(int)StringToInteger(ReadIni(INI, "MYSQL", "ClientFlag"));

   Print("Host: ",Host,", User: ",User,", Database: ",Database);

// open database connection
   Print("Connecting...");

   DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);

    //Переподключение если связь оборвалась????
      if(DB==-1)
        {
         Print("1: failed! Error: "+MySqlErrorDescription);
         while(DB==-1)
           {
            Print("2Connecting...");
            DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
           }
        }
      else
        {
         //Print("Reconnected on new tick. DBID#",DB);
        }
  }
//+------------------------------------------------------------------+
// функция OnCalculate()
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {

   if(firstStart)
     {

      //инициализируем массивы нулями
      ArrayInitialize(MA2LineBuffer2,0);
      firstStart=false;
     }

// string Query;
   int    i,Rows;

   string MA2Query;
   int MA2Cursor;
   MA2Query="SELECT NUMBER, MAPERIOD2, MA2VALUE, CANDLENUMBER FROM `ma2_data` where NUMBER>"+(string)MA2Number;

   MA2Cursor=MySqlCursorOpen(DB,MA2Query);

  //Переподключение если связь оборвалась????
      if(DB==-1)
        {
         Print("MySqlErrorDescription: "+MySqlErrorDescription);
         while(DB==-1)
           {
            Print("2Connecting...");
            DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
           }
        }
      else
        {
         //Print("Reconnected on new tick. DBID#",DB);
        }
        
   if(MA2Cursor>=0)
     {
      Rows=MySqlCursorRows(MA2Cursor);
      for(i=0; i<Rows; i++)
         if(MySqlCursorFetchRow(MA2Cursor))
           {

            int ma2_number,ma2_period,ma2_candlenumber;
            double ma2_value;

            ma2_number=MySqlGetFieldAsInt(MA2Cursor,0);
            MA2Number=ma2_number;
            ma2_period=MySqlGetFieldAsInt(MA2Cursor,1);
            ma2_value=MySqlGetFieldAsDouble(MA2Cursor,2);
            ma2_value=NormalizeDouble(ma2_value,_Digits);
            ma2_candlenumber=MySqlGetFieldAsInt(MA2Cursor,3);

            //пишем в индикаторный буфер значение первой скользящей средней
            MA2LineBuffer2[ma2_candlenumber]=ma2_value;

            //  Comment(StringFormat("OHLCNumber=%G\nOpenBuffer[CandleNumber]=%G\nHughBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\nCandleNumber=%G\nMA1Number=%G\nMA1LineBuffer1[CandleNumber]=%G",OHLCNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],CandleNumber,MA1Number,MA1LineBuffer1[CandleNumber]));
            // смещение положения индикатора для выравнивания с графиком цены
            PlotIndexSetInteger(0,PLOT_SHIFT,rates_total-ma2_candlenumber-1);
           }
      MySqlCursorClose(MA2Cursor); // NEVER FORGET TO CLOSE CURSOR !!!
     }
   else
     {
      Print("Cursor opening failed. Error: ",MySqlErrorDescription);
     }

//возврат из функции OnCalculate()
   return(rates_total);

   MySqlDisconnect(DB);
   Print("Disconnected. done!");
  }
//+------------------------------------------------------------------+
