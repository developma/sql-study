# サブクエリ  

SQLの中で作成される一時的なテーブル。これを永続化したものがビュー。  

テーブル、ビュー、サブクエリの違いを以下に示す。  

- テーブル: 永続的かつデータを保存する
- ビュー: 永続的だがデータは保持しないため、アクセスのたびにSELECT文が実行される
- サブクエリ: 非永続的なのでスコープがSQL文の実行中に限られる

非機能、特にパフォーマンス的な観点でいうと、テーブルとサブクエリには大きな違いがある。  
たとえば、サブクエリ(またはビュー)は同じデータを保持する場合であっても、テーブルに比べるとパフォーマンスが悪い傾向がある。  

ここでは、サブクエリを使う際に引き起こされる性能問題のパターンを確認し、どのような点に気をつけるべきか記載する。  

## サブクエリが引き起こす弊害  

### サブクエリの問題点  

サブクエリの性能的な問題は、サブクエリが実体的なデータを持たないことに起因する。  
それにより、次の3つの問題が生じる。  

- サブクエリの計算コストが上乗せされる
  サブクエリにアクセスするたびにSELECT文を作成してデータを作る必要がある。  
  これにより、そのコストがかかる。ましてや、中身が複雑であれば尚更である。  
- データのI/Oコストがかかる
  計算した結果はどこかに保持するため書きこむ必要がある。  
  データ量が大きい場合など、DBMSがファイルに書き出すことを選択してしまったためにTEMP落ちになる場合もある。  
- 最適化を受けられない
  テーブルは明示的に制約やインデックスを作れるが、サブクエリにはそのようなメタ情報が存在しない。  
  オプティマイザがクエリを解析するために必要な情報が、サブクエリの検索結果からは得られない。

こうした問題点から、サブクエリで複雑な計算をしたり、結果のサイズが大きくなる場合の性能リスクを考慮する必要がある。  

### サブクエリ・パラノイア  

顧客の購入明細を記録するテーブルがある。連番には顧客の古い購入ほど小さな値が振られている。  
ここから、顧客ごとに最小の連番の金額を求める。つまり、顧客の一番古い購入履歴を求める。  

```sql
CREATE TABLE Receipts
(cust_id   CHAR(1) NOT NULL, 
 seq   INTEGER NOT NULL, 
 price   INTEGER NOT NULL, 
     PRIMARY KEY (cust_id, seq));

INSERT INTO Receipts VALUES ('A',   1   ,500    );
INSERT INTO Receipts VALUES ('A',   2   ,1000   );
INSERT INTO Receipts VALUES ('A',   3   ,700    );
INSERT INTO Receipts VALUES ('B',   5   ,100    );
INSERT INTO Receipts VALUES ('B',   6   ,5000   );
INSERT INTO Receipts VALUES ('B',   7   ,300    );
INSERT INTO Receipts VALUES ('B',   9   ,200    );
INSERT INTO Receipts VALUES ('B',   12  ,1000   );
INSERT INTO Receipts VALUES ('C',   10  ,600    );
INSERT INTO Receipts VALUES ('C',   20  ,100    );
INSERT INTO Receipts VALUES ('C',   45  ,200    );
INSERT INTO Receipts VALUES ('C',   70  ,50     );
INSERT INTO Receipts VALUES ('D',   3   ,2000   );
commit;
```

連番の最小値が顧客により変わる。  
Aなら1だが、Bなら5、Cなら10、Dなら3となる。  
この場合、最小値を動的に求める必要がある。  

#### サブクエリを使った場合  

顧客ごとに最小の連番を保持するサブクエリを作り、本体のテーブルと結合する。  

```sql
SELECT 
   R1.cust_id,
   R1.seq,
   R1.price
  FROM Receipts R1
         INNER JOIN
		  (SELECT cust_id, MIN(seq) AS min_seq
		      FROM Receipts
			 GROUP BY cust_id) R2
    ON R1.cust_id = R2.cust_id
   AND R1.seq = R2.min_seq;
```

このSQL文はパフォーマンスが悪い。その理由は以下。  

1. オーバヘッドが生じる
   一時的な領域に結果が書き出される。
2. 最適化が受けられない
   サブクエリはインデックスや制約を保持していない。
3. 実行計画変動のリスクが発生する
   結合を必要とするためコストが高く、また実行計画が変動する可能性がある。
4. 本体テーブルへのスキャンが2回発生する
   そのままの意味。
   
#### 相関サブクエリは解にならない  

以下の相関サブクエリを利用しても本体テーブルへのアクセスは2回必要になる。  

