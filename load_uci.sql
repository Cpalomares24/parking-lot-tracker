-- =====================================================================
-- Reference loader: UCI Parking Birmingham CSV -> parking_tracker
-- Run after schema.sql, with the client started as mysql --local-infile=1
-- (and local_infile=ON on the server). The Python loader should give the
-- same result; this script is the reference to check it against.
-- =====================================================================
USE parking_tracker;

DROP TEMPORARY TABLE IF EXISTS stg_uci;
CREATE TEMPORARY TABLE stg_uci (
  system_code  VARCHAR(32) NOT NULL,
  capacity     INT         NOT NULL,
  occupancy    INT         NOT NULL,
  last_updated DATETIME    NOT NULL
);

LOAD DATA LOCAL INFILE 'dataset.csv'
INTO TABLE stg_uci
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(system_code, capacity, occupancy, @ts)
SET last_updated = STR_TO_DATE(TRIM(TRAILING '\r' FROM @ts), '%Y-%m-%d %H:%i:%s');

-- 1. Lots (capacity is constant for each lot in the source)
INSERT INTO parking_lot (lot_code, capacity)
SELECT system_code, MAX(capacity)
FROM stg_uci
GROUP BY system_code;

-- 2. Hierarchy: 'NIA Car Parks' = 'NIA North' + 'NIA South'
--    (checked: capacity 480 + 788 = 1268, and occupancy sums match exactly)
UPDATE parking_lot c
JOIN parking_lot p ON p.lot_code = 'NIA Car Parks'
SET c.parent_lot_id = p.lot_id
WHERE c.lot_code IN ('NIA North', 'NIA South');

-- 3. Readings; INSERT IGNORE drops the exact-duplicate rows in the source
INSERT IGNORE INTO occupancy_reading (lot_id, recorded_at, occupied_count)
SELECT l.lot_id, s.last_updated, s.occupancy
FROM stg_uci s
JOIN parking_lot l ON l.lot_code = s.system_code;

DROP TEMPORARY TABLE stg_uci;
