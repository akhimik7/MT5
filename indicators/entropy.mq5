//+------------------------------------------------------------------+
//     entropy
//
//+------------------------------------------------------------------+
#property copyright "алхимик"
#property description "entropy"
#property version   "1.00"
//индикатор выводится в отдельное окно
#property indicator_separate_window
// используется одно графическое построение - цветные свечи
//---
#include <MQLMySQL.mqh>
string Host,User,Password,Database,Socket; // database credentials
int Port,ClientFlag;
int DB; // database identifier
bool firstStart=true;
//+------------------------------------------------------------------------------------------+
//| Инициализируем хэшмап хранения данных индикатора меры энтропии рынка                     |
//+------------------------------------------------------------------------------------------+
#include <Generic\SortedMap.mqh>

CSortedMap<double, int> entropy;

int tValue=0;

int tickCounts=0;
double min=0;
double max=0;
double minDensity=0;
double maxDensity=0;

string Query;
int Cursor;
double CurrentTickBID;

//+------------------------------------------------------------------+
//функция OnInit()
//+------------------------------------------------------------------+
void OnInit()
  {

   Print(MySqlVersion());

// reading database credentials from INI file
   Host = "127.0.0.1";
   User = "root";
   Password = "Qw123456";
   Database = "";
   Port     = 3306;
   Socket   = "0";
   ClientFlag=0; //(int)StringToInteger(ReadIni(INI, "MYSQL", "ClientFlag"));

   Print("Host: ",Host,", User: ",User,", Database: ",Database);

// open database connection
   Print("Connecting...");

   DB=MySqlConnect(Host,User,Password,Database,Port,Socket,ClientFlag);

//+------------------------------------------------------------------+
//|            Create database for current Symbol                    |
//+------------------------------------------------------------------+
//удаляем все значения из таблицы eurusd
   Query="CREATE DATABASE IF NOT EXISTS `entropy` CHARACTER SET utf8 COLLATE utf8_general_ci;";
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
   Query="USE `entropy`;";
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
//|                         Truncate table "entropy"                   |
//+------------------------------------------------------------------+
//удаляем все значения из таблицы ticks
   Query="TRUNCATE TABLE `entropy`;";
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
//|                Creating Table for ticks entropy               |
//+------------------------------------------------------------------+
   Query="CREATE TABLE entropy.entropy (number double NOT NULL, tcickCount int DEFAULT NULL, avDensityMaxMin double DEFAULT NULL, avDensitybyAvPrice double DEFAULT NULL, moreThenAvDensity double DEFAULT NULL, lessThenAvDensity double DEFAULT NULL, densityRatio double DEFAULT NULL,  PRIMARY KEY (number))"
         "ENGINE = INNODB, AVG_ROW_LENGTH = 40, CHARACTER SET utf8mb3, COLLATE utf8mb3_general_ci;";

   if(MySqlExecute(DB,Query))
     {
      Print("11Succeeded: ",Query);
     }
   else
     {
      Print("11Error: ",MySqlErrorDescription);
      Print("11Query: ",Query);
     }
//+--------------------------------

//+------------------------------------------------------------------+
//|                         Truncate table "entropy"                   |
//+------------------------------------------------------------------+
//удаляем все значения из таблицы ticks
   Query="TRUNCATE TABLE `density`;";
   if(MySqlExecute(DB,Query))
     {
      Print("Succeeded: ",Query);
     }
   else
     {
      Print("Error: ",MySqlErrorDescription);
      Print("Query: ",Query);
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

   CurrentTickBID=NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_BID),_Digits);

   if(firstStart)
     {
      //инициализируем мапу первым значением

      entropy.Add(CurrentTickBID, 1);

      firstStart=false;


      tickCounts++;

      min = CurrentTickBID;
      max = CurrentTickBID;
      minDensity=CurrentTickBID;
      maxDensity=CurrentTickBID;

      return(rates_total);
     }


   if(entropy.ContainsKey(CurrentTickBID))
     {
      //Print("entropy.ContainsKey(CurrentTickBID) = ",CurrentTickBID);
      if(entropy.TryGetValue(CurrentTickBID, tValue))
        {
         //Print("entropy.ContainsKey(CurrentTickBID): &tValue = ", tValue);
         tValue++;
         //Print("entropy.ContainsKey(CurrentTickBID): tValue++ = ", tValue);
         entropy.TrySetValue(CurrentTickBID, tValue);

        }
      else
        {
         Print("entropy.ContainsKey(CurrentTickBID): НЕ УДАЛОСЬ ПОЛУЧИТЬ VALUE");
        }

      if(CurrentTickBID>max)
        {
         max = CurrentTickBID;
        }

      if(CurrentTickBID<min)
        {
         min = CurrentTickBID;
        }

     }
   else
     {
         entropy.Add(CurrentTickBID, 1);
        //Print("NEW:eentropy.ContainsKey(CurrentTickBID): tValue++ = ", tValue);

   
      if(CurrentTickBID>max)
        {
         max = CurrentTickBID;
        }

      if(CurrentTickBID<min)
        {
         min = CurrentTickBID;
        }
     }
   tickCounts++;

