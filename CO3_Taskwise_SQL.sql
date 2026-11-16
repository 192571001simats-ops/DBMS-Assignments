-- Standalone SQLite 3 demonstration
-- Run in an empty connection. Small fixtures are not the original benchmark.

-- SETUP (printed under Task 8 in the assignment)
PRAGMA foreign_keys = ON;
ATTACH DATABASE ':memory:' AS n4;
CREATE TABLE n4.customer(customer_id INTEGER PRIMARY KEY,
 customer_name TEXT NOT NULL,customer_email TEXT NOT NULL UNIQUE);
CREATE TABLE n4.postal(ship_pin TEXT PRIMARY KEY,
 ship_city TEXT NOT NULL,ship_state TEXT NOT NULL);
CREATE TABLE n4.street_pin(ship_street TEXT,ship_pin TEXT
 REFERENCES postal,PRIMARY KEY(ship_street,ship_pin));
CREATE TABLE n4.category(category_id INTEGER PRIMARY KEY,
 category_name TEXT NOT NULL);
CREATE TABLE n4.supplier(supplier_id INTEGER PRIMARY KEY,
 supplier_name TEXT NOT NULL,supplier_phone TEXT NOT NULL);
CREATE TABLE n4.warehouse(warehouse_id INTEGER PRIMARY KEY,
 warehouse_city TEXT NOT NULL);
CREATE TABLE n4.product(product_id INTEGER PRIMARY KEY,
 product_name TEXT NOT NULL,unit_price NUMERIC NOT NULL
 CHECK(unit_price>=0),category_id INTEGER NOT NULL REFERENCES category,
 supplier_id INTEGER NOT NULL REFERENCES supplier);
CREATE TABLE n4.orders(order_id INTEGER PRIMARY KEY,
 order_date TEXT NOT NULL,customer_id INTEGER NOT NULL REFERENCES customer,
 ship_street TEXT NOT NULL,ship_pin TEXT NOT NULL,
 FOREIGN KEY(ship_street,ship_pin) REFERENCES street_pin);
CREATE TABLE n4.order_item(order_id INTEGER REFERENCES orders,
 product_id INTEGER REFERENCES product,quantity INTEGER NOT NULL
 CHECK(quantity>0),warehouse_id INTEGER NOT NULL REFERENCES warehouse,
 PRIMARY KEY(order_id,product_id));
CREATE TABLE n4.product_tag(product_id INTEGER REFERENCES product,
 tag TEXT,PRIMARY KEY(product_id,tag));
CREATE TABLE n4.product_colour(product_id INTEGER REFERENCES product,
 colour TEXT,PRIMARY KEY(product_id,colour));
INSERT INTO n4.customer VALUES (1,'Customer 1','c1@example.test'),
 (2,'Customer 2','c2@example.test');
INSERT INTO n4.postal VALUES ('600001','Chennai','Tamil Nadu');
INSERT INTO n4.street_pin VALUES ('Street 1','600001');
INSERT INTO n4.category VALUES (1,'Books'),(2,'Toys');
INSERT INTO n4.supplier VALUES
 (1,'Supplier 1','9000000001'),(2,'Supplier 2','9000000002');
INSERT INTO n4.warehouse VALUES (1,'Chennai'),(2,'Vellore'),(3,'Madurai');
INSERT INTO n4.product VALUES
 (1,'Book',100,1,1),(2,'Toy',200,2,2),(3,'Unused book',50,1,1);
INSERT INTO n4.orders VALUES
 (1,'2026-10-01',1,'Street 1','600001'),
 (2,'2026-10-02',1,'Street 1','600001'),
 (3,'2026-10-03',2,'Street 1','600001');
INSERT INTO n4.order_item VALUES
 (1,1,2,1),(1,2,1,1),(2,1,1,2),(3,2,2,1);
