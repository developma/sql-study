# SQLにおけるループ  
SQLは意識的にループを言語設計から排除してる。(もともとはループを無くそうという発想で作られた言語)  
しかし、1レコードアクセスするSQLをループでまわし、ビジネスロジックをホスト側で処理している。  
こうして`ぐるぐる系`が出来る。  
たとえば…  

- オンライン処理で、画面に明細行を表示させるために、1行ずつ明細にアクセスするSELECT文をループさせる
- バッチ処理で大量データを処理するため、1行ずつレコードをフェッチしてホスト側で処理を行い、また1行ずつテーブルを更新する

## ぐるぐる系のサンプル  

```sql
CREATE TABLE Sales  
(
  company CHAR(1) NOT NULL,  
  year    INTEGER NOT NULL,  
  sale    INTEGER NOT NULL,  
  CONSTRAINT pk_sales PRIMARY KEY (company, year)  
);  

INSERT INTO Sales VALUES ('A', 2002, 50);  
INSERT INTO Sales VALUES ('A', 2003, 52);  
INSERT INTO Sales VALUES ('A', 2004, 55);  
INSERT INTO Sales VALUES ('A', 2007, 55);  
INSERT INTO Sales VALUES ('B', 2001, 27);  
INSERT INTO Sales VALUES ('B', 2005, 28);  
INSERT INTO Sales VALUES ('B', 2006, 28);  
INSERT INTO Sales VALUES ('B', 2009, 30);  
INSERT INTO Sales VALUES ('C', 2001, 40);  
INSERT INTO Sales VALUES ('C', 2005, 39);  
INSERT INTO Sales VALUES ('C', 2006, 38);  
INSERT INTO Sales VALUES ('C', 2010, 35);  

CREATE TABLE Sales2  
(
  company CHAR(1) NOT NULL,  
  year    INTEGER NOT NULL,  
  sale    INTEGER NOT NULL,  
  var     CHAR(1),  
  CONSTRAINT pk_sales2 PRIMARY KEY (company, year)  
);  

commit;

```

- Salesテーブルは企業ごとに会計年ごとの売上を記録する  
  - ただし、年は連続しているとは限らない  

同じ企業について、ある年とその直近の年の売上の変化を調べる。  
その結果を、Sales2テーブルのvar列に追加する。  
var列には次のルールがある。  
 - より古い年のデータが存在しない場合: NULL  
 - 直近の年のデータより売上が伸びた場合: +  
 - 直近の年のデータより売上が減った場合: -  
 - 直近の年のデータより売上が同じ場合: =  
 
 ```sql
CREATE OR REPLACE PROCEDURE PROC_INSERT_VAR  
IS  

  /* カーソル宣言 */  
  CURSOR c_sales IS  
       SELECT company, year, sale  
         FROM Sales  
        ORDER BY company, year;  

  /* レコードタイプ宣言 */  
  rec_sales c_sales%ROWTYPE;  

  /* カウンタ */  
  i_pre_sale INTEGER := 0;  
  c_company CHAR(1) := '*';  
  c_var CHAR(1) := '*';  

BEGIN  

OPEN c_sales;  

  LOOP  
    /* レコードをフェッチして変数に代入 */  
    fetch c_sales into rec_sales;  
    /* レコードがなくなったらループ終了 */  
    exit when c_sales%notfound;  

    IF (c_company = rec_sales.company) THEN  
        /* 直前のレコードが同じ会社のレコードの場合 */  
        /* 直前のレコードと売り上げを比較*/  
        IF (i_pre_sale < rec_sales.sale) THEN  
            c_var := '+';  
        ELSIF (i_pre_sale > rec_sales.sale) THEN  
            c_var := '-';  
        ELSE  
            c_var := '=';  
        END IF;  

    ELSE  
        c_var := NULL;  
    END IF;  

    /* 登録先テーブルにデータを登録 */  
    INSERT INTO Sales2 (company, year, sale, var)  
      VALUES (rec_sales.company, rec_sales.year, rec_sales.sale, c_var);  

    c_company := rec_sales.company;  
    i_pre_sale := rec_sales.sale;  

  END LOOP;  

  CLOSE c_sales;  
  commit;  
END;  
 ```
 
 今年のレコードと直近のレコードの値を比較するロジックを1レコードずつ繰り返す。  
 こういうぐるぐる系のメリットは、SQLをほとんど知らなくても解ける、処理を単純化出来る、こと。  
 ぐるぐる系の反対は`ガツン系`。  
 ガツン系のSQLは、ビジネスロジックをSQLに入れこむために複雑化、保守性が低くなる。  
 
 
