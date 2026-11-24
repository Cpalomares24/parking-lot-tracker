-- =====================================================================
-- parking_tracker -- views and a status function used by the website
-- export (export_data_js.py) and the presentation demo.
-- Run after schema_v2_special_cases.sql. Safe to re-run.
-- =====================================================================
USE parking_tracker;

-- ---------------------------------------------------------------------
-- v_lot_hourly: average % of spaces FREE per lot and hour of day.
-- Uses only quality_flag = 'OK' readings.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lot_hourly AS
SELECT lot_id,
       lot_code,
       HOUR(recorded_at)                                  AS hour_of_day,
       ROUND(100 * (1 - AVG(occupancy_rate)), 2)          AS avg_available_pct,
       COUNT(*)                                           AS readings
FROM v_occupancy
WHERE quality_flag = 'OK'
GROUP BY lot_id, lot_code, HOUR(recorded_at);

-- ---------------------------------------------------------------------
-- v_overall_hourly: city-wide average by hour.
-- Excludes "total" lots that have sections (e.g. NIA Car Parks), so the
-- same cars are not counted twice.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_overall_hourly AS
SELECT HOUR(o.recorded_at)                                AS hour_of_day,
       ROUND(100 * (1 - AVG(o.occupancy_rate)), 2)        AS avg_available_pct,
       COUNT(*)                                           AS readings
FROM v_occupancy o
WHERE o.quality_flag = 'OK'
  AND NOT EXISTS (SELECT 1 FROM parking_lot c WHERE c.parent_lot_id = o.lot_id)
GROUP BY HOUR(o.recorded_at);

-- ---------------------------------------------------------------------
-- v_lot_profile: one row per lot with the labels the website filters on.
--   parking_type: 'permit' if a whole-lot PERMIT or FACULTY_ONLY rule is
--                 in force, else 'reserved' if a whole-lot RESERVED rule,
--                 else 'general'
--   payment:      'paid' if any current rate band charges money, else 'free'
--   is_total:     1 for lots whose sections are listed separately
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lot_profile AS
SELECT l.lot_id,
       l.lot_code,
       COALESCE(l.display_name, l.lot_code)               AS display_name,
       COALESCE(l.address, '')                            AS area,
       l.capacity,
       CASE
         WHEN EXISTS (SELECT 1 FROM lot_requirement q
                      JOIN requirement_type t ON t.requirement_type_id = q.requirement_type_id
                      WHERE q.lot_id = l.lot_id AND q.spaces_count IS NULL
                        AND q.applies_from IS NULL
                        AND t.code IN ('PERMIT', 'FACULTY_ONLY')
                        AND (q.effective_to IS NULL OR q.effective_to >= CURDATE()))
           THEN 'permit'
         WHEN EXISTS (SELECT 1 FROM lot_requirement q
                      JOIN requirement_type t ON t.requirement_type_id = q.requirement_type_id
                      WHERE q.lot_id = l.lot_id AND q.spaces_count IS NULL
                        AND q.applies_from IS NULL
                        AND t.code = 'RESERVED'
                        AND (q.effective_to IS NULL OR q.effective_to >= CURDATE()))
           THEN 'reserved'
         ELSE 'general'
       END                                                AS parking_type,
       CASE
         WHEN EXISTS (SELECT 1 FROM rate_plan p
                      WHERE p.lot_id = l.lot_id AND p.rate_amount > 0
                        AND (p.effective_to IS NULL OR p.effective_to >= CURDATE()))
           THEN 'paid'
         ELSE 'free'
       END                                                AS payment,
       EXISTS (SELECT 1 FROM parking_lot c WHERE c.parent_lot_id = l.lot_id) AS is_total
FROM parking_lot l
WHERE l.is_active = TRUE;

-- ---------------------------------------------------------------------
-- fn_lot_status(lot_id, moment): is the lot usable at that moment?
-- Precedence: closure > special hours > regular weekly hours.
-- Returns one of:
--   'CLOSED: <reason>'        full closure in force
--   'PARTIAL: <n> spaces closed (<reason>)'   open, but fewer spaces
--   'CLOSED: <note>'          special-hours day marked closed
--   'OPEN (special hours)'    inside a special-hours window
--   'CLOSED (special hours)'  special-hours day, outside its window
--   'OPEN' / 'CLOSED'         from regular hours
-- Handles 24-hour rows (00:00-00:00) and windows past midnight.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_lot_status;