INSERT INTO n4.product_tag VALUES (1,'new'),(1,'sale');
INSERT INTO n4.product_colour VALUES (1,'red'),(1,'blue');
CREATE TABLE n4.flat_order_line AS
SELECT o.order_id,o.order_date,c.customer_id,c.customer_name,
 c.customer_email,o.ship_street,z.ship_city,z.ship_pin,z.ship_state,
 p.product_id,p.product_name,p.unit_price,
 g.category_id,g.category_name,s.supplier_id,s.supplier_name,
 s.supplier_phone,i.quantity,w.warehouse_id,w.warehouse_city,
 (SELECT group_concat(tag,',') FROM product_tag t
  WHERE t.product_id=p.product_id) AS tag_list,
 (SELECT group_concat(colour,',') FROM product_colour k
  WHERE k.product_id=p.product_id) AS colour_list
FROM orders o JOIN customer c USING(customer_id)
JOIN postal z USING(ship_pin) JOIN order_item i USING(order_id)
JOIN product p USING(product_id) JOIN category g USING(category_id)
JOIN supplier s USING(supplier_id) JOIN warehouse w USING(warehouse_id);

-- TASK 1
-- Check explicit FDs in the common flat demonstration state.
SELECT customer_id FROM n4.flat_order_line GROUP BY customer_id
HAVING COUNT(DISTINCT customer_name)>1
 OR COUNT(DISTINCT customer_email)>1;
SELECT product_id FROM n4.flat_order_line GROUP BY product_id
HAVING COUNT(DISTINCT unit_price)>1
 OR COUNT(DISTINCT supplier_id)>1;
SELECT order_id FROM n4.flat_order_line GROUP BY order_id
HAVING COUNT(DISTINCT customer_id)>1
 OR COUNT(DISTINCT ship_pin)>1;
-- Data checks test instances; the business rules justify FDs.

-- TASK 2
-- Update anomaly in the unvalidated flat baseline.
SAVEPOINT anomaly;
UPDATE n4.flat_order_line SET supplier_phone='9999999999'
WHERE order_id=1 AND product_id=1;
SELECT supplier_id,COUNT(DISTINCT supplier_phone) AS copies
FROM n4.flat_order_line GROUP BY supplier_id
HAVING COUNT(DISTINCT supplier_phone)>1;
ROLLBACK TO anomaly;
RELEASE anomaly;
-- Unordered and untagged products can still exist.
SELECT p.product_id FROM n4.product p WHERE NOT EXISTS
 (SELECT 1 FROM n4.order_item i WHERE i.product_id=p.product_id);
SELECT p.product_id FROM n4.product p WHERE NOT EXISTS
 (SELECT 1 FROM n4.product_tag t WHERE t.product_id=p.product_id);

-- TASK 3
-- Verify the order/product line key in this fixture.
SELECT order_id,product_id,COUNT(*) FROM n4.flat_order_line
GROUP BY order_id,product_id HAVING COUNT(*)>1;
-- Demonstrate OP -> quantity and warehouse via the line table.
SELECT i.order_id,i.product_id,i.quantity,i.warehouse_id,
 w.warehouse_city FROM n4.order_item i
JOIN n4.warehouse w USING(warehouse_id);
-- List determinants preserved by PK and UNIQUE constraints.
SELECT name,sql FROM n4.sqlite_master
WHERE name IN ('customer','product','order_item','postal');
-- The closure and canonical-cover proof remains in the written answer.

-- TASK 4
-- 2NF removes order-only and product-only repetitions.
SELECT DISTINCT order_id,order_date,customer_id,
 customer_name,customer_email,ship_street,ship_city,
 ship_pin,ship_state FROM n4.flat_order_line;
SELECT DISTINCT product_id,product_name,unit_price,
 category_id,category_name,supplier_id,supplier_name,
 supplier_phone FROM n4.flat_order_line;
