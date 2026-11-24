-- =====================================================================
-- parking_tracker -- SAMPLE data for hours, rules, rates, closures,
-- holidays and special hours.
--
-- The UCI dataset has occupancy only. Everything in this file is
-- SYNTHETIC demo data so the app's filters and edge cases can be shown.
-- It is not real Birmingham parking policy.
--
-- Run order: schema.sql -> load_uci_inserts.sql (or Python importer)
--            -> schema_v2_special_cases.sql -> sample_data.sql
-- Lots are looked up by lot_code, so this works whatever lot_id values
-- your database assigned. Safe to re-run: it clears its own tables first.
-- =====================================================================
USE parking_tracker;

-- Start clean (only the tables this file fills; readings are untouched)
DELETE FROM lot_special_hours;
DELETE FROM holiday;
DELETE FROM lot_closure;
DELETE FROM lot_requirement;
DELETE FROM rate_plan;
DELETE FROM lot_hours;

-- ---------------------------------------------------------------------
-- 1. Friendlier names and an area label for the website cards
-- ---------------------------------------------------------------------
UPDATE parking_lot SET display_name = lot_code, address = 'Birmingham (UCI dataset)';
UPDATE parking_lot SET display_name = 'Broad Street Car Park'  WHERE lot_code = 'Broad Street';
UPDATE parking_lot SET display_name = 'Bull Ring Car Park'     WHERE lot_code = 'Bull Ring';
UPDATE parking_lot SET display_name = 'NIA Car Parks (total)'  WHERE lot_code = 'NIA Car Parks';
UPDATE parking_lot SET display_name = 'NIA North'              WHERE lot_code = 'NIA North';
UPDATE parking_lot SET display_name = 'NIA South'              WHERE lot_code = 'NIA South';
UPDATE parking_lot SET display_name = 'Shopping Centre Car Park' WHERE lot_code = 'Shopping';

-- ---------------------------------------------------------------------
-- 2. Extra requirement types used by the website filter
-- ---------------------------------------------------------------------
INSERT IGNORE INTO requirement_type (code, name, description) VALUES
  ('PERMIT',   'Permit required', 'Only vehicles with a valid parking permit'),
  ('RESERVED', 'Reserved parking', 'Spaces reserved in advance (events, contract holders)');

-- ---------------------------------------------------------------------
-- 3. Regular weekly hours (ISO day: 1 = Monday ... 7 = Sunday)
-- ---------------------------------------------------------------------
-- Default: Mon-Fri 06:00-22:00, Sat 07:00-22:00, Sun 08:00-20:00
INSERT INTO lot_hours (lot_id, day_of_week, open_time, close_time, effective_from)
SELECT l.lot_id, d.dow,
       CASE WHEN d.dow <= 5 THEN '06:00' WHEN d.dow = 6 THEN '07:00' ELSE '08:00' END,
       CASE WHEN d.dow <= 6 THEN '22:00' ELSE '20:00' END,
       '2016-01-01'
FROM parking_lot l
CROSS JOIN (SELECT 1 dow UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
            UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7) d
WHERE l.lot_code NOT IN ('Bull Ring', 'Broad Street', 'BHMBCCTHL01');

-- Edge case: open 24 hours (open_time = close_time = 00:00)
INSERT INTO lot_hours (lot_id, day_of_week, open_time, close_time, effective_from)
SELECT l.lot_id, d.dow, '00:00', '00:00', '2016-01-01'
FROM parking_lot l
CROSS JOIN (SELECT 1 dow UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
            UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7) d
WHERE l.lot_code = 'Bull Ring';

-- Edge case: split hours + window past midnight (close < open)
INSERT INTO lot_hours (lot_id, day_of_week, open_time, close_time, effective_from)
SELECT l.lot_id, d.dow, w.open_t, w.close_t, '2016-01-01'
FROM parking_lot l
CROSS JOIN (SELECT 1 dow UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
            UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7) d
