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

#property indicator_color1  Green

//input ENUM_MA_METHOD InpMAMethod2=MODE_LWMA;  // Method

//--- indicator buffers
double               MA1LineBuffer1[];

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

int MA1Number=0;
//+------------------------------------------------------------------+
//функция OnInit()
//+------------------------------------------------------------------+
void OnInit()
  {

//--- indicator buffers mapping
   SetIndexBuffer(0,MA1LineBuffer1,INDICATOR_DATA);

//индексация в массиве MA1LineBuffer1 будет производиться как в таймсериях
   ArraySetAsSeries(MA1LineBuffer1,false);

//нулевые значения в графическом построении 2 (цены Low) не отрисовываются
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0);

//---- sets drawing line empty value--
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0.0);

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
         Print("Reconnected on new tick. DBID#",DB);
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

      ArrayInitialize(MA1LineBuffer1,0);

      firstStart=false;
     }

// string Query;
   int    i,Rows;

   string MA1Query;
   int MA1Cursor;
   MA1Query="SELECT NUMBER, MAPERIOD1, MA1VALUE, CANDLENUMBER FROM `ma1_data` where NUMBER>"+(string)MA1Number;

   MA1Cursor=MySqlCursorOpen(DB,MA1Query);

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
        
   if(MA1Cursor>=0)
     {
      Rows=MySqlCursorRows(MA1Cursor);
      for(i=0; i<Rows; i++)
         if(MySqlCursorFetchRow(MA1Cursor))
           {

            int ma1_number,ma1_period,ma1_candlenumber;
            double ma1_value;

            ma1_number=MySqlGetFieldAsInt(MA1Cursor,0);
            MA1Number=ma1_number;
            ma1_period=MySqlGetFieldAsInt(MA1Cursor,1);
            ma1_value=MySqlGetFieldAsDouble(MA1Cursor,2);
            ma1_value=NormalizeDouble(ma1_value,_Digits);
            ma1_candlenumber=MySqlGetFieldAsInt(MA1Cursor,3);

            //пишем в индикаторный буфер значение первой скользящей средней
            MA1LineBuffer1[ma1_candlenumber]=ma1_value;

            // смещение положения индикатора для выравнивания с графиком цены
            PlotIndexSetInteger(0,PLOT_SHIFT,rates_total-ma1_candlenumber-1);
           }
      MySqlCursorClose(MA1Cursor); // NEVER FORGET TO CLOSE CURSOR !!!
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