DELIMITER $$
CREATE FUNCTION fn_lot_status(p_lot_id INT UNSIGNED, p_at DATETIME)
RETURNS VARCHAR(150)
READS SQL DATA
BEGIN
  DECLARE v_reason   VARCHAR(255);
  DECLARE v_spaces   INT;
  DECLARE v_closed   BOOLEAN;
  DECLARE v_open     TIME;
  DECLARE v_close    TIME;
  DECLARE v_note     VARCHAR(255);
  DECLARE v_partial  VARCHAR(150) DEFAULT NULL;
  DECLARE v_t        TIME    DEFAULT TIME(p_at);
  DECLARE v_d        DATE    DEFAULT DATE(p_at);
  DECLARE v_dow      TINYINT DEFAULT WEEKDAY(p_at) + 1;
  DECLARE v_prev_dow TINYINT DEFAULT WEEKDAY(p_at - INTERVAL 1 DAY) + 1;

  -- 1. Full closure wins
  SELECT COALESCE(r.name, c.reason, 'Closed') INTO v_reason
  FROM lot_closure c
  LEFT JOIN closure_reason r ON r.closure_reason_id = c.closure_reason_id
  WHERE c.lot_id = p_lot_id AND c.closure_type = 'FULL'
    AND p_at >= c.starts_at AND (c.ends_at IS NULL OR p_at < c.ends_at)
  ORDER BY c.starts_at DESC LIMIT 1;
  IF v_reason IS NOT NULL THEN
    RETURN CONCAT('CLOSED: ', v_reason);
  END IF;

  -- Partial closure: remember it, then still check hours
  SELECT c.spaces_closed, COALESCE(r.name, c.reason, 'closure')
    INTO v_spaces, v_reason
  FROM lot_closure c
  LEFT JOIN closure_reason r ON r.closure_reason_id = c.closure_reason_id
  WHERE c.lot_id = p_lot_id AND c.closure_type = 'PARTIAL'
    AND p_at >= c.starts_at AND (c.ends_at IS NULL OR p_at < c.ends_at)
  ORDER BY c.starts_at DESC LIMIT 1;
  IF v_spaces IS NOT NULL THEN
    SET v_partial = CONCAT('PARTIAL: ', v_spaces, ' spaces closed (', v_reason, ')');
  END IF;

  -- 2. Special hours for this date
  SELECT s.is_closed, s.open_time, s.close_time, COALESCE(s.note, 'special hours')
    INTO v_closed, v_open, v_close, v_note
  FROM lot_special_hours s
  WHERE s.lot_id = p_lot_id AND s.special_date = v_d
  LIMIT 1;
  IF v_closed IS NOT NULL THEN
    IF v_closed THEN
      RETURN CONCAT('CLOSED: ', v_note);
    ELSEIF v_t >= v_open AND v_t < v_close THEN
      RETURN COALESCE(v_partial, 'OPEN (special hours)');
    ELSE
      RETURN 'CLOSED (special hours)';
    END IF;
  END IF;

  -- 3. Regular hours: a window today, or last night's window that runs
  --    past midnight
  IF EXISTS (
       SELECT 1 FROM lot_hours h
       WHERE h.lot_id = p_lot_id AND h.day_of_week = v_dow
         AND h.effective_from <= v_d
         AND (h.effective_to IS NULL OR h.effective_to >= v_d)
         AND (   (h.open_time = '00:00' AND h.close_time = '00:00')
              OR (h.open_time < h.close_time AND v_t >= h.open_time AND v_t < h.close_time)
              OR (h.close_time <= h.open_time AND v_t >= h.open_time)))
     OR EXISTS (
       SELECT 1 FROM lot_hours h
       WHERE h.lot_id = p_lot_id AND h.day_of_week = v_prev_dow
         AND h.effective_from <= v_d - INTERVAL 1 DAY
         AND (h.effective_to IS NULL OR h.effective_to >= v_d - INTERVAL 1 DAY)
         AND h.close_time < h.open_time
         AND v_t < h.close_time)
  THEN
    RETURN COALESCE(v_partial, 'OPEN');
  END IF;

  RETURN 'CLOSED';
END$$
DELIMITER ;

-- Quick check
SELECT lot_code, display_name, capacity, parking_type, payment, is_total
FROM v_lot_profile ORDER BY lot_code;
SELECT * FROM v_overall_hourly ORDER BY hour_of_day;