CROSS JOIN (SELECT '07:00' open_t, '12:00' close_t
            UNION ALL SELECT '13:00', '02:00') w
WHERE l.lot_code = 'Broad Street';

-- Edge case: closed on Sundays (no Sunday row) for BHMBCCTHL01
INSERT INTO lot_hours (lot_id, day_of_week, open_time, close_time, effective_from)
SELECT l.lot_id, d.dow, '07:00', '19:00', '2016-01-01'
FROM parking_lot l
CROSS JOIN (SELECT 1 dow UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
            UNION ALL SELECT 5 UNION ALL SELECT 6) d
WHERE l.lot_code = 'BHMBCCTHL01';

-- ---------------------------------------------------------------------
-- 4. Access rules (lot_requirement)
-- ---------------------------------------------------------------------
-- Disability spaces in every lot: about 2% of capacity, at least 2
INSERT INTO lot_requirement (lot_id, requirement_type_id, spaces_count, effective_from)
SELECT l.lot_id, t.requirement_type_id, GREATEST(2, ROUND(l.capacity * 0.02)), '2016-01-01'
FROM parking_lot l
JOIN requirement_type t ON t.code = 'DISABILITY_PERMIT';

-- Whole-lot permit parking
INSERT INTO lot_requirement (lot_id, requirement_type_id, spaces_count, effective_from)
SELECT l.lot_id, t.requirement_type_id, NULL, '2016-01-01'
FROM parking_lot l
JOIN requirement_type t ON t.code = 'PERMIT'
WHERE l.lot_code IN ('BHMBRCBRG01', 'BHMBRCBRG02', 'BHMBRCBRG03', 'BHMBRTARC01');

-- Whole-lot reserved parking
INSERT INTO lot_requirement (lot_id, requirement_type_id, spaces_count, effective_from)
SELECT l.lot_id, t.requirement_type_id, NULL, '2016-01-01'
FROM parking_lot l
JOIN requirement_type t ON t.code = 'RESERVED'
WHERE l.lot_code IN ('NIA South', 'BHMMBMMBX01');

-- Time-limited rule: faculty/staff only on weekday mornings, 50 spaces
INSERT INTO lot_requirement (lot_id, requirement_type_id, spaces_count,
                             applies_from, applies_to, effective_from)
SELECT l.lot_id, t.requirement_type_id, 50, '07:00', '10:00', '2016-01-01'
FROM parking_lot l
JOIN requirement_type t ON t.code = 'FACULTY_ONLY'
WHERE l.lot_code = 'BHMEURBRD01';

-- ---------------------------------------------------------------------
-- 5. Rates. Free lots get a single 0.00 band; paid lots get day/evening
--    bands with a grace period and a daily cap; paid lots also carry
--    the PAID requirement so both tables agree.
-- ---------------------------------------------------------------------
-- Free lots
INSERT INTO rate_plan (lot_id, plan_name, day_of_week, start_time, end_time,
                       rate_amount, rate_unit, effective_from)
SELECT l.lot_id, 'Free parking', NULL, '00:00', '23:59', 0.00, 'FLAT', '2016-01-01'
FROM parking_lot l
WHERE l.lot_code IN ('BHMBCCMKT01', 'BHMBCCPST01', 'BHMBCCSNH01', 'BHMBCCTHL01',
                     'BHMEURBRD01', 'BHMEURBRD02', 'NIA North');

-- Paid lots: weekday daytime hourly with 15 free minutes and a cap
INSERT INTO rate_plan (lot_id, plan_name, day_of_week, start_time, end_time,
                       rate_amount, rate_unit, free_minutes, max_daily, effective_from)
SELECT l.lot_id, 'Daytime hourly', d.dow, '06:00', '18:00', 2.50, 'PER_HOUR', 15, 15.00, '2016-01-01'
FROM parking_lot l
CROSS JOIN (SELECT 1 dow UNION ALL SELECT 2 UNION ALL SELECT 3
            UNION ALL SELECT 4 UNION ALL SELECT 5) d