### ぐるぐる系の欠点  
パフォーマンスが問題。  
ぐるぐる系は、処理時間が線形に伸びる。  
ガツン系は、対数関数的な曲線になる。当然、SQLのパターンにもよるが。  


ぐるぐる系がガツン系にパフォーマンスで負ける理由は以下。  

- SQL実行のオーバヘッド  
  SQL実行には以下の処理が行なわれている。  
  1. SQL文のネットワーク伝送  
  2. データベースへの接続  
  3. SQL文のパース  
  4. SQL文の実行計画生成および評価  
  5. 結果セットのネットワーク伝送  

細かいSQLを積み重ねてるので、ぐるぐる系はオーバヘッドに占める割合が大きくなってくる。  

- 並列分散がやりにくい  
ループ1回あたりの処理を単純化している関係で、リソース分散したうえでの並列処理による最適化が受けられない。  
I/Oを並列化しにくい。  

- データベース進化による恩恵を受けられない  
最近のデータベースは、SSDや最適化により大規模データを扱う複雑なSQL文を早くする努力がなされている。  
しかし、ガツン系のSQLが十分にチューニングされていれば、という前提がつく。  
また、ぐるぐる系にはチューニングポテンシャルがほとんど無い。  

### ぐるぐる系を早くするには?  

選択肢は大きく次の3つ。  

1. ぐるぐる系をガツン系に書き換える  
アプリケーションの改修になる。  
2. 個々のSQLを早くする  
ぐるぐる系のSQLはすでに十分に単純なものになっている。  
INSERT文で、コミット間隔を広げるか、バルクINSERTを使うか、ぐらいしかない。  
3. 処理を多重化する  
CPUやディスクといったリソースに余裕があり、処理をうまく分割出来るキーがあれば、  
ループそのものを多重化出来るので現実的な解。  
ただし、データを分割出来るキーがない、順序が求められたり、多重度を設計していなかったり、だと意味がない。  

### ぐるぐる系の利点  

1. 実行計画が安定する  
SQLが単純なので、実行計画に変動リスクがほとんど無い。  
本番中に実行計画が変わってスローダウンするトラブルから開放される。  
また、SQL文で結合を記述する必要がないというぼも大きい。特に、実行計画の中で結合アルゴリズムが変動大きい。  
これ、逆にいうと、ガツン系のデメリットでもある。  

2. 処理時間の見積り精度が(相対的には)高い  

処理時間は次のように見積れる。  
`処理時間 = 1回あたり実行時間 * 実行回数`  

ガツン系よりは見積りやすい、ということ。  

3. トランザクション制御が容易  
トランザクション粒度を細かく設定出来る。  
特定のループ回数ごとにコミットするような処理がある場合、ある更新処理でエラーが発生したときに、  
直前のコミットからリスタート可能。  
こういう制御は、ガツン系では出来ない。  



### 利点と欠点のトレードオフ   
ぐるぐる系か、ガツン系かは、利点と欠点のトレードオフを考慮して選択する必要がある。  


## ガツン系のサンプル  

SQLでループを代用する技術は、CASE式とウィンドウ関数。  

```sql
INSERT INTO Sales2  
   SELECT company,  
          year,  
		  sale,  
		  /* 現在のsaleと、1個前のsaleを比較する */  
		  /* SIGN関数は、数値型を引数にとり、符号がマイナスなら-1, プラスなら1, 0なら0を返す */  
		  CASE SIGN(sale - MAX(sale)  
		            OVER ( PARTITION BY company  
					       ORDER BY year  
						   /* さかのぼる対象範囲のレコードを直前の1行に制限している */  
						   /* カレントレコードの1行前から1行前の範囲、という意味 */  
						   ROWS BETWEEN 1 PRECEDING AND 1 PRECEING ) )  
		  WHEN 0 THEN '='  
		  WHEN 1 THEN '+'  
		  WHEN -1 THEN '-'  
		  ELSE NULL END AS var  
   FROM Sales;  
```

まず、テーブルをフルスキャンし、ウィンドウ関数をソートして実行している。

## 近似する郵便番号をガツン系で求める  

2つの異なる郵便番号は、下位の桁まで一致するほど近い地域を意味する。  
最寄りの郵便番号を検索してみる。

