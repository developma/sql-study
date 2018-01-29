# 集約
## 集約関数(aggregate function)  
標準SQLに次のような集約関数がある。  

- COUNT
- SUM
- AVG
- MAX
- MIN

### 非集約テーブルのサンプル  
```sql  
CREATE TABLE NonAggTbl  
(  
  id VARCHAR(32) NOT NULL,  
  data_type CHAR(1) NOT NULL,  
  data_1 INTEGER,  
  data_2 INTEGER,  
  data_3 INTEGER,  
  data_4 INTEGER,  
  data_5 INTEGER,  
  data_6 INTEGER  
);  

DELETE FROM NonAggTbl;  
INSERT INTO NonAggTbl VALUES('Jim',    'A',  100,  10,     34,  346,   54,  NULL);  
INSERT INTO NonAggTbl VALUES('Jim',    'B',  45,    2,    167,   77,   90,   157);  
INSERT INTO NonAggTbl VALUES('Jim',    'C',  NULL,  3,    687, 1355,  324,   457);  
INSERT INTO NonAggTbl VALUES('Ken',    'A',  78,    5,    724,  457, NULL,     1);  
INSERT INTO NonAggTbl VALUES('Ken',    'B',  123,  12,    178,  346,   85,   235);  
INSERT INTO NonAggTbl VALUES('Ken',    'C',  45, NULL,     23,   46,  687,    33);  
INSERT INTO NonAggTbl VALUES('Beth',   'A',  75,    0,    190,   25,  356,  NULL);  
INSERT INTO NonAggTbl VALUES('Beth',   'B',  435,   0,    183, NULL,    4,   325);  
INSERT INTO NonAggTbl VALUES('Beth',   'C',  96,  128,   NULL,    0,    0,    12);  
commit;  
```  

上記のテーブルはCSVや固定長などのフラットファイルをイメージすると良い。  
人物を管理するID列、データの種別を管理するdata_type列を加えて主キーとしている。(あまり良くない例)  

特定の人物かつ特定のデータを持つ情報を得たい場合、`WHERE id = XXX AND data_type = X`というクエリを発行する必要がある。  
また、ある業務ではdata_1, data_2, 別の業務ではdata_3を使うケースだと、どんなクエリを出したとしても列数が異なり、UNIONで1つのクエリにまとめることが出来ない。  
情報を集約し、一人分の情報がすべて同じ行にまとまるようにする。

```sql
SELECT id,  
	   MAX(CASE WHEN data_type = 'A' THEN data_1 ELSE NULL END) AS data_1,  
	   MAX(CASE WHEN data_type = 'A' THEN data_2 ELSE NULL END) AS data_2,  
       MAX(CASE WHEN data_type = 'B' THEN data_3 ELSE NULL END) AS data_3,  
	   MAX(CASE WHEN data_type = 'B' THEN data_4 ELSE NULL END) AS data_4,  
	   MAX(CASE WHEN data_type = 'B' THEN data_5 ELSE NULL END) AS data_5,  
	   MAX(CASE WHEN data_type = 'C' THEN data_6 ELSE NULL END) AS data_6  
FROM NonAggTbl  
GROUP BY id;  
```

GROUP BY idで切り分けた時点では各集合(Jim, Ken, Beth)は3つの要素を含んでる。  
集約関数を適用すると、その時点でNULLが除外される。  

GROUP BYは、メモリを多く使用する演算のため、十分なワーキングメモリが確保出来ていないと、  
スワップが発生して遅延することがある。  

### 練習1  

```sql
CREATE TABLE PriceByAge  
(  
  product_id VARCHAR(32) NOT NULL,  
  low_age    INTEGER NOT NULL,  
  high_age   INTEGER NOT NULL,  
  price      INTEGER NOT NULL,  
  PRIMARY KEY (product_id, low_age),  
  CHECK (low_age < high_age)  
);  

INSERT INTO PriceByAge VALUES('製品1',  0  ,  50  ,  2000);  
INSERT INTO PriceByAge VALUES('製品1',  51 ,  100 ,  3000);  
INSERT INTO PriceByAge VALUES('製品2',  0  ,  100 ,  4200);  
INSERT INTO PriceByAge VALUES('製品3',  0  ,  20  ,  500);  
INSERT INTO PriceByAge VALUES('製品3',  31 ,  70  ,  800);  
INSERT INTO PriceByAge VALUES('製品3',  71 ,  100 ,  1000);  
INSERT INTO PriceByAge VALUES('製品4',  0  ,  99  ,  8900);  
commit;  
```

複数の製品の対象年齢ごとの値段を管理するテーブル。  
同じIDでも対象年齢の違いにより値段が変わっている。  
1つの製品で、年齢範囲の重複するレコードはないと仮定する。  

製品1の場合、2レコードを使って0〜100歳までカバーしている。  
しかし、製品3は21〜30歳に空きがある。  

このテーブルから、0〜100歳までの全ての年齢で遊べる製品を求める。  

```sql
SELECT product_id  
FROM PriceByAge  
GROUP BY product_id  
HAVING SUM(high_age - low_age + 1) = 101;  
```

### 練習2  

