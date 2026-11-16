-- Standalone SQLite 3 demonstration
-- Run in an empty connection. Small fixtures are not the original benchmark.

-- SETUP (printed under Task 8 in the assignment)
PRAGMA foreign_keys = ON;
CREATE TABLE person (
 id INTEGER PRIMARY KEY, given_name TEXT NOT NULL,
 family_name TEXT NOT NULL, email TEXT UNIQUE);
CREATE TABLE lender (
 id INTEGER PRIMARY KEY, person_id INTEGER UNIQUE
 REFERENCES person(id), name TEXT NOT NULL);
CREATE TABLE curator (
 id INTEGER PRIMARY KEY, person_id INTEGER NOT NULL UNIQUE
 REFERENCES person(id));
CREATE TABLE registrar (
 id INTEGER PRIMARY KEY, person_id INTEGER NOT NULL UNIQUE
 REFERENCES person(id));
CREATE TABLE collection_unit (
 id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE artifact (
 id INTEGER PRIMARY KEY, accession_code TEXT NOT NULL UNIQUE,
 unit_id INTEGER NOT NULL REFERENCES collection_unit(id),
 title TEXT NOT NULL, collection_type TEXT NOT NULL);
CREATE TABLE loan (
 id INTEGER PRIMARY KEY,
 lender_id INTEGER NOT NULL REFERENCES lender(id),
 registrar_id INTEGER NOT NULL REFERENCES registrar(id),
 start_date TEXT NOT NULL, due_date TEXT NOT NULL,
 return_date TEXT,
 CHECK(due_date >= start_date),
 CHECK(return_date IS NULL OR return_date >= start_date));
CREATE TABLE loan_object (
 id INTEGER PRIMARY KEY,
 loan_id INTEGER NOT NULL REFERENCES loan(id),
 artifact_id INTEGER NOT NULL REFERENCES artifact(id),
 insured_value NUMERIC NOT NULL CHECK(insured_value >= 0),
 UNIQUE(loan_id, artifact_id));
CREATE TABLE condition_report (
 id INTEGER PRIMARY KEY,
 loan_object_id INTEGER NOT NULL REFERENCES loan_object(id),
 report_date TEXT NOT NULL,
 report_type TEXT NOT NULL
 CHECK(report_type IN ('ARRIVAL','DURING','RETURN')),
 notes TEXT);
CREATE TABLE exhibition (
 id INTEGER PRIMARY KEY, name TEXT NOT NULL,
 curator_id INTEGER NOT NULL REFERENCES curator(id));
CREATE TABLE display_slot (
 exhibition_id INTEGER NOT NULL REFERENCES exhibition(id),
 slot_no INTEGER NOT NULL, room TEXT NOT NULL,
 PRIMARY KEY(exhibition_id, slot_no));
CREATE TABLE placement (
 id INTEGER PRIMARY KEY,
 loan_object_id INTEGER NOT NULL REFERENCES loan_object(id),
 exhibition_id INTEGER NOT NULL, slot_no INTEGER NOT NULL,
 placed_on TEXT NOT NULL, removed_on TEXT,
 FOREIGN KEY(exhibition_id,slot_no)
 REFERENCES display_slot(exhibition_id,slot_no),
 CHECK(removed_on IS NULL OR removed_on >= placed_on));
INSERT INTO person VALUES
 (1,'Anu','Rao','anu@example.test'),
 (2,'Ravi','Das','ravi@example.test');
INSERT INTO lender VALUES (1,1,'Anu Rao'),(2,NULL,'Museum Trust');
INSERT INTO curator VALUES (1,1);
INSERT INTO registrar VALUES (1,2);
INSERT INTO collection_unit VALUES (1,'Sculpture');
INSERT INTO artifact VALUES
 (1,'ACC001',1,'Bronze lamp','METAL'),
 (2,'ACC002',1,'Stone figure','STONE'),
 (3,'ACC003',1,'Wooden box','WOOD');
INSERT INTO loan VALUES
 (1,1,1,'2026-10-01','2026-11-01',NULL),
 (2,2,1,'2026-10-01','2026-12-01',NULL);
INSERT INTO loan_object VALUES
 (1,1,1,50000),(2,1,2,75000),(3,2,3,10000);
INSERT INTO condition_report VALUES
 (1,1,'2026-10-01','ARRIVAL','Intact'),
 (2,1,'2026-11-01','RETURN','Unchanged'),
 (3,3,'2026-10-01','ARRIVAL','Surface mark');
INSERT INTO exhibition VALUES (1,'Autumn Gallery',1);
INSERT INTO display_slot VALUES (1,1,'A'),(1,2,'A');
INSERT INTO placement VALUES
 (1,1,1,1,'2026-10-02',NULL);

-- TASK 1
-- Loan occurrences keep custody and evidence separate.
SELECT l.id AS loan_id, a.title, l.start_date, l.due_date,
       COUNT(r.id) AS condition_reports
FROM loan l JOIN loan_object x ON x.loan_id=l.id
JOIN artifact a ON a.id=x.artifact_id
LEFT JOIN condition_report r ON r.loan_object_id=x.id
GROUP BY l.id,a.id,a.title,l.start_date,l.due_date;
-- Shared identity supports a curator who is also a lender.
SELECT p.id,p.given_name,c.id AS curator_id,l.id AS lender_id
FROM person p JOIN curator c ON c.person_id=p.id
JOIN lender l ON l.person_id=p.id;

-- TASK 2
-- Inspect stable and owner-scoped keys.
PRAGMA table_info(artifact);
PRAGMA index_list(artifact);
PRAGMA table_info(display_slot);
-- A repeated exhibition name is legal; its ID remains distinct.
SELECT name,COUNT(*) AS exhibitions
FROM exhibition GROUP BY name;

-- TASK 3
-- Loans with no objects violate confirmation requirements.
SELECT l.id FROM loan l
LEFT JOIN loan_object x ON x.loan_id=l.id
GROUP BY l.id HAVING COUNT(x.id)=0;
-- Detect placements outside their custody interval.
SELECT p.id FROM placement p
JOIN loan_object x ON x.id=p.loan_object_id
JOIN loan l ON l.id=x.loan_id
WHERE p.placed_on<l.start_date OR p.placed_on>l.due_date
 OR (p.removed_on IS NOT NULL AND p.removed_on>l.due_date)
 OR (l.return_date IS NOT NULL AND
     COALESCE(p.removed_on,'9999-12-31')>l.return_date);
-- Three binary projections can invent a ternary fact.
WITH t(l,c,e) AS (VALUES(1,1,1),(1,2,2),(2,1,2)),
lc AS (SELECT DISTINCT l,c FROM t),
le AS (SELECT DISTINCT l,e FROM t),
ce AS (SELECT DISTINCT c,e FROM t)
SELECT lc.l,lc.c,le.e FROM lc
JOIN le ON le.l=lc.l
JOIN ce ON ce.c=lc.c AND ce.e=le.e
EXCEPT SELECT l,c,e FROM t;

-- TASK 4
-- Follow the ER path from exhibition to physical object.
SELECT e.id,e.name,s.slot_no,a.accession_code,a.title
FROM exhibition e
JOIN display_slot s ON s.exhibition_id=e.id
LEFT JOIN placement p ON p.exhibition_id=s.exhibition_id
 AND p.slot_no=s.slot_no AND p.removed_on IS NULL
LEFT JOIN loan_object x ON x.id=p.loan_object_id
LEFT JOIN artifact a ON a.id=x.artifact_id;
PRAGMA foreign_key_list(placement);

-- TASK 5
-- Overlapping PERSON roles share the same identity.
SELECT p.id,p.given_name,
 EXISTS(SELECT 1 FROM lender l WHERE l.person_id=p.id)
 AS is_lender,
 EXISTS(SELECT 1 FROM curator c WHERE c.person_id=p.id)
 AS is_curator,
 EXISTS(SELECT 1 FROM registrar r WHERE r.person_id=p.id)
 AS is_registrar
FROM person p;
-- Contact union: exactly one person or organisation target.
CREATE TABLE organization(id INTEGER PRIMARY KEY,name TEXT NOT NULL);
CREATE TABLE notification_contact (
 id INTEGER PRIMARY KEY,
 person_id INTEGER REFERENCES person(id),
 organization_id INTEGER REFERENCES organization(id),
 CHECK((person_id IS NOT NULL)+(organization_id IS NOT NULL)=1));

-- TASK 6
-- Multivalued phones become atomic child rows.
CREATE TABLE person_phone (
 person_id INTEGER NOT NULL REFERENCES person(id),
 phone TEXT NOT NULL, PRIMARY KEY(person_id,phone));
INSERT INTO person_phone VALUES (1,'9000000001'),(1,'9000000002');
SELECT p.given_name,pp.phone FROM person p
JOIN person_phone pp ON pp.person_id=p.id;
-- Derive time-dependent summaries instead of storing them.
SELECT id,CAST(julianday(due_date)-julianday('2026-11-02')
 AS INTEGER) AS days_to_due FROM loan;
SELECT x.id,COUNT(r.id) AS report_count
FROM loan_object x LEFT JOIN condition_report r
 ON r.loan_object_id=x.id GROUP BY x.id;

-- TASK 7
-- The associative relation supports multiple objects per loan.
SELECT l.id AS loan_id,COUNT(x.id) AS object_count
FROM loan l LEFT JOIN loan_object x ON x.loan_id=l.id
GROUP BY l.id;
PRAGMA foreign_key_list(loan_object);
PRAGMA foreign_key_list(condition_report);
PRAGMA foreign_key_check;

-- TASK 8
-- Run the complete setup printed above this block first.
SELECT 'lenders' AS relation_name,COUNT(*) AS rows FROM lender
UNION ALL SELECT 'loans',COUNT(*) FROM loan
UNION ALL SELECT 'objects',COUNT(*) FROM loan_object
UNION ALL SELECT 'reports',COUNT(*) FROM condition_report;
PRAGMA foreign_key_check;
-- Inspect the date and report-category constraints.
SELECT name,sql FROM sqlite_master
WHERE name IN ('loan','condition_report');

-- TASK 9
-- Q1 Overdue loans that remain open.
SELECT * FROM loan WHERE return_date IS NULL
 AND due_date<'2026-11-02';
-- Q2 Artifacts without any recorded condition evidence.
SELECT a.id,a.title FROM artifact a
WHERE NOT EXISTS (
 SELECT 1 FROM loan_object x JOIN condition_report r
 ON r.loan_object_id=x.id WHERE x.artifact_id=a.id);
-- Q3 Condition evidence for lender 1.
SELECT l.id,x.artifact_id,r.report_date,r.report_type
FROM loan l JOIN loan_object x ON x.loan_id=l.id
JOIN condition_report r ON r.loan_object_id=x.id
WHERE l.lender_id=1;
-- Q4 Active exhibition inventory.
SELECT e.name,s.slot_no,a.title FROM exhibition e
JOIN display_slot s ON s.exhibition_id=e.id
JOIN placement p ON p.exhibition_id=s.exhibition_id
 AND p.slot_no=s.slot_no
JOIN loan_object x ON x.id=p.loan_object_id
JOIN artifact a ON a.id=x.artifact_id
WHERE p.removed_on IS NULL;
-- Q5 Loans containing more than one artifact.
SELECT loan_id,COUNT(*) FROM loan_object
GROUP BY loan_id HAVING COUNT(*)>1;
-- Q6 Lenders with the number of their loan objects.
SELECT l.id,COUNT(x.id) FROM lender l
LEFT JOIN loan n ON n.lender_id=l.id
LEFT JOIN loan_object x ON x.loan_id=n.id GROUP BY l.id;
-- Q7 Return condition reports.
SELECT x.artifact_id,r.report_date,r.notes
FROM condition_report r JOIN loan_object x
 ON x.id=r.loan_object_id WHERE r.report_type='RETURN';
-- Q8 Objects still displayed after the custody due date.
SELECT p.id,x.artifact_id FROM placement p
JOIN loan_object x ON x.id=p.loan_object_id
JOIN loan l ON l.id=x.loan_id
WHERE p.removed_on IS NULL AND l.due_date<'2026-11-02';

-- TASK 10
CREATE VIEW registrar_open_loans AS
SELECT id,lender_id,start_date,due_date
FROM loan WHERE return_date IS NULL;
CREATE INDEX ix_loan_due ON loan(return_date,due_date);
SELECT * FROM registrar_open_loans;
EXPLAIN QUERY PLAN SELECT * FROM loan
WHERE return_date IS NULL AND due_date<'2026-11-02';

-- TASK 11
-- Audit the recommended event model.
SELECT loan_id,artifact_id,COUNT(*) AS copies
FROM loan_object GROUP BY loan_id,artifact_id
HAVING COUNT(*)>1;
SELECT r.id FROM condition_report r
LEFT JOIN loan_object x ON x.id=r.loan_object_id
WHERE x.id IS NULL;
PRAGMA foreign_key_check;

-- TASK 12
-- A and B: inspect preserved custody identifiers.
SELECT id,loan_id,artifact_id FROM loan_object ORDER BY id;
-- C: independent temporal legal ownership.
CREATE TABLE owner(owner_id INTEGER PRIMARY KEY,
 owner_name TEXT NOT NULL);
CREATE TABLE artifact_owner (
 artifact_id INTEGER NOT NULL REFERENCES artifact(id),
 owner_id INTEGER NOT NULL REFERENCES owner(owner_id),
 valid_from TEXT NOT NULL,valid_to TEXT,
 share_pct NUMERIC NOT NULL CHECK(share_pct>0 AND share_pct<=100),
 PRIMARY KEY(artifact_id,owner_id,valid_from),
 CHECK(valid_to IS NULL OR valid_to>valid_from));
INSERT INTO owner VALUES (1,'Owner A'),(2,'Owner B');
INSERT INTO artifact_owner VALUES
 (1,1,'2026-10-01','2026-11-01',60),
 (1,2,'2026-10-01','2026-11-01',40),
 (1,1,'2026-11-01',NULL,50),
 (1,2,'2026-11-01',NULL,50),
 (2,1,'2026-10-01',NULL,100),
 (3,2,'2026-10-01',NULL,100);
-- D: include artifacts with no ownership allocation.
SELECT a.id,COALESCE(SUM(o.share_pct),0) AS total_share
FROM artifact a LEFT JOIN artifact_owner o
 ON o.artifact_id=a.id AND o.valid_from<='2026-11-02'
 AND (o.valid_to IS NULL OR o.valid_to>'2026-11-02')
GROUP BY a.id HAVING ABS(COALESCE(SUM(o.share_pct),0)-100)>0.001;
-- Detect overlapping versions for the same owner and artifact.
SELECT a.artifact_id,a.owner_id,a.valid_from,b.valid_from
FROM artifact_owner a JOIN artifact_owner b
 ON a.artifact_id=b.artifact_id AND a.owner_id=b.owner_id
 AND a.valid_from<b.valid_from
WHERE b.valid_from<COALESCE(a.valid_to,'9999-12-31');
-- Changing ownership has not changed custody rows.
SELECT id,loan_id,artifact_id FROM loan_object ORDER BY id;
