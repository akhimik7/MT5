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
#property indicator_plots 3
// для свечей индикатора необходимо 4 буфера для цен OHLC и один - для индекса цвета
#property indicator_buffers 6
//задание типа графического построения - цветные свечи
#property indicator_type1 DRAW_COLOR_CANDLES

// задание цветов для раскраски свечей
#property indicator_color1 Gray,Red,Green

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
//+------------------------------------------------------------------+
//функция OnInit()
//+------------------------------------------------------------------+
void OnInit()
  {

// массив OpenBuffer[] является индикаторным буфером
   SetIndexBuffer(0,OpenBuffer,INDICATOR_DATA);
// массив HighBuffer[] является индикаторным буфером
   SetIndexBuffer(1,HighBuffer,INDICATOR_DATA);
//массив LowBuffer[] является индикаторным буфером
   SetIndexBuffer(2,LowBuffer,INDICATOR_DATA);
//массив CloseBuffer[] является индикаторным буфером
   SetIndexBuffer(3,CloseBuffer,INDICATOR_DATA);
//массив ColorIndexBuffer[] является буфером индекса цвета
   SetIndexBuffer(4,ColorIndexBuffer,INDICATOR_COLOR_INDEX);

//индексация в массиве OpenBuffer[] будет производиться как в таймсериях
   ArraySetAsSeries(OpenBuffer,false);
// индексация в массиве HighBuffer[] будет производиться как в таймсериях
   ArraySetAsSeries(HighBuffer,false);
// индексация в массиве LowBuffer[] будет производиться как в таймсериях
   ArraySetAsSeries(LowBuffer,false);
// индексация в массиве CloseBuffer[] будет производиться как в таймсериях
   ArraySetAsSeries(CloseBuffer,false);
// индексация в массиве ColorIndexBuffer[] будет производиться как в таймсериях
   ArraySetAsSeries(ColorIndexBuffer,false);
// нулевые значения в графическом построении 0 (цены Open) не отрисовываются
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0);
//нулевые значения в графическом построении 1 (цены High) не отрисовываются
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,0);
//нулевые значения в графическом построении 2 (цены Low) не отрисовываются
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,0);
//нулевые значения в графическом построении 3 (цены Close) не отрисовываются
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,0);

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
         Print("MySqlErrorDescription: "+MySqlErrorDescription);
       
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

   double      O;
   double      H;
   double      L;
   double      C;

   if(firstStart)
     {

      //инициализируем массивы нулями
      ArrayInitialize(OpenBuffer,0);
      ArrayInitialize(HighBuffer,0);
      ArrayInitialize(LowBuffer,0);
      ArrayInitialize(CloseBuffer,0);

      string Query;
      int    i,Cursor,Rows;


      Query="SELECT NUMBER, O, H, L, C, CANDLENUMBER FROM `candles`";
      Cursor=MySqlCursorOpen(DB,Query);

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
         //Print("Reconnected on new tick. DBID#",DB);
        }
        
      if(Cursor>=0)
        {
         Rows=MySqlCursorRows(Cursor);
         //Print(Rows," row(s) selected.");
         for(i=0; i<Rows; i++)
            if(MySqlCursorFetchRow(Cursor))
              {
               OHLCNumber=MySqlGetFieldAsInt(Cursor,0);
               O=MySqlGetFieldAsDouble(Cursor,1);
               O=NormalizeDouble(O,_Digits);
               H=MySqlGetFieldAsDouble(Cursor,2);
               H=NormalizeDouble(H,_Digits);
               L=MySqlGetFieldAsDouble(Cursor,3);
               L=NormalizeDouble(L,_Digits);
               C=MySqlGetFieldAsDouble(Cursor,4);
               C=NormalizeDouble(C,_Digits);
               CandleNumber=MySqlGetFieldAsInt(Cursor,5);

               Print("ROW[",i,"]: OHLCNumber = ",OHLCNumber,", O = ",O,", H = ",H,",L = ",L,", C = ",C,", CandleNumbere = ",CandleNumber);
               // текущая котировка будет являться ценой открытия свечи
               OpenBuffer[CandleNumber]=O;
               // текущая котировка будет являться максимальной ценой свечи
               HighBuffer[CandleNumber]=H;
               // текущая котировка будет являться минимальной ценой свечи
               LowBuffer[CandleNumber]=L;
               // текущая котировка пока является ценой закрытия текущей свечи
               CloseBuffer[CandleNumber]=C;
               // свеча будет иметь цвет с индексом 0 (серый)
               ColorIndexBuffer[CandleNumber]=0;
               // Comment(StringFormat("OHLCNumber=%G\nOpenBuffer[CandleNumber]=%G\nHughBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\nCandleNumber=%G",OHLCNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],CandleNumber));
               // если свеча растущая, то она будет иметь цвет с индексом 2 (зеленый)
               if(CloseBuffer[CandleNumber]>OpenBuffer[CandleNumber])
                  ColorIndexBuffer[CandleNumber]=2;
               // если свеча падающая, то она будет иметь цвет с индексом 1 (красный)
               if(CloseBuffer[CandleNumber]<OpenBuffer[CandleNumber])
                  ColorIndexBuffer[CandleNumber]=1;
               // если цены открытия и закрытия свечи равны между собой, то свеча будет иметь цвет с индексом 0 (серый)
               if(CloseBuffer[CandleNumber]==OpenBuffer[CandleNumber])
                  ColorIndexBuffer[CandleNumber]=0;

               // смещение положения индикатора для выравнивания с графиком цены
               PlotIndexSetInteger(0,PLOT_SHIFT,rates_total-CandleNumber-1);
               PlotIndexSetInteger(1,PLOT_SHIFT,rates_total-CandleNumber-1);
               PlotIndexSetInteger(2,PLOT_SHIFT,rates_total-CandleNumber-1);
               PlotIndexSetInteger(3,PLOT_SHIFT,rates_total-CandleNumber-1);
               firstStart=false;
              }
         MySqlCursorClose(Cursor); // NEVER FORGET TO CLOSE CURSOR !!!
        }
      else
        {
         Print("Cursor opening failed. Error: ",MySqlErrorDescription);
        }
        
        

      return(rates_total);
     }

   string Query;
   int    i,Cursor,Rows;

