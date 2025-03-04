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
#property indicator_buffers 2
//задание типа графического построения - цветные свечи
#property indicator_type1 DRAW_COLOR_HISTOGRAM
//#property indicator_type2 DRAW_LINE
#property indicator_width1  2
#property indicator_label1  "TicksVolume"
#property indicator_color1 Green,Red
//Описание индикатор строит тиковые свечи фиксиованной разницы между high и low значениями текущей свечи.
//За основу взят индикатор tickcolorcandles, отсюда
//Пока не сработало условие inaquality, будут проверяться условия алгоритма построения и временные значения high и low
//будут записываться в массив CurrentCandle[]

//--- indicator buffers
//double               MA1LineBuffer1[];
//double               MA2LineBuffer2[];
//+---------------------------------------

//Хранит номер текущей свечи
int CandleNumber=0;
int TicksInCandle=0;
// переменная ticks_stored - хранит количество накопленных и сохраненных тиков и соответственно
// порядковый номер  индексов для массива TicksBuffer[]
//--- indicator buffers
double ExtTVBuffer[];
double ExtColorBuffer[];
int Number=0;
bool firstStart=true;

//---
#include <MQLMySQL.mqh>
string Host,User,Password,Database,Socket; // database credentials
int Port,ClientFlag;
int DB; // database identifier

int number=0;
//int MA1Number=0;
//int MA2Number=0;
//+------------------------------------------------------------------+
//функция OnInit()
//+------------------------------------------------------------------+
void OnInit()
  {

   SetIndexBuffer(0,ExtTVBuffer,INDICATOR_DATA);
   IndicatorSetInteger(INDICATOR_DIGITS,1);
   SetIndexBuffer(1,ExtColorBuffer,INDICATOR_COLOR_INDEX);

   Print(MySqlVersion());

//string INI=TerminalInfoString(TERMINAL_PATH)+"\\MQL5\\Scripts\\MyConnection.ini";

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

//инициализируем массивы нулями
   if(firstStart)
     {
      ArrayInitialize(ExtTVBuffer,0);
      ArrayResize(ExtTVBuffer,5000000);
      firstStart=false;
     }

   string Query;
   int    i,Cursor,Rows;

   Query="SELECT NUMBER, CANDLENUMBER, TICKSINCANDLE FROM `candles` where NUMBER>"+(string)Number;
   Cursor=MySqlCursorOpen(DB,Query);

//Переподключение если связь оборвалась????
   if(DB==-1)
     {
      Print("MySqlErrorDescription: "+MySqlErrorDescription);
      while(DB==-1)
        {
         Print("2Connecting...");
         DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);
         Print("MySqlErrorDescription: "+MySqlErrorDescription);
        }
     }
   else
     {
      //Print("Reconnected on new tick. DBID#",DB);
     }

   if(Cursor>=0)
     {
      Rows=MySqlCursorRows(Cursor);
      for(i=0; i<Rows; i++)
         if(MySqlCursorFetchRow(Cursor))
           {
            Number=MySqlGetFieldAsInt(Cursor,0);
            CandleNumber=MySqlGetFieldAsInt(Cursor,1);
            TicksInCandle=MySqlGetFieldAsInt(Cursor,2);


            // текущая котировка будет являться ценой открытия свечи
            ExtTVBuffer[CandleNumber]=TicksInCandle;

            if(CandleNumber==0)
               ExtColorBuffer[CandleNumber]=0;
            else
               if(ExtTVBuffer[CandleNumber]>ExtTVBuffer[CandleNumber-1])
                  ExtColorBuffer[CandleNumber]=0; // set color Green
               else
                  ExtColorBuffer[CandleNumber]=1;

            PlotIndexSetInteger(0,PLOT_SHIFT,rates_total-CandleNumber-1);
            firstStart=false;
           }
      MySqlCursorClose(Cursor); // NEVER FORGET TO CLOSE CURSOR !!!
     }
   else
     {
      Print("Cursor opening failed. Error: ",MySqlErrorDescription);
     }

   return(rates_total);

   MySqlDisconnect(DB);
   Print("Disconnected. done!");
  }
//+------------------------------------------------------------------+