WHERE l.lot_code NOT IN ('BHMBCCMKT01', 'BHMBCCPST01', 'BHMBCCSNH01', 'BHMBCCTHL01',
                         'BHMEURBRD01', 'BHMEURBRD02', 'NIA North');

-- Paid lots: evening flat fee every day
INSERT INTO rate_plan (lot_id, plan_name, day_of_week, start_time, end_time,
                       rate_amount, rate_unit, effective_from)
SELECT l.lot_id, 'Evening flat', NULL, '18:00', '23:59', 4.00, 'FLAT', '2016-01-01'
FROM parking_lot l
WHERE l.lot_code NOT IN ('BHMBCCMKT01', 'BHMBCCPST01', 'BHMBCCSNH01', 'BHMBCCTHL01',
                         'BHMEURBRD01', 'BHMEURBRD02', 'NIA North');

-- Paid lots: free on weekends (free hours = 0.00 band)
INSERT INTO rate_plan (lot_id, plan_name, day_of_week, start_time, end_time,
                       rate_amount, rate_unit, effective_from)
SELECT l.lot_id, 'Weekend free daytime', d.dow, '06:00', '18:00', 0.00, 'FLAT', '2016-01-01'
FROM parking_lot l
CROSS JOIN (SELECT 6 dow UNION ALL SELECT 7) d
WHERE l.lot_code IN ('Shopping', 'Bull Ring');

INSERT INTO lot_requirement (lot_id, requirement_type_id, spaces_count, effective_from)
SELECT l.lot_id, t.requirement_type_id, NULL, '2016-01-01'
FROM parking_lot l
JOIN requirement_type t ON t.code = 'PAID'
WHERE l.lot_code NOT IN ('BHMBCCMKT01', 'BHMBCCPST01', 'BHMBCCSNH01', 'BHMBCCTHL01',
                         'BHMEURBRD01', 'BHMEURBRD02', 'NIA North');

-- ---------------------------------------------------------------------
-- 6. Closures with reasons
-- ---------------------------------------------------------------------
-- Full closure for an event (inside the 2016 data range)
INSERT INTO lot_closure (lot_id, starts_at, ends_at, closure_type, closure_reason_id, reason)
SELECT l.lot_id, '2016-11-12 06:00', '2016-11-12 23:59', 'FULL', r.closure_reason_id,
       'Concert at the arena'
FROM parking_lot l JOIN closure_reason r ON r.code = 'EVENT'
WHERE l.lot_code = 'NIA South';

-- Partial closure for maintenance: 200 spaces out of use for a week
INSERT INTO lot_closure (lot_id, starts_at, ends_at, closure_type, spaces_closed, closure_reason_id, reason)
SELECT l.lot_id, '2016-11-21 00:00', '2016-11-28 00:00', 'PARTIAL', 200, r.closure_reason_id,
       'Level 3 resurfacing'
FROM parking_lot l JOIN closure_reason r ON r.code = 'MAINTENANCE'
WHERE l.lot_code = 'Shopping';

-- Weather closure for one day
INSERT INTO lot_closure (lot_id, starts_at, ends_at, closure_type, closure_reason_id, reason)
SELECT l.lot_id, '2016-11-30 05:00', '2016-11-30 14:00', 'FULL', r.closure_reason_id,
       'Ice on ramps'
FROM parking_lot l JOIN closure_reason r ON r.code = 'WEATHER'
WHERE l.lot_code = 'BHMNCPRAN01';

-- Open-ended partial closure (ends_at NULL = until further notice)
INSERT INTO lot_closure (lot_id, starts_at, ends_at, closure_type, spaces_closed, closure_reason_id, reason)
SELECT l.lot_id, '2016-12-01 00:00', NULL, 'PARTIAL', 300, r.closure_reason_id,
       'East stairwell rebuild'