```sql
CREATE TABLE PostalCode  
(  
   pcode CHAR(7),  
   district_name VARCHAR(256),  
   CONSTRAINT pk_pcode PRIMARY KEY(pcode)  
);  

INSERT INTO PostalCode VALUES ('4130001',  '静岡県熱海市泉');  
INSERT INTO PostalCode VALUES ('4130002',  '静岡県熱海市伊豆山');  
INSERT INTO PostalCode VALUES ('4130103',  '静岡県熱海市網代');  
INSERT INTO PostalCode VALUES ('4130041',  '静岡県熱海市青葉町');  
INSERT INTO PostalCode VALUES ('4103213',  '静岡県伊豆市青羽根');  
INSERT INTO PostalCode VALUES ('4380824',  '静岡県磐田市赤池');  
commit;  
```

4130033に最寄りの番号を求める。

```sql

SELECT pcode,
       district_name,
	   CASE WHEN pcode = '4130033' THEN 0
	        WHEN pcode LIKE '413003%' THEN 1
			WHEN pcode LIKE '41300%' THEN 2
			WHEN pcode LIKE '4130%' THEN 3
			WHEN pcode LIKE '413%' THEN 4
			WHEN pcode LIKE '41%' THEN 5
			WHEN pcode LIKE '4%' THEN 6
			ELSE NULL END AS rank
 FROM PostalCode;
```

```sql
SELECT pcode,
       district_name
  FROM PostalCode  
 WHERE CASE WHEN pcode = '4130033' THEN 0
	        WHEN pcode LIKE '413003%' THEN 1
			WHEN pcode LIKE '41300%' THEN 2
			WHEN pcode LIKE '4130%' THEN 3
			WHEN pcode LIKE '413%' THEN 4
			WHEN pcode LIKE '41%' THEN 5
			WHEN pcode LIKE '4%' THEN 6
            ELSE NULL END = 
			     (SELECT MIN(CASE WHEN pcode = '4130033' THEN 0
                                  WHEN pcode LIKE '413003%' THEN 1
                                  WHEN pcode LIKE '41300%' THEN 2
                                  WHEN pcode LIKE '4130%' THEN 3
                                  WHEN pcode LIKE '413%' THEN 4
                                  WHEN pcode LIKE '41%' THEN 5
                                  WHEN pcode LIKE '4%' THEN 6
								  ELSE NULL END)
				    FROM PostalCode);
```

この実装だと、PostalCodeテーブルに対するスキャンが2回発生している。  
ウィンドウ関数でスキャンを減らすようにする。  

```sql
SELECT pcode,
       district_name
  FROM (SELECT pcode,
               district_name,
               CASE WHEN pcode = '4130033' THEN 0
                    WHEN pcode LIKE '413003%' THEN 1
                    WHEN pcode LIKE '41300%'  THEN 2
                    WHEN pcode LIKE '4130%'   THEN 3
                    WHEN pcode LIKE '413%'    THEN 4
                    WHEN pcode LIKE '41%'     THEN 5
                    WHEN pcode LIKE '4%'      THEN 6
                    ELSE NULL END AS hit_code,
               MIN(CASE WHEN pcode = '4130033' THEN 0
                        WHEN pcode LIKE '413003%' THEN 1
                        WHEN pcode LIKE '41300%'  THEN 2
                        WHEN pcode LIKE '4130%'   THEN 3
                        WHEN pcode LIKE '413%'    THEN 4
                        WHEN pcode LIKE '41%'     THEN 5
                        WHEN pcode LIKE '4%'      THEN 6
                        ELSE NULL END) 
                OVER(ORDER BY CASE WHEN pcode = '4130033' THEN 0
                                   WHEN pcode LIKE '413003%' THEN 1
                                   WHEN pcode LIKE '41300%'  THEN 2
                                   WHEN pcode LIKE '4130%'   THEN 3
                                   WHEN pcode LIKE '413%'    THEN 4
                                   WHEN pcode LIKE '41%'     THEN 5
                                   WHEN pcode LIKE '4%'      THEN 6
                                   ELSE NULL END) AS min_code
          FROM PostalCode) Foo
 WHERE hit_code = min_code;
```

何度みても、これがいまいちよく分からない…。とりあえず次へ行こう…。

### 隣接リストモデルと再帰クエリ  

郵便番号の履歴管理サンプル。  

```sql
CREATE TABLE PostalHistory
(
  name  CHAR(1),
  pcode CHAR(7),
  new_pcode CHAR(7),
  CONSTRAINT pk_name_pcode PRIMARY KEY(name, pcode)
);

INSERT INTO PostalHistory VALUES ('A', '4130001', '4130002');
INSERT INTO PostalHistory VALUES ('A', '4130002', '4130103');
INSERT INTO PostalHistory VALUES ('A', '4130103', NULL     );
INSERT INTO PostalHistory VALUES ('B', '4130041', NULL     );
INSERT INTO PostalHistory VALUES ('C', '4103213', '4380824');
INSERT INTO PostalHistory VALUES ('C', '4380824', NULL     );
commit;
```

