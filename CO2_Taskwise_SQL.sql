-- Standalone SQLite 3 demonstration
-- Run in an empty connection. Small fixtures are not the original benchmark.

-- SETUP (printed under Task 8 in the assignment)
PRAGMA foreign_keys = ON;
CREATE TABLE Sender(SenderID INTEGER PRIMARY KEY,
 SenderName TEXT NOT NULL,RouteGroup TEXT NOT NULL);
CREATE TABLE Service(ServiceID INTEGER PRIMARY KEY,
 ServiceCode TEXT NOT NULL UNIQUE,ServiceName TEXT NOT NULL,
 VolumeWeight NUMERIC NOT NULL CHECK(VolumeWeight>0));
CREATE TABLE Coordinator(CoordinatorID INTEGER PRIMARY KEY,
 CoordinatorName TEXT NOT NULL,Hub TEXT NOT NULL);
CREATE TABLE BandFactor(ServiceBand TEXT PRIMARY KEY,
 RouteFactor NUMERIC NOT NULL CHECK(RouteFactor>0));
CREATE TABLE CompletionPolicy(Completion INTEGER PRIMARY KEY
 CHECK(Completion BETWEEN 0 AND 100),
 ServiceBand TEXT NOT NULL REFERENCES BandFactor(ServiceBand));
CREATE TABLE Assignment(SenderID INTEGER NOT NULL REFERENCES Sender,
 ServiceID INTEGER NOT NULL REFERENCES Service,
 CoordinatorID INTEGER NOT NULL REFERENCES Coordinator,
 PRIMARY KEY(SenderID,ServiceID));
CREATE TABLE Observation(SenderID INTEGER NOT NULL,
 ServiceID INTEGER NOT NULL,DispatchWave INTEGER NOT NULL,
 Completion INTEGER NOT NULL REFERENCES CompletionPolicy,
 CHECK(Completion BETWEEN 0 AND 100),
 PRIMARY KEY(SenderID,ServiceID,DispatchWave),
 FOREIGN KEY(SenderID,ServiceID) REFERENCES Assignment);
INSERT INTO Sender VALUES (1,'Sender A','G1'),(2,'Sender B','G1');
INSERT INTO Service VALUES
 (1,'EXP','Express',2),(2,'STD','Standard',1);
INSERT INTO Coordinator VALUES (1,'Anu','H1'),(2,'Ravi','H1');
INSERT INTO BandFactor VALUES ('LOW',0.8),('HIGH',1.0);
WITH RECURSIVE n(x) AS (
 VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<100)
INSERT INTO CompletionPolicy SELECT x,
 CASE WHEN x<39 THEN 'LOW' ELSE 'HIGH' END FROM n;
INSERT INTO Assignment VALUES (1,1,1),(1,2,1),(2,1,2),(2,2,2);
INSERT INTO Observation VALUES
 (1,1,1,20),(1,1,2,30),(1,1,3,35),
 (1,1,4,60),(1,2,4,50),(2,1,4,90),(2,2,4,95);
CREATE TABLE Handover_Flat AS
SELECT s.SenderID,s.SenderName,s.RouteGroup,
 v.ServiceID,v.ServiceCode,v.ServiceName,v.VolumeWeight,
 c.CoordinatorID,c.CoordinatorName,c.Hub,
 o.DispatchWave,o.Completion,p.ServiceBand,f.RouteFactor
FROM Observation o JOIN Sender s USING(SenderID)
JOIN Service v USING(ServiceID)
JOIN Assignment a USING(SenderID,ServiceID)
JOIN Coordinator c USING(CoordinatorID)
JOIN CompletionPolicy p USING(Completion)
JOIN BandFactor f USING(ServiceBand);
CREATE UNIQUE INDEX flat_key
 ON Handover_Flat(SenderID,ServiceID,DispatchWave);
CREATE TABLE Partial_Observation AS
SELECT SenderID,ServiceID,DispatchWave,Completion,
 CoordinatorID,CoordinatorName,Hub,ServiceBand,RouteFactor