SELECT order_id,product_id,quantity,warehouse_id,warehouse_city
FROM n4.flat_order_line;
-- Atomic 1NF children avoid parsing comma-separated lists.
SELECT * FROM n4.product_tag;
SELECT * FROM n4.product_colour;

-- TASK 5
-- BCNF master tables store one fact per determinant.
SELECT * FROM n4.customer;
SELECT * FROM n4.supplier;
SELECT * FROM n4.postal;
-- Cross-relation check for (street,city) -> PIN.
SELECT s.ship_street,p.ship_city,COUNT(DISTINCT s.ship_pin)
FROM n4.street_pin s JOIN n4.postal p USING(ship_pin)
GROUP BY s.ship_street,p.ship_city
HAVING COUNT(DISTINCT s.ship_pin)>1;
-- Run this global check inside a serialized address-write workflow.
-- This diagnostic alone does not enforce concurrent address changes.

-- TASK 6
-- 4NF independently stores tags and colours.
SELECT product_id,tag FROM n4.product_tag;
SELECT product_id,colour FROM n4.product_colour;
-- Reconstruct all combinations for product 1.
SELECT t.product_id,t.tag,c.colour
FROM n4.product_tag t JOIN n4.product_colour c USING(product_id)
WHERE t.product_id=1;
-- Separate child rows also preserve products with empty sets.
SELECT p.product_id,COUNT(t.tag) AS tag_count
FROM n4.product p LEFT JOIN n4.product_tag t USING(product_id)
GROUP BY p.product_id;

-- TASK 7
CREATE TABLE n4.supply_reference(supplier_id INTEGER,
 category_id INTEGER,warehouse_id INTEGER,
 PRIMARY KEY(supplier_id,category_id,warehouse_id));
INSERT INTO n4.supply_reference VALUES
 (1,1,1),(1,1,2),(1,1,3),(1,2,1),(1,2,2),(2,1,1);
CREATE TABLE n4.supplier_category(
 supplier_id INTEGER REFERENCES supplier,
 category_id INTEGER REFERENCES category,
 PRIMARY KEY(supplier_id,category_id));
CREATE TABLE n4.category_warehouse(
 category_id INTEGER REFERENCES category,
 warehouse_id INTEGER REFERENCES warehouse,
 PRIMARY KEY(category_id,warehouse_id));
CREATE TABLE n4.supplier_warehouse(
 supplier_id INTEGER REFERENCES supplier,
 warehouse_id INTEGER REFERENCES warehouse,
 PRIMARY KEY(supplier_id,warehouse_id));
INSERT INTO n4.supplier_category SELECT DISTINCT
 supplier_id,category_id FROM n4.supply_reference;
INSERT INTO n4.category_warehouse SELECT DISTINCT
 category_id,warehouse_id FROM n4.supply_reference;
INSERT INTO n4.supplier_warehouse SELECT DISTINCT
 supplier_id,warehouse_id FROM n4.supply_reference;
CREATE VIEW n4.supply AS
SELECT sc.supplier_id,sc.category_id,cw.warehouse_id
FROM supplier_category sc
JOIN category_warehouse cw USING(category_id)
JOIN supplier_warehouse sw ON sw.supplier_id=sc.supplier_id
 AND sw.warehouse_id=cw.warehouse_id;
-- Both differences must be empty under the stated cyclic JD.
SELECT * FROM n4.supply EXCEPT SELECT * FROM n4.supply_reference;
SELECT * FROM n4.supply_reference EXCEPT SELECT * FROM n4.supply;

-- TASK 8
-- Run the full setup first in an empty SQLite connection.
CREATE INDEX n4.orders_customer ON orders(customer_id,order_id);
PRAGMA n4.foreign_key_check;
-- Five-table history query, with a literal demo customer ID.
SELECT o.order_id,o.order_date,c.customer_name,
 i.product_id,p.product_name,p.unit_price,
 i.quantity,s.supplier_name