```sql
SELECT cust_id, seq, price 
  FROM Receipts R1
 WHERE seq = (SELECT MIN(seq)
                FROM Receipts R2
			   WHERE R1.cust_id = R2.cust_id);
```

#### ウィンドウ関数で結合をなくす  

前述SQL文の大きな改善ポイントは、本体テーブルへのアクセスを1回に減らすこと。  
SQLチューニングの要諦は、1にI/O、2にI/O、最後にI/Oにつきる。  

```sql
SELECT cust_id, seq, price
  FROM (SELECT cust_id, seq, price, ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY seq) AS row_seq
		 FROM Receipts) WORK
 WHERE WORK.row_seq = 1;
 ```

`ROW_NUMBER()`で行に連番を振り、常に最小値に1を振ることで、seq列の最小値が不確定という問題に対処出来る。  
クエリもシンプルになり、可読性も上がる。  

### 長期的な視点でのリスクマネジメント  

ウィンドウ関数がどの程度パフォーマンス向上するかは、使用するDBMSやDBサーバの情報などの要因により左右されるため、  
一概には言えない。  

しかし、ストレージのI/Oを減らすことがSQLチューニングにおける基本原則である。  
また、結合を消去することは、パフォーマンス向上だけでなく性能の安定性を確保出来ることにも繋がる。  

結合クエリには2つの不確定要素がある。  

- 結合アルゴリズムの変動リスク
- 環境に起因する遅延リスク
  インデックス、メモリ、パラメータなど
  
相関サブクエリも、実行計画としては結合とほぼ同じものになるため、上記不確定要素で記載したリスクが同様に該当する。  

#### アルゴリズムの変動リスク  

結合アルゴリズムは、Nested Loops, Hash, Sort Mergeがあり、どれが選ばれるかはオプティマイザが自動的に決定する。  
システム運用中にレコード件数が増えたために実行計画が変動することがある。  

#### 環境起因の遅延リスク  

Nested Loopsの内部表の結合キーにインデックスが存在すると、性能が大きく改善する。  
また、Sort MergeやHashの場合にTEMP落ちが発生する場合、作業メモリを増やすことで性能改善出来る。  
しかし、上記対策がいつまでも有効とは限らない。  

結合を使うことは長期的に見て、考慮すべき性能リスクを増やすことになる。  
`結合クエリは、性能が非線形で劣化するリスクがある`  

よって、次のことに留意しなければならない。
- シンプルな実行計画になるようにする
- 機能だけでなく非機能を担保する

### サブクエリ・パラノイア(応用)  

Receiptsテーブルを使い、顧客ごとの連番の最小値を持つ行を求めた。  
次は、最大値の行を求め、両者のpriceの差分を求める。  

#### サブクエリ版  

```sql
SELECT TMP_MIN.cust_id,
       TMP_MIN.price - TMP_MAX.price AS diff
-- 最小値のseqを持つテーブルと、最大値のseqを持つテーブルを作成し、JOINさせる。 
　FROM (SELECT R1.cust_id, R1.seq, R1.price
          FROM Receipts R1
                 INNER JOIN
                  (SELECT cust_id, MIN(seq) AS min_seq
                     FROM Receipts
                    GROUP BY cust_id) R2
            ON R1.cust_id = R2.cust_id
           AND R1.seq = R2.min_seq) TMP_MIN
       INNER JOIN
       (SELECT R3.cust_id, R3.seq, R3.price
          FROM Receipts R3
                 INNER JOIN
                  (SELECT cust_id, MAX(seq) AS min_seq
                     FROM Receipts
                    GROUP BY cust_id) R4
            ON R3.cust_id = R4.cust_id
           AND R3.seq = R4.min_seq) TMP_MAX
    ON TMP_MIN.cust_id = TMP_MAX.cust_id;
```

これではパフォーマンスが悪くなる。  

#### 行間比較でも結合は必要ない  

ウィンドウ関数に加え、CASE式も使う。  

```sql
SELECT cust_id,
       SUM(CASE WHEN min_seq = 1 THEN price ELSE 0 END) - SUM(CASE WHEN max_seq = 1 THEN price ELSE 0 END) AS diff
  FROM (SELECT cust_id,
               price,
               ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY seq) AS min_seq,
               ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY seq DESC) AS max_seq
          FROM Receipts) WORK
 WHERE WORK.min_seq = 1
    OR WORK.max_seq = 1
 GROUP BY cust_id;
```

これならサブクエリはWORKの1つだけで、結合も発生していない。  
SUM関数の中でのCASE文にトリックがある。  