FROM Handover_Flat;

-- TASK 1
-- Compare where the same service description is stored.
SELECT ServiceID,COUNT(*) AS repeated_rows
FROM Handover_Flat GROUP BY ServiceID;
SELECT ServiceID,ServiceName FROM Service;
SELECT sql FROM sqlite_master
WHERE name IN ('flat_key','Assignment','Observation','Service');

-- TASK 2
-- Data checks can falsify an FD; business rules establish it.
SELECT SenderID FROM Handover_Flat GROUP BY SenderID
HAVING COUNT(DISTINCT SenderName)>1
 OR COUNT(DISTINCT RouteGroup)>1;
SELECT ServiceID FROM Handover_Flat GROUP BY ServiceID
HAVING COUNT(DISTINCT ServiceCode)>1
 OR COUNT(DISTINCT ServiceName)>1
 OR COUNT(DISTINCT VolumeWeight)>1;
SELECT SenderID,ServiceID FROM Handover_Flat
GROUP BY SenderID,ServiceID
HAVING COUNT(DISTINCT CoordinatorID)>1;
SELECT Completion FROM Handover_Flat GROUP BY Completion
HAVING COUNT(DISTINCT ServiceBand)>1;

-- TASK 3
-- Validate both candidate keys on the demonstration state.
SELECT SenderID,ServiceID,DispatchWave,COUNT(*)
FROM Handover_Flat GROUP BY SenderID,ServiceID,DispatchWave
HAVING COUNT(*)>1;
SELECT SenderID,ServiceCode,DispatchWave,COUNT(*)
FROM Handover_Flat GROUP BY SenderID,ServiceCode,DispatchWave
HAVING COUNT(*)>1;
-- Scope-to-name implication follows through CoordinatorID.
SELECT a.SenderID,a.ServiceID,c.CoordinatorName
FROM Assignment a JOIN Coordinator c USING(CoordinatorID);
-- This supports the derivation; it does not replace closure proof.

-- TASK 4
-- One-copy editing creates a flat update anomaly.
SAVEPOINT anomaly;
UPDATE Handover_Flat SET ServiceName='Edited copy'
WHERE SenderID=1 AND ServiceID=1 AND DispatchWave=1;
SELECT ServiceID,COUNT(DISTINCT ServiceName) AS names
FROM Handover_Flat GROUP BY ServiceID HAVING COUNT(DISTINCT ServiceName)>1;
ROLLBACK TO anomaly;
RELEASE anomaly;
-- Master insertion needs no invented observation.
SAVEPOINT catalog_test;
INSERT INTO Service VALUES (3,'NEW','New unused service',1);
SELECT * FROM Service WHERE ServiceID=3;
ROLLBACK TO catalog_test;
RELEASE catalog_test;

-- TASK 5
-- Inspect determinant keys in the BCNF decomposition.
PRAGMA table_info(Assignment);
PRAGMA table_info(Observation);
PRAGMA index_list(Service);
-- Reconstruct the policy consequence from its determinant.
SELECT o.SenderID,o.ServiceID,o.DispatchWave,
 o.Completion,p.ServiceBand,f.RouteFactor
FROM Observation o JOIN CompletionPolicy p USING(Completion)
JOIN BandFactor f USING(ServiceBand);

-- TASK 6
-- Lossless reconstruction equals the full flat projection.
CREATE VIEW Reconstructed AS
SELECT s.SenderID,s.SenderName,s.RouteGroup,
 v.ServiceID,v.ServiceCode,v.ServiceName,v.VolumeWeight,
 c.CoordinatorID,c.CoordinatorName,c.Hub,
 o.DispatchWave,o.Completion,p.ServiceBand,f.RouteFactor
