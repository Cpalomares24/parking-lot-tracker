-- =====================================================================
-- Campus Parking-Conditions Tracker -- database schema (MySQL 8.0.16+)
-- CS 514 team project
-- Source data: UCI "Parking Birmingham" dataset (ID 482), CC BY 4.0
--
-- Conventions
--   * Surrogate integer PKs; natural keys kept as UNIQUE columns.
--   * All DATETIME / TIME values are lot-local wall-clock time
--     (parking_lot.time_zone; 'Europe/London' for the UCI data).
--   * Day of week uses ISO numbering: 1 = Monday ... 7 = Sunday.
--   * effective_from / effective_to give the validity window of a rule;
--     effective_to NULL = still in force (open-ended).
--   * CHECK constraints are enforced from MySQL 8.0.16 onward.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS parking_tracker
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE parking_tracker;

-- ---------------------------------------------------------------------
-- parking_lot: one row per lot, or per section of a lot.
-- parent_lot_id links a section (e.g. 'NIA North') to the lot that
-- contains it ('NIA Car Parks'), so totals are not double-counted.
-- ---------------------------------------------------------------------
CREATE TABLE parking_lot (
  lot_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  lot_code       VARCHAR(32)   NOT NULL,          -- CSV: SystemCodeNumber
  display_name   VARCHAR(100)  NULL,
  parent_lot_id  INT UNSIGNED  NULL,
  capacity       INT UNSIGNED  NOT NULL,          -- CSV: Capacity
  address        VARCHAR(255)  NULL,
  latitude       DECIMAL(9,6)  NULL,
  longitude      DECIMAL(9,6)  NULL,
  time_zone      VARCHAR(64)   NOT NULL DEFAULT 'Europe/London',
  is_active      BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (lot_id),
  UNIQUE KEY uq_lot_code (lot_code),
  KEY ix_lot_parent (parent_lot_id),
  CONSTRAINT fk_lot_parent FOREIGN KEY (parent_lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE SET NULL,
  CONSTRAINT ck_lot_capacity  CHECK (capacity > 0),
  -- No CHECK for parent_lot_id <> lot_id: MySQL rejects CHECKs on FK
  -- referential-action columns and on AUTO_INCREMENT columns (errors 3823/3818).
  -- The loader/application must prevent a lot from being its own parent.
  CONSTRAINT ck_lot_lat       CHECK (latitude  IS NULL OR latitude  BETWEEN -90  AND 90),
  CONSTRAINT ck_lot_lon       CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- occupancy_reading: time series of occupied-space counts.
-- occupied_count is SIGNED and has no upper bound: the raw feed contains
-- negative counts and counts above capacity. These rows are kept and
-- flagged in v_occupancy instead of being rejected.
-- ---------------------------------------------------------------------
CREATE TABLE occupancy_reading (
  reading_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  lot_id          INT UNSIGNED    NOT NULL,
  recorded_at     DATETIME        NOT NULL,       -- CSV: LastUpdated
  occupied_count  INT             NOT NULL,       -- CSV: Occupancy
  source          VARCHAR(32)     NOT NULL DEFAULT 'UCI_BHAM_2016',
  ingested_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reading_id),
  UNIQUE KEY uq_reading_lot_time (lot_id, recorded_at),  -- also the lot+time-range index
  KEY ix_reading_time (recorded_at),
  CONSTRAINT fk_reading_lot FOREIGN KEY (lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- lot_hours: regular weekly opening hours.
-- A day may have several rows (split hours). close_time <= open_time
-- means the window runs past midnight; open_time = close_time = '00:00'
-- means open 24 hours. A day with no row is a closed day.
-- ---------------------------------------------------------------------
CREATE TABLE lot_hours (
  lot_hours_id    INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  lot_id          INT UNSIGNED     NOT NULL,
  day_of_week     TINYINT UNSIGNED NOT NULL,
  open_time       TIME             NOT NULL,
  close_time      TIME             NOT NULL,
  effective_from  DATE             NOT NULL,
  effective_to    DATE             NULL,
  PRIMARY KEY (lot_hours_id),
  UNIQUE KEY uq_hours (lot_id, day_of_week, effective_from, open_time),
  CONSTRAINT fk_hours_lot FOREIGN KEY (lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE CASCADE,
  CONSTRAINT ck_hours_dow    CHECK (day_of_week BETWEEN 1 AND 7),
  CONSTRAINT ck_hours_window CHECK (effective_to IS NULL OR effective_to >= effective_from)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- lot_closure: one-off closures (events, maintenance, weather).
-- Overrides lot_hours. spaces_closed NULL = whole lot closed.
-- ends_at NULL = closed until further notice.
-- ---------------------------------------------------------------------
CREATE TABLE lot_closure (
  closure_id     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  lot_id         INT UNSIGNED  NOT NULL,
  starts_at      DATETIME      NOT NULL,
  ends_at        DATETIME      NULL,
  closure_type   ENUM('FULL','PARTIAL') NOT NULL DEFAULT 'FULL',
  spaces_closed  INT UNSIGNED  NULL,
  reason         VARCHAR(255)  NULL,
  PRIMARY KEY (closure_id),
  KEY ix_closure_lot_time (lot_id, starts_at),
  CONSTRAINT fk_closure_lot FOREIGN KEY (lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE CASCADE,
  CONSTRAINT ck_closure_window  CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT ck_closure_partial CHECK (
       (closure_type = 'FULL'    AND spaces_closed IS NULL)
    OR (closure_type = 'PARTIAL' AND spaces_closed IS NOT NULL AND spaces_closed > 0))
    -- IS NOT NULL is required: a CHECK that evaluates to NULL counts as passing.
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- requirement_type: lookup table of access rules. New rules
-- (EV charging, motorcycle, visitor permit, ...) are new rows,
-- so no schema change is needed.
-- ---------------------------------------------------------------------
CREATE TABLE requirement_type (
  requirement_type_id  SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code                 VARCHAR(32)  NOT NULL,
  name                 VARCHAR(100) NOT NULL,
  description          VARCHAR(255) NULL,
  PRIMARY KEY (requirement_type_id),
  UNIQUE KEY uq_requirement_code (code)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- lot_requirement: links lots to requirement types (M:N), optionally
-- limited to some spaces and/or a daily time window.
-- spaces_count NULL = the whole lot; applies_from/applies_to NULL = all day.
-- ---------------------------------------------------------------------
CREATE TABLE lot_requirement (
  lot_requirement_id   INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  lot_id               INT UNSIGNED      NOT NULL,
  requirement_type_id  SMALLINT UNSIGNED NOT NULL,
  spaces_count         INT UNSIGNED      NULL,
  applies_from         TIME              NULL,
  applies_to           TIME              NULL,
  effective_from       DATE              NOT NULL,
  effective_to         DATE              NULL,
  PRIMARY KEY (lot_requirement_id),
  UNIQUE KEY uq_lot_req (lot_id, requirement_type_id, effective_from, applies_from),
  KEY ix_lot_req_type (requirement_type_id),
  CONSTRAINT fk_lotreq_lot  FOREIGN KEY (lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE CASCADE,
  CONSTRAINT fk_lotreq_type FOREIGN KEY (requirement_type_id)
    REFERENCES requirement_type (requirement_type_id) ON DELETE RESTRICT,
  CONSTRAINT ck_lotreq_spaces CHECK (spaces_count IS NULL OR spaces_count > 0),
  CONSTRAINT ck_lotreq_time   CHECK ((applies_from IS NULL) = (applies_to IS NULL)),
  CONSTRAINT ck_lotreq_window CHECK (effective_to IS NULL OR effective_to >= effective_from)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- rate_plan: pricing per lot, day and time band.
-- Free hours = a row with rate_amount = 0 for that band.
-- free_minutes = grace period before charging starts.
-- day_of_week NULL = every day.
-- ---------------------------------------------------------------------
CREATE TABLE rate_plan (
  rate_plan_id    INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  lot_id          INT UNSIGNED     NOT NULL,
  plan_name       VARCHAR(100)     NOT NULL,
  day_of_week     TINYINT UNSIGNED NULL,
  start_time      TIME             NOT NULL,
  end_time        TIME             NOT NULL,
  rate_amount     DECIMAL(8,2)     NOT NULL,
  rate_unit       ENUM('PER_HOUR','PER_DAY','FLAT','PER_ENTRY') NOT NULL,
  free_minutes    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  max_daily       DECIMAL(8,2)     NULL,
  currency        CHAR(3)          NOT NULL DEFAULT 'GBP',
  effective_from  DATE             NOT NULL,
  effective_to    DATE             NULL,
  PRIMARY KEY (rate_plan_id),
  KEY ix_rate_lot (lot_id, day_of_week, start_time),
  CONSTRAINT fk_rate_lot FOREIGN KEY (lot_id)
    REFERENCES parking_lot (lot_id) ON DELETE CASCADE,
  CONSTRAINT ck_rate_amount CHECK (rate_amount >= 0),
  CONSTRAINT ck_rate_max    CHECK (max_daily IS NULL OR max_daily >= 0),
  CONSTRAINT ck_rate_dow    CHECK (day_of_week IS NULL OR day_of_week BETWEEN 1 AND 7),
  CONSTRAINT ck_rate_window CHECK (effective_to IS NULL OR effective_to >= effective_from)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- v_occupancy: readings joined to their lot, with occupancy rate and
-- a data-quality flag. Query this view rather than the raw table.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_occupancy AS
SELECT r.reading_id,
       l.lot_id,
       l.lot_code,
       l.parent_lot_id,
       r.recorded_at,
       r.occupied_count,
       l.capacity,
       ROUND(r.occupied_count / l.capacity, 4) AS occupancy_rate,
       CASE
         WHEN r.occupied_count < 0           THEN 'NEGATIVE'
         WHEN r.occupied_count > l.capacity  THEN 'OVER_CAPACITY'
         ELSE 'OK'
       END AS quality_flag
FROM occupancy_reading r
JOIN parking_lot l ON l.lot_id = r.lot_id;

-- ---------------------------------------------------------------------
-- Seed data for the lookup table
-- ---------------------------------------------------------------------
INSERT INTO requirement_type (code, name, description) VALUES
  ('DISABILITY_PERMIT', 'Disability permit',  'Space reserved for vehicles displaying a valid disability permit'),
  ('FACULTY_ONLY',      'Faculty/staff only', 'Restricted to holders of a faculty or staff permit'),
  ('PAID',              'Paid parking',       'Payment required; prices are in rate_plan');
