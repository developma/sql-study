CREATE TABLE Address (
  name VARCHAR(32) NOT NULL,
  phone VARCHAR(32),
  address VARCHAR(32) NOT NULL,
  sex CHAR(4) NOT NULL,
  age INTEGER NOT NULL,
  PRIMARY KEY (name)
);

INSERT INTO Address VALUES ('田中', '090-1111-XXXX', '東京都', '男', 30);
INSERT INTO Address VALUES ('斎藤', '090-0000-XXXX', '神奈川県', '女', 32);
INSERT INTO Address VALUES ('鈴木', '080-3333-XXXX', '東京都', '男', 55);
INSERT INTO Address VALUES ('佐藤', '090-2842-XXXX', '青森県', '男', 19);
INSERT INTO Address VALUES ('太田', NULL, '大分県', '男', 20);
INSERT INTO Address VALUES ('木村', '080-9876-XXXX', '三重県', '女', 25);
INSERT INTO Address VALUES ('上田', NULL, '徳島県', '女', 83);
INSERT INTO Address VALUES ('小林', NULL, '沖縄県', '女', 43);
INSERT INTO Address VALUES ('吉田', '090-1922-XXXX', '広島県', '男', 60);
INSERT INTO Address VALUES ('前田', '090-0001-XXXX', '高知県', '男', 9);
commit;

-- Get all data from the table.
SELECT name, phone, address, sex, age FROM Address;

-- search specify data from the table using WHERE.
SELECT name, phone, address, sex, age
       FROM Address
       WHERE address = '東京都';

SELECT name, phone, address, sex, age
       FROM Address
       WHERE age >= 30;

SELECT name, phone, address, sex, age
       FROM Address
       WHERE address <> '東京都';

SELECT name, phone, address, sex, age
       FROM Address
       WHERE address = '東京都'
       AND
       age >= 30;

SELECT name, phone, address, sex, age
       FROM Address
       WHERE address = '東京都'
       OR
       age >= 30;

SELECT name, phone, address, sex, age
       FROM Address
       WHERE address IN ('東京都', '神奈川県');

SELECT name, phone, address, sex, age
       FROM Address
       WHERE phone IS NULL;

SELECT sex, COUNT(*)
       FROM Address
       GROUP BY sex;

SELECT address, COUNT(*)
       FROM Address
       GROUP BY address;

SELECT COUNT(*)
       FROM Address
       GROUP BY ( );

SELECT address, COUNT(*)
       FROM Address
       GROUP BY address
       HAVING COUNT(*) = 1;

SELECT name, phone, address, sex, age
       FROM Address
       ORDER BY age DESC;

CREATE VIEW CountAddress (
  v_address,
  cnt
) AS
SELECT address, COUNT(*)
       FROM Address
       GROUP BY address;

SELECT v_address, cnt FROM CountAddress;

SELECT v_address, cnt
       FROM (SELECT address AS v_address, COUNT(*) AS cnt
       	    	    FROM Address
		    GROUP BY address);

CREATE TABLE Address2 (
  name VARCHAR(32) NOT NULL,
  phone VARCHAR(32),
  address VARCHAR(32) NOT NULL,
  sex CHAR(4) NOT NULL,
  age INTEGER NOT NULL,
  PRIMARY KEY (name)
);

INSERT INTO Address2 VALUES ('田中', '090-1111-XXXX', '東京都', '男', 30);
INSERT INTO Address2 VALUES ('上野', '080-7777-XXXX', '千葉県', '女', 20);
INSERT INTO Address2 VALUES ('太田', NULL, '大分県', '男', 20);
INSERT INTO Address2 VALUES ('武田', '080-0207-XXXX', '福島県', '男', 34);
INSERT INTO Address2 VALUES ('吉田', '090-1983-XXXX', '福島県', '男', 7);
commit;

SELECT name
       FROM Address
       WHERE name IN (SELECT name FROM Address2);

SELECT name, address,
       CASE
         WHEN address = '東京都' THEN '関東'
  	 WHEN address = '千葉県' THEN '関東'
	 WHEN address = '神奈川県' THEN '関東'
	 WHEN address = '三重県' THEN '中部'
	 WHEN address = '大分県' THEN '九州'
	 WHEN address = '徳島県' THEN '四国'
	 ELSE NULL
       END AS district
       FROM Address;

SELECT * FROM Address
       UNION
       SELECT * FROM Address2;

SELECT * FROM Address
       UNION ALL
       SELECT * FROM Address2;

SELECT * FROM Address
       INTERSECT
       SELECT * FROM Address2;

SELECT * FROM Address
       MINUS
       SELECT * FROM Address2;

SELECT address, COUNT(*) OVER(PARTITION BY address)
       FROM Address;

SELECT name,
       age,
       RANK() OVER(ORDER BY age DESC) AS rnk
       FROM Address;

DELETE FROM Address;

DELETE From Address where address = '大分県';

UPDATE Address SET phone = '090-XXXX-0000'
       WHERE name = '小林';

UPDATE Address SET phone = 'XXX-XXXX-XXXX'
       	           age = 11
	WHERE name = '前田';


     