//Print("debug:entropy.Count(): = ", entropy.Count());


//рассчитываем и выводим статистические данные по энтропии
   if(tickCounts%10000==0)
     {

      //Суммируем все плотности
      int sumDensity = 0;

      double avDensity=0;


      //Разница в пунктах деленная на  суммарную плотность
      double avDensityMaxMin=0;
      //средняя количественная плотность - сумма всех плотностей цен деленная на количество цен
      double avDensitybyAvPrice=0;
      //количество всех цен c плотностью больше средней деленное на количество всех цен
      int moreThenAvDensity=0;
      //количество всех цен c плотностью больше средней деленное на количество всех цен
      double lessThenAvDensity=0;
      //чем выше этот коэффициент тем больше ценовых плотностей с меньшим значением чем средняя ценовая плотность, и вероятно более стабильные тренды у пары, и веротяно ниже количественный показатель флэта lessThenAvDensity/moreThenAvDensity
      double densityRatio=0;
      double keys[];
      int values[];

      entropy.CopyTo(keys,values);
      for(int i=0;i<entropy.Count();i++)
        {
         sumDensity+=values[i];
         if(values[i]>maxDensity)
           {
            maxDensity = values[i];
           }
         if(values[i]<minDensity)
           {
            maxDensity = values[i];
           }
        }
      Print("sumDensity: = ", sumDensity);
      Print("entropy.Count(): = ", entropy.Count());
      //1. avDensityMaxMin
      avDensityMaxMin = sumDensity/((max-min)/_Point);

      //2. avDensitybyAvPrice
      avDensitybyAvPrice = entropy.Count()/sumDensity;

      //3. moreThenAvDensity
      avDensity=(minDensity+maxDensity)/2;
      for(int i=0;i<entropy.Count();i++)

        {
         if(values[i]>avDensity)
           {
            moreThenAvDensity++;
           }
        }
      //4.densityRatio
      densityRatio = lessThenAvDensity/moreThenAvDensity;


      Comment(StringFormat("tickCounts=%G\navDensityMaxMin=%G\navDensitybyAvPrice=%G\nmoreThenAvDensity=%G\nlessThenAvDensity=%G\ndensityRatio=%G\n", tickCounts, avDensityMaxMin, avDensitybyAvPrice,moreThenAvDensity, lessThenAvDensity, densityRatio));
      //пишем в таблицу промежуточные расчёты
         //+------------------------------------------------------------------+
         //|  Inserting first tick in Table of Symbol Ticks statistics        |
         //+------------------------------------------------------------------+
         Query="REPLACE INTO entropy (tickCounts, avDensityMaxMin, avDensitybyAvPrice ,moreThenAvDensity, lessThenAvDensity, densityRatio) VALUES (" + tickCounts + ", "+ (string)avDensityMaxMin + ", "+ (string)avDensitybyAvPrice + ", "+ (string)moreThenAvDensity + ", "+ (string)lessThenAvDensity + ", "+ (string)densityRatio + ");";
         //получаем количество миллисекунд прошедших с момента старта системы
         if(MySqlExecute(DB,Query))
           {
            //   Print("Succeeded: ",Query);
           }
         else
           {
            Print("Error11: ",MySqlErrorDescription);
            Print("Query: ",Query);
           }
           
      min = 0;
      max = 0;
      minDensity=0;
      maxDensity=0;
     }

//возврат из функции OnCalculate()
   return(rates_total);

   MySqlDisconnect(DB);
   Print("Disconnected. done!");
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
