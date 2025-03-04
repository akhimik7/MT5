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
#property indicator_label1  "Spread"
#property indicator_color1 Green,Red


//Хранит номер текущей свечи
int CandleNumber=0;
double O,C;
// переменная ticks_stored - хранит количество накопленных и сохраненных тиков и соответственно
// порядковый номер  индексов для массива TicksBuffer[]
//--- indicator buffers
double OCBuffer[];
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

   SetIndexBuffer(0,OCBuffer,INDICATOR_DATA);
   IndicatorSetInteger(INDICATOR_DIGITS,1);
   SetIndexBuffer(1,ExtColorBuffer,INDICATOR_COLOR_INDEX);

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

   if(DB==-1) { Print("Connection failed! Error: "+MySqlErrorDescription); } else { Print("Connected! DBID#",DB);}
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
      ArrayInitialize(OCBuffer,0);
      ArrayResize(OCBuffer,5000000);
      firstStart=false;
     }

   string Query;
   int    i,Cursor,Rows;

   Query="SELECT NUMBER, CANDLENUMBER, O, C FROM `candles` where NUMBER>"+(string)Number;
   Cursor=MySqlCursorOpen(DB,Query);

   if(Cursor>=0)
     {
      Rows=MySqlCursorRows(Cursor);
      for(i=0; i<Rows; i++)
         if(MySqlCursorFetchRow(Cursor))
           {
            Number=MySqlGetFieldAsInt(Cursor,0);
            CandleNumber=MySqlGetFieldAsInt(Cursor,1);
            O=MySqlGetFieldAsDouble(Cursor,2);
            C=MySqlGetFieldAsDouble(Cursor,3);

            if(O>C)
              {
               OCBuffer[CandleNumber]=NormalizeDouble((O-C)*100000,_Digits);
              }

            else if(C>O)
              {
               OCBuffer[CandleNumber]=NormalizeDouble((C-O)*100000,_Digits);
              }

            else if(O==C)
              {
               OCBuffer[CandleNumber]=NormalizeDouble((O-C)*100000,_Digits);
              }

            if(CandleNumber==0) ExtColorBuffer[CandleNumber]=0;
            else if(OCBuffer[CandleNumber]>OCBuffer[CandleNumber-1]) ExtColorBuffer[CandleNumber]=0; // set color Green
            else ExtColorBuffer[CandleNumber]=1;

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