```sql
CREATE TABLE HotelRooms  
(
  room_nbr	INTEGER,  
  start_date DATE,  
  end_date   DATE,  
  PRIMARY KEY(room_nbr, start_date)  
);  

INSERT INTO HotelRooms VALUES(101,	'2008-02-01',	'2008-02-06');  
INSERT INTO HotelRooms VALUES(101,	'2008-02-06',	'2008-02-08');  
INSERT INTO HotelRooms VALUES(101,	'2008-02-10',	'2008-02-13');  
INSERT INTO HotelRooms VALUES(202,	'2008-02-05',	'2008-02-08');  
INSERT INTO HotelRooms VALUES(202,	'2008-02-08',	'2008-02-11');  
INSERT INTO HotelRooms VALUES(202,	'2008-02-11',	'2008-02-12');  
INSERT INTO HotelRooms VALUES(303,	'2008-02-03',	'2008-02-17');  
commit;  
```

稼動日数が10日以上の部屋を選択する。  
稼動日数の定義は、宿泊日数で計る。2/1到着、2/6出発の場合、5泊なので5日。  

```sql
SELECT  
 room_nbr,  
 SUM(end_date - start_date)  
FROM HotelRooms  
GROUP BY room_nbr  
HAVING SUM(end_date - start_date) >= 10;  
```

## カット  
GROUP BY句には、カットという機能がある。  
母集合である元のテーブルを小さな部分集合に切り分ける。  

### カットとパーティション  

```sql
CREATE TABLE Persons  
(  
  name   VARCHAR(8) NOT NULL,  
  age    INTEGER NOT NULL,  
  height FLOAT NOT NULL,  
  weight FLOAT NOT NULL,  
  PRIMARY KEY (name)  
);  

INSERT INTO Persons VALUES('Anderson',  30,  188,  90);  
INSERT INTO Persons VALUES('Adela',    21,  167,  55);  
INSERT INTO Persons VALUES('Bates',    87,  158,  48);  
INSERT INTO Persons VALUES('Becky',    54,  187,  70);  
INSERT INTO Persons VALUES('Bill',    39,  177,  120);  
INSERT INTO Persons VALUES('Chris',    90,  175,  48);  
INSERT INTO Persons VALUES('Darwin',  12,  160,  55);  
INSERT INTO Persons VALUES('Dawson',  25,  182,  90);  
INSERT INTO Persons VALUES('Donald',  30,  176,  53);  
commit;  
```

名簿のインデックスを作るために、名前の頭文字のアルファベットごとに何人テーブルにいるか調べる。  

```sql
SELECT   
  SUBSTR(name, 1, 1) AS label, COUNT(*)  
 FROM Persons  
GROUP BY SUBSTR(name, 1, 1);  
```

GROUP BY句でカットして作られた1つ1つの部分集合は、類(partition)と呼ばれる。  
互いに重複する要素を持たない部分集合のこと。  

年齢によって、子供(20歳未満)、成人(20〜69歳)、老人(70歳以上)で分けてみる。

```sql
SELECT__
  CASE WHEN age < 20 THEN '子供'  
       WHEN age BETWEEN 20 AND 69 THEN '成人'  
 	   WHEN age >= 70 THEN '老人'  
   	   ELSE NULL  
	   END AS age_class  ,  
  COUNT(*)  
 FROM Persons  
GROUP BY  
  CASE WHEN age < 20 THEN '子供'  
       WHEN age BETWEEN 20 AND 69 THEN '成人'  
 	   WHEN age >= 70 THEN '老人'  
   	   ELSE NULL  
	   END;  
```

BMIでカットしてみる。  
BMIの式は、`kg / m^2`。  

18.5未満が痩せ、18.5以上25未満を標準、25以上が肥満となる。  

```sql
SELECT  
  CASE WHEN weight / POWER(height /100, 2) < 18.5 THEN 'やせ'  
       WHEN 18.5 <= weight / POWER(height /100, 2)  AND weight / POWER(height /100, 2) < 25 THEN '標準'  
       WHEN 25 <= weight / POWER(height /100, 2) THEN '肥満'  
       ELSE NULL END AS bmi,  
       COUNT(*)  
　FROM Persons  
 GROUP BY CASE WHEN weight / POWER(height /100, 2) < 18.5 THEN 'やせ'  
               WHEN 18.5 <= weight / POWER(height /100, 2) AND weight / POWER(height /100, 2) < 25 THEN '標準'  
               WHEN 25 <= weight / POWER(height /100, 2) THEN '肥満'  
               ELSE NULL END;  
```

### PARTITION BY句を使ったカット  
GROUP BYから集約機能を取り去り、カット機能だけ残したのがウィンドウ関数のPARTITION BY。  
前述の年齢算出を、PARTITION BYでやってみる。  

```sql
SELECT  
   name,  
   age,  
   CASE WHEN age < 20 THEN '子供'  
        WHEN age BETWEEN 20 AND 69 THEN '成人'  
		WHEN age >= 70 THEN '老人'  
		ELSE NULL END AS age_class,  
   RANK() OVER(PARTITION BY CASE WHEN age < 20 THEN '子供'  
                                 WHEN age BETWEEN 20 AND 69 THEN '成人'  
                                 WHEN age >= 70 THEN '老人'  
                                 ELSE NULL END ORDER BY age) AS age_rank_in_class  
  FROM Persons  
ORDER BY age_class, age_rank_in_class;  
```