FROM Observation o JOIN Sender s USING(SenderID)
JOIN Service v USING(ServiceID)
JOIN Assignment a USING(SenderID,ServiceID)
JOIN Coordinator c USING(CoordinatorID)
JOIN CompletionPolicy p USING(Completion)
JOIN BandFactor f USING(ServiceBand);
SELECT * FROM Handover_Flat EXCEPT SELECT * FROM Reconstructed;
SELECT * FROM Reconstructed EXCEPT SELECT * FROM Handover_Flat;
-- Independent 4NF child facts; no Cartesian product is stored.
CREATE TABLE ServiceMode(ServiceID INTEGER REFERENCES Service,
 Mode TEXT,PRIMARY KEY(ServiceID,Mode));
CREATE TABLE ServiceDocument(ServiceID INTEGER REFERENCES Service,
 DocumentType TEXT,PRIMARY KEY(ServiceID,DocumentType));
-- 5NF under the explicitly stated three-pair approval rule.
CREATE TABLE OperatorItem(Operator INTEGER,Item INTEGER,
 PRIMARY KEY(Operator,Item));
CREATE TABLE OperatorChannel(Operator INTEGER,Channel TEXT,
 PRIMARY KEY(Operator,Channel));
CREATE TABLE ItemChannel(Item INTEGER,Channel TEXT,
 PRIMARY KEY(Item,Channel));
CREATE VIEW Approved AS
SELECT a.Operator,a.Item,b.Channel FROM OperatorItem a
JOIN OperatorChannel b ON a.Operator=b.Operator
JOIN ItemChannel c ON c.Item=a.Item AND c.Channel=b.Channel;

-- TASK 7
-- Q1a Sender 1 observations in wave 4.
SELECT ServiceID,Completion FROM Observation
WHERE SenderID=1 AND DispatchWave=4;
-- Q1b Weighted adjusted index.
SELECT SUM(o.Completion*v.VolumeWeight*f.RouteFactor)*1.0
 /NULLIF(SUM(v.VolumeWeight),0) AS AdjustedIndex
FROM Observation o JOIN Service v USING(ServiceID)
JOIN CompletionPolicy p USING(Completion)
JOIN BandFactor f USING(ServiceBand)
WHERE o.SenderID=1 AND o.DispatchWave=4;
-- Q2 At least one >=39 observation for every required service.
-- The fixture assigns every catalog service to each group.
SELECT s.SenderID FROM Sender s WHERE NOT EXISTS (
 SELECT 1 FROM Service v WHERE NOT EXISTS (
  SELECT 1 FROM Observation o WHERE o.SenderID=s.SenderID
  AND o.ServiceID=v.ServiceID AND o.Completion>=39));
-- Q3 Observed services with no low value in wave 4.
SELECT v.ServiceID FROM Service v WHERE EXISTS (
 SELECT 1 FROM Observation o WHERE o.ServiceID=v.ServiceID
 AND o.DispatchWave=4) AND NOT EXISTS (
 SELECT 1 FROM Observation o WHERE o.ServiceID=v.ServiceID
 AND o.DispatchWave=4 AND o.Completion<39);
-- Q4 Coordinator mean below the observation-weighted hub mean.
WITH facts AS (
 SELECT c.CoordinatorID,c.Hub,o.Completion
 FROM Observation o JOIN Assignment a USING(SenderID,ServiceID)
 JOIN Coordinator c USING(CoordinatorID)),
 cm AS (SELECT CoordinatorID,Hub,AVG(Completion) AS MeanValue
 FROM facts GROUP BY CoordinatorID,Hub),
 hm AS (SELECT Hub,AVG(Completion) AS HubMean
 FROM facts GROUP BY Hub)
SELECT cm.*,hm.HubMean FROM cm JOIN hm USING(Hub)
WHERE cm.MeanValue<hm.HubMean;
-- Q5 Low completion in at least three distinct waves.
SELECT SenderID FROM Observation WHERE Completion<39
GROUP BY SenderID HAVING COUNT(DISTINCT DispatchWave)>=3;

