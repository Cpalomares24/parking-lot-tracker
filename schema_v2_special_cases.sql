-- =====================================================================
-- parking_tracker -- v2 additions: closure reasons, holidays, special hours
-- Run AFTER schema.sql on an existing database, ONCE.
-- (Re-running fails at the ALTER TABLE because the column already exists;
--  everything else uses IF NOT EXISTS / INSERT IGNORE.)
--
-- Precedence the app should use when deciding if a lot is open:
--   1. lot_closure        (FULL closure wins; PARTIAL reduces capacity)
--   2. lot_special_hours  (a dated exception, e.g. holiday hours)
--   3. lot_hours          (regular weekly schedule)
-- =====================================================================
USE parking_tracker;

-- ---------------------------------------------------------------------
-- closure_reason: lookup of WHY a lot is closed. New reasons = new rows.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS closure_reason (
  closure_reason_id  SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code               VARCHAR(32)  NOT NULL,
  name               VARCHAR(100) NOT NULL,
  PRIMARY KEY (closure_reason_id),
  UNIQUE KEY uq_closure_reason_code (code)
) ENGINE=InnoDB;

INSERT IGNORE INTO closure_reason (code, name) VALUES
  ('EVENT',        'Special event'),
  ('MAINTENANCE',  'Maintenance / repairs'),
  ('CONSTRUCTION', 'Construction'),
  ('WEATHER',      'Weather'),
  ('EMERGENCY',    'Emergency / safety'),
  ('HOLIDAY',      'Holiday closure'),
  ('OTHER',        'Other');

-- Link existing lot_closure rows to a reason. The old free-text
-- `reason` column stays as optional notes.
ALTER TABLE lot_closure
  ADD COLUMN closure_reason_id SMALLINT UNSIGNED NULL AFTER closure_type,
  ADD CONSTRAINT fk_closure_reason FOREIGN KEY (closure_reason_id)
      REFERENCES closure_reason (closure_reason_id) ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- holiday: named dates (campus-wide). One row per holiday per year.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS holiday (
  holiday_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  holiday_date  DATE         NOT NULL,
  name          VARCHAR(100) NOT NULL,
  PRIMARY KEY (holiday_id),
  UNIQUE KEY uq_holiday_date_name (holiday_date, name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- lot_special_hours: dated exceptions to lot_hours for one lot.
-- is_closed = TRUE  -> closed all day (times must be NULL)
-- is_closed = FALSE -> open from open_time to close_time that day
-- holiday_id is optional: set it when the exception is for a holiday.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lot_special_hours (
  lot_special_hours_id  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  lot_id                INT UNSIGNED NOT NULL,
  special_date          DATE         NOT NULL,
  is_closed             BOOLEAN      NOT NULL DEFAULT FALSE,
  open_time             TIME         NULL,
  close_time            TIME         NULL,
  holiday_id            INT UNSIGNED NULL,
  note                  VARCHAR(255) NULL,
  PRIMARY KEY (lot_special_hours_id),
  UNIQUE KEY uq_special (lot_id, special_date),
  CONSTRAINT fk_special_lot FOREIGN KEY (lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE CASCADE,
  CONSTRAINT fk_special_holiday FOREIGN KEY (holiday_id)
    REFERENCES holiday (holiday_id) ON DELETE SET NULL,
  CONSTRAINT ck_special_times CHECK (
       (is_closed = TRUE  AND open_time IS NULL     AND close_time IS NULL)
    OR (is_closed = FALSE AND open_time IS NOT NULL AND close_time IS NOT NULL))
) ENGINE=InnoDB;

-- Quick check
SHOW TABLES;