現住所を登録するときは、new_pcodeをNULLにし、name, pcodeに値を入れて登録する。  
`(A, 4130001, NULL)`  

引越しを行なったタイミングで、現住所の情報を更新する。  
`(A, 4130001, NULL) -> (A, 4130001, 4130002)`  
さらに、引越し先の住所を以下のようにして登録する。  
`(A, 4130002, NULL)`  

このように履歴を保存することで、Aさんは次のように引越ししたことが分かる。  
`4130001 -> 4130002 -> 4130003`  

こういうものを隣接リストモデルと呼称する。  

このテーブルから一番古い住所を見つけるには、再帰共通表式、を使う。  

```sql
WITH Explosion (name, pcode, new_pcode, depth)
AS
   (SELECT name, pcode, new_pcode, 1
      FROM PostalHistory
	 WHERE name = 'A' 
	  AND
	 new_pcode IS NULL -- 探索の開始点
	UNION ALL
	SELECT Child.name, Child.pcode, Child.new_pcode, depth + 1
	  FROM Explosion Parent, PostalHistory Child
	 WHERE Parent.pcode = Child.new_pcode
	  AND
	 Parent.name = Child.name)
-- メインのSQL
SELECT name, pcode, new_pcode
   FROM Explosion
  WHERE depth = (SELECT MAX(depth) FROM Explosion);
```

共通表式は、Aさんの現住所(new_pcode列がNULL)から出発し、チェーンをたどって過去の住所を網羅する。  
その中で一番古い住所は、再帰レベルが最も深い行。これをdepthで計算している。  

まだこれもしっくり来ない…。  

### 入れ子集合モデル  

SQLにおける階層構造の表現方法は大きく3つある。  
1. 隣接リストモデル
  RDB誕生前からあった階層構造の表現方法。伝統的なもの。郵便の履歴管理がそれにあたる。
2. 入れ子集合モデル
  各行のデータを集合(円)とみなして、階層構造を集合の入れ子関係で表現する。
3. 経路列挙モデル
  更新がほとんど発生しないケースで威力を発揮する。
  

入れ子集合モデルの例  

```sql
CREATE TABLE PostalHistory2  
(  
   name  CHAR(1),  
   pcode CHAR(7),  
   lft   REAL NOT NULL,  
   rgt   REAL NOT NULL,  
   CONSTRAINT pk_name_pcode2 PRIMARY KEY(name, pcode),  
   CONSTRAINT uq_name_lft UNIQUE (name, lft),  
   CONSTRAINT uq_name_rgt UNIQUE (name, rgt),  
   CHECK(lft < rgt)  
);  

INSERT INTO PostalHistory2 VALUES ('A', '4130001', 0,   27);  
INSERT INTO PostalHistory2 VALUES ('A', '4130002', 9,   18);  
INSERT INTO PostalHistory2 VALUES ('A', '4130103', 12,  15);  
INSERT INTO PostalHistory2 VALUES ('B', '4130041', 0,   27);  
INSERT INTO PostalHistory2 VALUES ('C', '4103213', 0,   27);  
INSERT INTO PostalHistory2 VALUES ('C', '4380824', 9,   18);  
commit;
```

これは、郵便番号のデータを数直線上に存在する円として考える。  
lft, rgtは、円の左端と右端の座標。  
引越しするたびに、新しい郵便番号が古い郵便番号の中に含まれる形で追加される。  


新たに挿入する郵便番号の座標は、外側の円の左端と右端の座標を使って決められる。  
左端座標をpleft、右端座標をprightとすると、次の数式で計算できる。  

```
左端座標 = (plft * 2 + prgh) / 3
右端座標 = (plft + prght * 2) /3
```


`(/ (+ (* 0 2) 27) 3) ;; 9`
`(/ (+ 0 (* 27 2)) 3) ;; 18`

plft, prghtによって与えられた区間を3つの区間に分割する2点の座標を求めている。  
実装の許す精度の範囲であればいくらでも入れ子を深く出来る。  

この入れ子集合のモデルで、Aさんの一番外側の円を求める。(一番古い住所を求める)  
一番外側ということは、他のどの円にも含まれない円ということ。  

```sql
-- 外側の円をPH1、内側をPH2とする。

SELECT name,
       pcode
   FROM PostalHistory2 PH1
 WHERE name = 'A'
   AND NOT EXISTS (SELECT * 
                      FROM PostalHistory2 PH2
	                 WHERE PH2.name = 'A'
                      AND  PH1.lft > PH2.lft);
```