-- TASK 8
-- The complete setup precedes this block.
CREATE INDEX observation_lookup
 ON Observation(SenderID,DispatchWave,ServiceID);
PRAGMA foreign_key_check;
SELECT name,sql FROM sqlite_master
WHERE name IN ('Service','Observation','Assignment');
-- Use Task 7 Q1-Q5 as the five SQL operational tests.

-- TASK 9
SELECT 'flat' AS design,COUNT(*) AS rows FROM Handover_Flat
UNION ALL SELECT 'partial',COUNT(*) FROM Partial_Observation
UNION ALL SELECT 'observations',COUNT(*) FROM Observation;
SELECT ServiceID,COUNT(*) AS update_rows FROM Handover_Flat
GROUP BY ServiceID;
PRAGMA page_count;
PRAGMA page_size;
-- These PRAGMAs describe this whole demo database, not a design.
-- Use an external timer for repeated runs; do not invent timings.

-- TASK 10
-- Compare repeated updates with the authoritative master edit.
SAVEPOINT compare_updates;
UPDATE Handover_Flat SET ServiceName='Express revised'
WHERE ServiceID=1;
SELECT changes() AS flat_rows_touched;
UPDATE Service SET ServiceName='Express revised' WHERE ServiceID=1;
SELECT changes() AS normalized_rows_touched;
ROLLBACK TO compare_updates;
RELEASE compare_updates;
EXPLAIN QUERY PLAN SELECT * FROM Observation
WHERE SenderID=1 AND DispatchWave=4;

-- TASK 11
-- The recommended schema keeps descriptions in master tables.
SELECT v.ServiceCode,v.ServiceName,COUNT(o.SenderID) AS observations
FROM Service v LEFT JOIN Observation o USING(ServiceID)
GROUP BY v.ServiceID,v.ServiceCode,v.ServiceName;
PRAGMA foreign_key_check;

-- TASK 12
-- A: convert the changed traffic assumption to a planning rate.
SELECT 55000.0/3600 AS mean_requests_per_second;
-- B: measure the original indexed path separately.
EXPLAIN QUERY PLAN SELECT * FROM Observation
WHERE SenderID=1 AND DispatchWave=4;
-- C: atomically build a consistent demonstration read projection.
CREATE TABLE ReadCard(SenderID INTEGER REFERENCES Sender,
 DispatchWave INTEGER,SummaryIndex NUMERIC NOT NULL,
 SourceVersion INTEGER NOT NULL,RefreshedAt TEXT NOT NULL,
 PRIMARY KEY(SenderID,DispatchWave));
BEGIN IMMEDIATE;
INSERT INTO ReadCard
SELECT o.SenderID,o.DispatchWave,
 SUM(o.Completion*v.VolumeWeight*f.RouteFactor)*1.0
 /SUM(v.VolumeWeight),1,'2026-11-02T00:00:00Z'
FROM Observation o JOIN Service v USING(ServiceID)
JOIN CompletionPolicy p USING(Completion)
JOIN BandFactor f USING(ServiceBand)
GROUP BY o.SenderID,o.DispatchWave;
COMMIT;
-- D: discrepancy test against the current source snapshot.
WITH truth AS (
 SELECT o.SenderID,o.DispatchWave,
 SUM(o.Completion*v.VolumeWeight*f.RouteFactor)*1.0
 /SUM(v.VolumeWeight) AS Expected
 FROM Observation o JOIN Service v USING(ServiceID)
 JOIN CompletionPolicy p USING(Completion)
 JOIN BandFactor f USING(ServiceBand)
 GROUP BY o.SenderID,o.DispatchWave)
SELECT t.* FROM truth t LEFT JOIN ReadCard r
 USING(SenderID,DispatchWave)
WHERE r.SenderID IS NULL OR ABS(t.Expected-r.SummaryIndex)>0.000001;
SELECT * FROM ReadCard WHERE SenderID=1 AND DispatchWave=4;
-- Scheduler and production snapshot/version coordination remain external.