WORKビューの時点では、最大値と最小値は異なる行として存在している。  
異なる行同士の引き算は出来ないので、GROUP BY cust_idで顧客単位に集約している。  

#### 困難は分割するな  

サブクエリそのものは悪ではない。  
サブクエリでなければ解決しない問題もあるだろうし、最終的にサブクエリを消すことになるとしても、  
最初の突破口としてサブクエリを使った解を組み立ててみる、というのは有効な方法。  

サブクエリを使うことで問題を分割して考えることが容易になるため、思考の補助線としては有効。  

## サブクエリの積極的意味  

サブクエリを使ったほうがパフォーマンス良くなるケースは?  
そもそもサブクエリが性能面で重要になってくるのは、結合が関係している部分。  
結合対象の行を絞ること、オプティマイザが結合アルゴリズムをうまく判断出来るように演算順序を明示するようなコーディングをすることが重要。  

### 結合と集約の順序  

会社と事業所を管理するテーブルがある。  

```sql
CREATE TABLE Companies
(co_cd      CHAR(3) NOT NULL, 
 district   CHAR(1) NOT NULL, 
     CONSTRAINT pk_Companies PRIMARY KEY (co_cd));

INSERT INTO Companies VALUES('001',	'A');	
INSERT INTO Companies VALUES('002',	'B');	
INSERT INTO Companies VALUES('003',	'C');	
INSERT INTO Companies VALUES('004',	'D');	

CREATE TABLE Shops
(co_cd      CHAR(3) NOT NULL, 
 shop_id    CHAR(3) NOT NULL, 
 emp_nbr    INTEGER NOT NULL, 
 main_flg   CHAR(1) NOT NULL, 
     PRIMARY KEY (co_cd, shop_id));

INSERT INTO Shops VALUES('001',	'1',   300,  'Y');
INSERT INTO Shops VALUES('001',	'2',   400,  'N');
INSERT INTO Shops VALUES('001',	'3',   250,  'Y');
INSERT INTO Shops VALUES('002',	'1',   100,  'Y');
INSERT INTO Shops VALUES('002',	'2',    20,  'N');
INSERT INTO Shops VALUES('003',	'1',   400,  'Y');
INSERT INTO Shops VALUES('003',	'2',   500,  'Y');
INSERT INTO Shops VALUES('003',	'3',   300,  'N');
INSERT INTO Shops VALUES('003',	'4',   200,  'Y');
INSERT INTO Shops VALUES('004',	'1',   999,  'Y');
commit;
```

この2つのテーブルは、1:Nのオードソックスな親子関係(1つの会社に複数の事業所がある)を現わしている。  
会社ごとの主要事業所の従業員数を求めたい。

#### 結合を先にしてから集約する  

```sql
SELECT C.co_cd, C.district,
       SUM(emp_nbr) AS sum_emp
　FROM Companies C
         INNER JOIN
           Shops S
    ON C.co_cd = S.co_cd
 WHERE main_flg = 'Y'
 GROUP BY C.co_cd;
```

このSQL文うごかないー。

#### 集約を先にしてから結合する  

```sql
SELECT C.co_cd, C.district, sum_emp
　FROM Companies C
         INNER JOIN
          (SELECT co_cd,
                  SUM(emp_nbr) AS sum_emp
             FROM Shops
            WHERE main_flg = 'Y'
            GROUP BY co_cd) CSUM
    ON C.co_cd = CSUM.co_cd;
```

#### 結合か集約のどっちが先か?  

判断ポイントは結合の対象行数。  
最初(結合)の場合、会社テーブル(4行)、事業所テーブル(10行)となり、  
後者(集約)の場合、会社テーブル(4行)、CSUMテーブル(4行)となる。  

後者のCSUMテーブル(ビュー)が会社コードで集約されて4行になっており、  
結合コストを抑えられる。  

このサンプルが、会社テーブル(1000行)、事業所テーブル(500万行)、事業所テーブル(CSUM, 1000行)であれば、  
先に集約して結合対象の行を1000行に絞ることでコストを抑えられる。  

## まとめ  

- サブクエリは困難を分割出来る便利な道具だが、結合を増やすことでパフォーマンスを悪化させることもある
- SQLのパフォーマンスを決定する要因はとにかくI/O
- サブクエリと結合をウィンドウ関数で代替することでパフォーマンスを改善できる可能性がある
- サブクエリを使う場合は、結合対象のレコード数を事前に絞ることでパフォーマンスを改善できる可能性がある
