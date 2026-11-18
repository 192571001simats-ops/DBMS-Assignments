CREATE TABLE pool(id TEXT PRIMARY KEY, balance INTEGER CHECK(balance>=0));
INSERT INTO pool VALUES ('A',100),('B',60),('C',40);
CREATE TABLE receipt(id TEXT PRIMARY KEY);
CREATE TABLE run(n,skew,mode,cap,throughput,mean,p95,retries,cycles,blocked,queued,safe);
CREATE TABLE farm_day(farm,day,used,ceiling,PRIMARY KEY(farm,day));
INSERT INTO farm_day VALUES ('F1','2026-11-18',8,10);
INSERT INTO run VALUES (10,0,'serial',1,263.2,21.8,38,0,0,0,180,1);
INSERT INTO run VALUES (10,0,'lock',8,1000.0,6.5,10,0,0,19,8,1);
INSERT INTO run VALUES (10,0,'lock',2,476.2,12.9,21,0,0,3,88,1);
INSERT INTO run VALUES (10,0,'to',8,454.5,11.4,22,15,0,0,16,1);
INSERT INTO run VALUES (10,0,'none',8,1250.0,4.8,8,0,0,0,8,0);
INSERT INTO run VALUES (10,1,'serial',1,263.2,21.8,38,0,0,0,180,1);
INSERT INTO run VALUES (10,1,'lock',8,625.0,11.7,16,3,3,60,13,1);
INSERT INTO run VALUES (10,1,'lock',2,476.2,12.8,21,0,0,3,87,1);
INSERT INTO run VALUES (10,1,'to',8,294.1,18.6,34,21,0,0,64,1);
INSERT INTO run VALUES (10,1,'none',8,1250.0,4.8,8,0,0,0,8,0);
INSERT INTO run VALUES (50,0,'serial',1,235.8,107.0,206,0,0,0,5140,1);
INSERT INTO run VALUES (50,0,'lock',8,543.5,26.6,66,7,7,254,817,1);
INSERT INTO run VALUES (50,0,'lock',2,427.4,59.4,114,0,0,21,2735,1);
INSERT INTO run VALUES (50,0,'to',8,520.8,35.9,79,55,0,0,1354,1);
INSERT INTO run VALUES (50,0,'none',8,1515.2,15.3,28,0,0,0,549,0);
INSERT INTO run VALUES (50,1,'serial',1,235.8,107.0,206,0,0,0,5140,1);
INSERT INTO run VALUES (50,1,'lock',8,574.7,36.4,75,5,5,304,1269,1);
INSERT INTO run VALUES (50,1,'lock',2,416.7,60.2,116,1,1,23,2771,1);
INSERT INTO run VALUES (50,1,'to',8,301.2,66.1,149,84,0,0,2731,1);
INSERT INTO run VALUES (50,1,'none',8,1515.2,15.3,28,0,0,0,549,0);
INSERT INTO run VALUES (200,0,'serial',1,229.9,432.9,821,0,0,0,85700,1);
INSERT INTO run VALUES (200,0,'lock',8,657.9,103.7,183,35,35,641,19141,1);
INSERT INTO run VALUES (200,0,'lock',2,406.5,240.9,454,3,3,86,47206,1);
INSERT INTO run VALUES (200,0,'to',8,451.5,138.1,376,204,0,0,25828,1);
INSERT INTO run VALUES (200,0,'none',8,1652.9,57.0,107,0,0,0,10502,0);
INSERT INTO run VALUES (200,1,'serial',1,229.9,432.9,821,0,0,0,85700,1);
INSERT INTO run VALUES (200,1,'lock',8,399.2,172.5,389,63,63,1838,31500,1);
INSERT INTO run VALUES (200,1,'lock',2,397.6,239.0,456,5,5,81,46802,1);
INSERT INTO run VALUES (200,1,'to',8,291.5,277.8,639,352,0,0,53116,1);
INSERT INTO run VALUES (200,1,'none',8,1652.9,57.0,107,0,0,0,10502,0);
INSERT INTO run VALUES (1000,0,'serial',1,229.9,2172.8,4127,0,0,0,2168500,1);
INSERT INTO run VALUES (1000,0,'lock',8,815.7,475.8,974,151,151,3513,467342,1);
INSERT INTO run VALUES (1000,0,'lock',2,407.0,1181.5,2240,24,24,380,1176592,1);
INSERT INTO run VALUES (1000,0,'to',8,485.9,654.7,1765,994,0,0,645807,1);
INSERT INTO run VALUES (1000,0,'none',8,1766.8,279.4,529,0,0,0,274957,0);
INSERT INTO run VALUES (1000,1,'serial',1,229.9,2172.8,4127,0,0,0,2168500,1);
INSERT INTO run VALUES (1000,1,'lock',8,428.6,774.2,1707,228,228,9259,759281,1);
INSERT INTO run VALUES (1000,1,'lock',2,394.5,1218.0,2299,27,27,430,1212957,1);
INSERT INTO run VALUES (1000,1,'to',8,291.6,1363.2,3201,1731,0,0,1351144,1);
INSERT INTO run VALUES (1000,1,'none',8,1766.8,279.4,529,0,0,0,274957,0);
-- Task 1
SELECT id,balance FROM pool ORDER BY id;
-- Task 2
BEGIN;
INSERT INTO receipt VALUES ('K1');
UPDATE pool SET balance=balance-10 WHERE id='A';
UPDATE pool SET balance=balance+10 WHERE id='B';
COMMIT;
SELECT SUM(balance) AS conserved FROM pool;
-- Task 3
WITH edges(a,b) AS (VALUES (1,2),(2,1))
SELECT e.a,e.b FROM edges e JOIN edges f ON e.a=f.b AND e.b=f.a;
-- Task 4
WITH events(writer_commit,reader_read,reader_commit) AS (VALUES(3,2,4))
SELECT writer_commit<reader_commit AS recoverable,
 writer_commit<reader_read AS avoids_dirty_read FROM events;
-- Task 5
SELECT cap,cycles,blocked FROM run WHERE n=1000 AND skew=1 AND mode='lock';
-- Task 6
WITH attempt(ts,rts,wts) AS (VALUES(10,0,20),(10,20,0))
SELECT ts>=wts AS read_ok,ts>=MAX(rts,wts) AS write_ok FROM attempt;
-- Task 7
SELECT id,balance FROM pool ORDER BY id;
-- Task 8
SELECT mode,COUNT(*),SUM(safe) AS passed FROM run GROUP BY mode;
-- Task 9
SELECT mode,cap,throughput,mean,p95 FROM run WHERE n=1000 AND skew=1;
-- Task 10
SELECT skew,retries,cycles FROM run WHERE n=1000 AND mode='to';
-- Task 11
SELECT 8+268*180/2500.0 AS restart_seconds;
-- Task 12
UPDATE farm_day SET used=used+2 WHERE farm='F1' AND used+2<=ceiling;
UPDATE farm_day SET used=used+2 WHERE farm='F1' AND used+2<=ceiling;
SELECT changes() AS second_approval, used FROM farm_day;