FROM parking_lot l JOIN closure_reason r ON r.code = 'CONSTRUCTION'
WHERE l.lot_code = 'Others-CCCPS8';

-- Upcoming closure (shows in a "current" demo)
INSERT INTO lot_closure (lot_id, starts_at, ends_at, closure_type, closure_reason_id, reason)
SELECT l.lot_id, '2026-12-05 12:00', '2026-12-05 23:59', 'FULL', r.closure_reason_id,
       'Holiday market setup'
FROM parking_lot l JOIN closure_reason r ON r.code = 'EVENT'
WHERE l.lot_code = 'Broad Street';

-- ---------------------------------------------------------------------
-- 7. Holidays and special hours
-- ---------------------------------------------------------------------
INSERT INTO holiday (holiday_date, name) VALUES
  ('2016-12-24', 'Christmas Eve'),
  ('2016-12-25', 'Christmas Day'),
  ('2016-12-26', 'Boxing Day'),
  ('2026-11-26', 'Thanksgiving'),
  ('2026-12-24', 'Christmas Eve'),
  ('2026-12-25', 'Christmas Day'),
  ('2027-01-01', 'New Year''s Day');

-- Christmas Day: most lots closed all day
INSERT INTO lot_special_hours (lot_id, special_date, is_closed, holiday_id, note)
SELECT l.lot_id, h.holiday_date, TRUE, h.holiday_id, 'Closed for the holiday'
FROM parking_lot l
JOIN holiday h ON h.name = 'Christmas Day'
WHERE l.lot_code NOT IN ('Bull Ring', 'Shopping');

-- Christmas Day: the 24-hour lot and the shopping centre run short hours
INSERT INTO lot_special_hours (lot_id, special_date, is_closed, open_time, close_time, holiday_id, note)
SELECT l.lot_id, h.holiday_date, FALSE, '10:00', '16:00', h.holiday_id, 'Holiday hours'
FROM parking_lot l
JOIN holiday h ON h.name = 'Christmas Day'
WHERE l.lot_code IN ('Bull Ring', 'Shopping');

-- Christmas Eve: everyone closes early
INSERT INTO lot_special_hours (lot_id, special_date, is_closed, open_time, close_time, holiday_id, note)
SELECT l.lot_id, h.holiday_date, FALSE, '07:00', '15:00', h.holiday_id, 'Early close'
FROM parking_lot l
JOIN holiday h ON h.name = 'Christmas Eve';

-- Thanksgiving 2026 and New Year's Day 2027: council lots closed
INSERT INTO lot_special_hours (lot_id, special_date, is_closed, holiday_id, note)
SELECT l.lot_id, h.holiday_date, TRUE, h.holiday_id, 'Closed for the holiday'
FROM parking_lot l
JOIN holiday h ON h.name IN ('Thanksgiving', 'New Year''s Day')
WHERE l.lot_code LIKE 'BHMBCC%';

-- Non-holiday special day: late opening after an event night
INSERT INTO lot_special_hours (lot_id, special_date, is_closed, open_time, close_time, note)
SELECT l.lot_id, '2016-11-13', FALSE, '11:00', '22:00', 'Late opening after concert cleanup'
FROM parking_lot l
WHERE l.lot_code = 'NIA South';

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
SELECT 'lot_hours' AS tbl, COUNT(*) AS rows_loaded FROM lot_hours
UNION ALL SELECT 'lot_requirement',   COUNT(*) FROM lot_requirement
UNION ALL SELECT 'rate_plan',         COUNT(*) FROM rate_plan
UNION ALL SELECT 'lot_closure',       COUNT(*) FROM lot_closure
UNION ALL SELECT 'holiday',           COUNT(*) FROM holiday
UNION ALL SELECT 'lot_special_hours', COUNT(*) FROM lot_special_hours;