//  int CandleNumber;

   Query="SELECT NUMBER, O, H, L, C, CANDLENUMBER FROM `candles` where NUMBER>"+(string)OHLCNumber;
   Cursor=MySqlCursorOpen(DB,Query);

   if(Cursor>=0)
     {
      Rows=MySqlCursorRows(Cursor);
      for(i=0; i<Rows; i++)
         if(MySqlCursorFetchRow(Cursor))
           {
            OHLCNumber=MySqlGetFieldAsInt(Cursor,0);
            O=MySqlGetFieldAsDouble(Cursor,1);
            O=NormalizeDouble(O,_Digits);
            H=MySqlGetFieldAsDouble(Cursor,2);
            H=NormalizeDouble(H,_Digits);
            L=MySqlGetFieldAsDouble(Cursor,3);
            L=NormalizeDouble(L,_Digits);
            C=MySqlGetFieldAsDouble(Cursor,4);
            C=NormalizeDouble(C,_Digits);
            CandleNumber=MySqlGetFieldAsInt(Cursor,5);

            // текущая котировка будет являться ценой открытия свечи
            OpenBuffer[CandleNumber]=O;
            // текущая котировка будет являться максимальной ценой свечи
            HighBuffer[CandleNumber]=H;
            // текущая котировка будет являться минимальной ценой свечи
            LowBuffer[CandleNumber]=L;
            // текущая котировка пока является ценой закрытия текущей свечи
            CloseBuffer[CandleNumber]=C;
            // свеча будет иметь цвет с индексом 0 (серый)
            ColorIndexBuffer[CandleNumber]=0;
            //Comment(StringFormat("OHLCNumber=%G\nOpenBuffer[CandleNumber]=%G\nHughBuffer[CandleNumber]=%G\nLowBuffer[CandleNumber]=%G\nCloseBuffer[CandleNumber]=%G\nCandleNumber=%G",OHLCNumber,OpenBuffer[CandleNumber],HighBuffer[CandleNumber],LowBuffer[CandleNumber],CloseBuffer[CandleNumber],CandleNumber));
            // если свеча растущая, то она будет иметь цвет с индексом 2 (зеленый)
            if(CloseBuffer[CandleNumber]>OpenBuffer[CandleNumber])
               ColorIndexBuffer[CandleNumber]=2;
            // если свеча падающая, то она будет иметь цвет с индексом 1 (красный)
            if(CloseBuffer[CandleNumber]<OpenBuffer[CandleNumber])
               ColorIndexBuffer[CandleNumber]=1;
            // если цены открытия и закрытия свечи равны между собой, то свеча будет иметь цвет с индексом 0 (серый)
            if(CloseBuffer[CandleNumber]==OpenBuffer[CandleNumber])
               ColorIndexBuffer[CandleNumber]=0;

            // смещение положения индикатора для выравнивания с графиком цены
            PlotIndexSetInteger(0,PLOT_SHIFT,rates_total-CandleNumber-1);
            PlotIndexSetInteger(1,PLOT_SHIFT,rates_total-CandleNumber-1);
            PlotIndexSetInteger(2,PLOT_SHIFT,rates_total-CandleNumber-1);
            PlotIndexSetInteger(3,PLOT_SHIFT,rates_total-CandleNumber-1);

           }
      MySqlCursorClose(Cursor); // NEVER FORGET TO CLOSE CURSOR !!!
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