FROM n4.orders o JOIN n4.customer c USING(customer_id)
JOIN n4.order_item i USING(order_id)
JOIN n4.product p USING(product_id)
JOIN n4.supplier s USING(supplier_id)
WHERE o.customer_id=1 ORDER BY o.order_id,i.product_id;
-- Candidate boundary tests: zero-tag product is in Task 2;
-- positive quantity and nonnegative price are enforced in setup.

-- TASK 9
-- Count stored facts and repeated supplier copies.
SELECT 'flat_order_line' AS relation_name,COUNT(*) AS rows
FROM n4.flat_order_line
UNION ALL SELECT 'order_item',COUNT(*) FROM n4.order_item
UNION ALL SELECT 'supplier',COUNT(*) FROM n4.supplier;
SELECT supplier_id,COUNT(*) AS flat_phone_copies
FROM n4.flat_order_line GROUP BY supplier_id;
PRAGMA n4.page_count;
PRAGMA n4.page_size;
-- SQLite page figures describe this small demo as a whole.
-- The original PostgreSQL measurements remain a separate experiment.

-- TASK 10
SAVEPOINT update_cost;
UPDATE n4.flat_order_line SET supplier_phone='9000000099'
WHERE supplier_id=1;
SELECT changes() AS flat_rows_touched;
UPDATE n4.supplier SET supplier_phone='9000000099'
WHERE supplier_id=1;
SELECT changes() AS normalized_rows_touched;
ROLLBACK TO update_cost;
RELEASE update_cost;
EXPLAIN QUERY PLAN
SELECT o.order_id,i.product_id FROM n4.orders o
JOIN n4.order_item i USING(order_id) WHERE o.customer_id=1;

-- TASK 11
-- Referential integrity and retained line facts.
PRAGMA n4.foreign_key_check;
SELECT p.product_id,p.unit_price,s.supplier_name
FROM n4.product p JOIN n4.supplier s USING(supplier_id);
SELECT i.order_id,i.product_id,i.quantity,w.warehouse_city
FROM n4.order_item i JOIN n4.warehouse w USING(warehouse_id);
-- Supplier/category/warehouse permissions are derived by supply view.
SELECT * FROM n4.supply;

-- TASK 12
-- A: changed demand is a planning average, not a load test.
SELECT 200000.0/86400 AS mean_history_requests_per_second;
-- B and C: preserve an actual purchase-time price.
-- This tiny fixture has a known unchanged original price snapshot.
ALTER TABLE n4.order_item ADD COLUMN paid_unit_price NUMERIC
 CHECK(paid_unit_price>=0);
UPDATE n4.order_item SET paid_unit_price=(
 SELECT unit_price FROM n4.product p
 WHERE p.product_id=order_item.product_id);
-- In a real migration, backfill from verified invoices or receipts.
-- Do not use today's price for unknown historical purchase prices.
CREATE TRIGGER n4.require_paid_price
BEFORE INSERT ON order_item WHEN NEW.paid_unit_price IS NULL
BEGIN SELECT RAISE(ABORT,'Paid price is required'); END;
CREATE TRIGGER n4.guard_paid_price_update
BEFORE UPDATE OF paid_unit_price ON order_item
WHEN OLD.paid_unit_price IS NOT NULL
 AND NEW.paid_unit_price IS NOT OLD.paid_unit_price
BEGIN SELECT RAISE(ABORT,'Paid price is immutable'); END;
-- D: rollback-only catalogue repricing leaves paid prices unchanged.
SAVEPOINT repricing;
UPDATE n4.product SET unit_price=unit_price+10 WHERE product_id=1;
SELECT i.order_id,i.product_id,i.quantity,i.paid_unit_price,
 p.unit_price AS current_price,
 i.quantity*i.paid_unit_price AS paid_line_total
FROM n4.order_item i JOIN n4.product p USING(product_id)
JOIN n4.orders o USING(order_id) WHERE o.customer_id=1;
ROLLBACK TO repricing;
RELEASE repricing;
