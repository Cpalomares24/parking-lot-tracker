# parking-lot-tracker

Parking Lot Tracker is a database-driven application designed to store and analyze parking lot occupancy data.

## Parking Overview

The application allows users to import parking data from a CSV file and store the information in a MySQL database. Users can inspect historical parking lot capacity and occupancy readings, examine average availability by hour, and search for parking lots based on selected preferences.

The current prototype runs in the terminal. Availability results are based on historical data, **not live parking availability**.

## Features

### Implemented Features

- Import parking data from CSV files into MySQL.
- Store parking lot information and historical occupancy records.
- Calculate parking availability by hour.
- Search, filter, and compare parking availability across different lots.

### Planned Features

- Compare occupancy between different parking lots
- Display parking occupancy trends

## Prerequisites

- Python 3.10 or newer, with `pip` and `venv`.
- MySQL Server 8.0.16 or newer (tested on MySQL Server 8.0.46).
- Git.
- Python dependencies from `requirements.txt` (MySQL Connector/Python 26.7.0 was used for local integration testing).
- A MySQL account with access to the `parking_tracker` database.

The Python application is intended to run on Windows, macOS, or Linux with these dependencies. **End-to-end testing was performed on Ubuntu 24.04; other operating systems have not been independently tested.** Commands should be run from the repository directory unless stated otherwise.

## Setup and Running the Application

### 1. Clone the repository

Using SSH (requires a configured GitHub SSH key):

```bash
git clone git@github.com:Cpalomares24/parking-lot-tracker.git
cd parking-lot-tracker
```

Or use HTTPS:

```bash
git clone https://github.com/Cpalomares24/parking-lot-tracker.git
cd parking-lot-tracker
```

### 2. Create a Python virtual environment and install dependencies

**Linux / macOS:**

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

On Ubuntu, if `venv` is missing, install `python3-venv` using your package manager and retry.

**Windows (PowerShell):**

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

If PowerShell blocks activation, use `.venv\Scripts\python.exe` to run the remaining Python commands without activating the environment.

### 3. Initialize the MySQL database

Start MySQL Server using your operating system's service manager or MySQL installation tools. Run the existing schema with an administrative MySQL account:

```bash
mysql -u root -p < schema.sql
```

This works in a terminal with the MySQL client on `PATH` and a password-authenticated administrative account. Alternatively, open `schema.sql` in MySQL Workbench and execute it using an administrative connection.

**Ubuntu/Linux with socket-authenticated root:**

```bash
sudo systemctl start mysql
sudo mysql < schema.sql
```

The schema creates the `parking_tracker` database, seven tables, the `v_occupancy` view, and seed requirement types. **It does not load the occupancy dataset.** Do not rerun the schema on an existing populated database without reviewing its effects.

Verify the schema using a MySQL account that can access the database:

```bash
mysql -u root -p -D parking_tracker -e "SHOW TABLES;"
```

For socket-authenticated Ubuntu root, use below instead:
```bash
sudo mysql -D parking_tracker -e "SHOW TABLES;"
```

### 4. Create a database account and configure Python access

Connect as a MySQL administrator using the MySQL command-line client or MySQL Workbench. On Ubuntu installations with socket authentication, `sudo mysql` opens the administrator prompt.

Execute the following SQL once, substituting a strong password of your own:

```sql
CREATE USER 'parking_app'@'localhost' IDENTIFIED BY 'choose-a-strong-password';
GRANT SELECT, INSERT, UPDATE ON parking_tracker.* TO 'parking_app'@'localhost';
```

Do not repeat `CREATE USER` if the account already exists. These permissions are sufficient for the CSV importer and analysis scripts, not for creating the schema. Never commit real passwords.

The migrated I/O scripts share the `connect()` function in `import_data.py`. It reads `MYSQL_HOST` (default `localhost`), `MYSQL_PORT` (default `3306`), `MYSQL_USER` (default `root`), `MYSQL_PASSWORD` (default empty), and `MYSQL_DATABASE` (default `parking_tracker`).

**Linux / macOS (Bash):**

```bash
export MYSQL_USER=parking_app
read -rsp 'MySQL password: ' MYSQL_PASSWORD
echo
export MYSQL_PASSWORD
```

**Windows (PowerShell):**

```powershell
$env:MYSQL_USER = 'parking_app'
$securePassword = Read-Host 'MySQL password' -AsSecureString
$env:MYSQL_PASSWORD = [System.Net.NetworkCredential]::new('', $securePassword).Password
Remove-Variable securePassword
```

These settings apply only to the current terminal session. Set `MYSQL_HOST`, `MYSQL_PORT`, or `MYSQL_DATABASE` similarly if your installation differs.

**Important difference in the existing search scripts:** `mysql_parking_data.py` and `parking_search.py` currently use the hardcoded username `root` and ask for a MySQL root password. They **do not** read the `MYSQL_*` environment variables. To run them unchanged, a password-authenticated MySQL root account must be available. Alternatively, change their local connection username to an authorized account such as `parking_app` and enter that account's password when prompted. Do not commit local credential changes. On Ubuntu, socket-authenticated root (`auth_socket`) cannot log in through those password-based Python connections without a configuration change.

### 5. Obtain the sample dataset

The test data comes from the [UCI Parking Birmingham dataset](https://archive.ics.uci.edu/dataset/482/parking+birmingham) (dataset ID 482, CC BY 4.0). It contains historical parking readings from October–December 2016. The original CSV has these columns:

```text
SystemCodeNumber,Capacity,Occupancy,LastUpdated
```

Download the dataset from the [UCI dataset page](https://archive.ics.uci.edu/dataset/482/parking+birmingham) and extract `dataset.csv` into a `data/` directory at the repository root.

On Linux/macOS with `curl` and `unzip`, this can be done with:

```bash
mkdir -p data
curl -L 'https://archive.ics.uci.edu/static/public/482/parking+birmingham.zip' -o parking_birmingham.zip
unzip -o parking_birmingham.zip -d data/
rm parking_birmingham.zip
```

On Windows, download the ZIP in a browser and extract it into `data/`, or use PowerShell:

```powershell
New-Item -ItemType Directory -Force data | Out-Null
Invoke-WebRequest 'https://archive.ics.uci.edu/static/public/482/parking+birmingham.zip' -OutFile parking_birmingham.zip
Expand-Archive -Path parking_birmingham.zip -DestinationPath data -Force
Remove-Item parking_birmingham.zip
```

Confirm the file is located at `data/dataset.csv`. The local `data/` directory is ignored by Git. The downloaded ZIP is temporary and should not be committed; delete it after extraction.

### 6. Import the CSV into MySQL

With the virtual environment activated and the `MYSQL_*` variables configured:

```bash
python import_data.py data/dataset.csv
```

The CSV path is optional when using the default `data/dataset.csv`. To import another compatible file, supply its path:

```bash
python import_data.py /path/to/another_dataset.csv
```

The importer checks required columns and lot capacities, reuses existing lots, and prevents duplicate readings using the schema's unique `(lot_id, recorded_at)` key. It commits a successful import as a transaction and rolls back on errors. Negative and over-capacity occupancy counts are deliberately preserved; the `v_occupancy` view flags them. If an existing lot has a different capacity from the CSV, the import fails rather than silently changing that lot's capacity. Duplicate lot/timestamp readings are skipped, not overwritten.

On an initially empty database, the UCI dataset produces these tested import statistics:

```text
rows: 35717
lots_added: 30
readings_added: 35501
duplicates: 216
```

Reimporting the same CSV produces zero new lots and readings, with all 35,717 input rows counted as duplicates.

**Alternative data-loading methods:** `load_uci.sql` and `load_uci_inserts.sql` are existing MySQL reference loaders. Use **one loading approach** for initial setup; the Python importer is the recommended path for testing CSV I/O. `load_uci.sql` requires MySQL `LOCAL INFILE` support and an appropriately located CSV. `load_uci_inserts.sql` contains SQL inserts for the supplied dataset. Do not run multiple loaders indiscriminately against populated tables.

**Dataset hierarchy note:** The reference SQL loader sets `NIA North` and `NIA South` as children of `NIA Car Parks` using `parent_lot_id`. The generic Python CSV importer does not infer or create parent-child relationships because those relationships are not present in the CSV columns. Consequently, a database initialized only through the Python importer has the correct reading counts but does not automatically have this hierarchy metadata. Queries that aggregate parent and child lots should account for this to avoid double counting.

### 7. Verify the imported data

```bash
mysql -u parking_app -p parking_tracker -e "SELECT COUNT(*) AS lots FROM parking_lot; SELECT COUNT(*) AS readings FROM occupancy_reading;"
```

Check the quality flags:

```bash
mysql -u parking_app -p parking_tracker -e "SELECT quality_flag, COUNT(*) AS total FROM v_occupancy GROUP BY quality_flag ORDER BY quality_flag;"
```

Expected totals for the UCI dataset:

| Metric | Count |
| --- | ---: |
| Parking lots | 30 |
| Unique occupancy readings | 35,501 |
| Valid (`OK`) readings | 35,116 |
| Negative readings | 12 |
| Over-capacity readings | 373 |

These values were verified against the Python CSV importer on MySQL Server 8.0.46.

### 8. Run the analysis scripts

These scripts use the shared environment-variable connection configuration from step 4:

```bash
python analyze_parking.py
python availability_by_hour.py
```

- `analyze_parking.py` displays five valid historical readings with lot codes, capacities, occupied counts, available spaces, and timestamps.
- `availability_by_hour.py` calculates the average available-space percentage for each hour represented in the dataset. Invalid readings are excluded from availability calculations but remain stored in MySQL.

For the UCI dataset, hourly averages run from 07:00 through 16:00. For example, 07:00 averages **79.02%** available and 14:00 averages **40.15%** available.

### 9. Run the interactive parking search

**MySQL authentication:** Both scripts prompt for a MySQL root password because their connection settings currently use `root`. If your MySQL root account uses socket authentication (common on Ubuntu), password-based login will not work. To run the scripts with a different MySQL account, change `user="root"` to `user="parking_app"` (or another authorized account) in each script and enter that account's password when prompted. Do not commit local credential changes.

Once the search scripts have a working password-authenticated MySQL connection (see step 4), run:

```bash
python mysql_parking_data.py
python parking_search.py
```

- `mysql_parking_data.py` asks for an hour (0–23) and displays the five parking lots with the highest historical average availability at that hour.
- `parking_search.py` asks for an hour, number of lots, whether to include closed lots, parking type (`all`, `general`, `faculty`), and payment type (`all`, `free`, `paid`). It then ranks and displays matching lots.

For example, searching at hour `12` with five lots, `yes` for closed lots, and `all` for both filters returns historical availability rankings. The search application currently runs in the terminal only.

**Data-source limitation:** Availability percentages are calculated from real historical UCI occupancy readings. Operating hours, open/closed status, faculty/general restrictions, and parking rates in the interactive search are **simulated for demonstration** because the UCI dataset does not supply those fields. They should not be treated as verified real-world parking conditions.

## Database Design

The MySQL schema is defined in `schema.sql`, with additional design details in `Parking_Tracker_DB_Design.pdf` and the ER diagram source `er.dot`.

The seven tables are `parking_lot`, `occupancy_reading`, `lot_hours`, `lot_closure`, `requirement_type`, `lot_requirement`, and `rate_plan`. The `v_occupancy` view joins lots and readings and classifies data quality as `OK`, `NEGATIVE`, or `OVER_CAPACITY`.

The schema includes primary and foreign keys, uniqueness constraints, indexes, and validation constraints. Occupancy timestamps are stored as lot-local wall-clock values (`Europe/London` for the UCI data), not automatically converted to UTC.

## Repository Files

| File | Purpose |
| --- | --- |
| `schema.sql` | Creates the MySQL database schema and view. |
| `Parking_Tracker_DB_Design.pdf` | Database design and implementation notes. |
| `er.dot` | Entity-relationship diagram source. |
| `load_uci.sql` | Reference CSV-to-MySQL SQL loader. |
| `load_uci_inserts.sql` | SQL insert-based UCI dataset loader. |
| `import_data.py` | Reusable CSV-to-MySQL importer. |
| `analyze_parking.py` | Sample occupancy and available-space analysis. |
| `availability_by_hour.py` | Average availability grouped by hour. |
| `mysql_parking_data.py` | Top-five historical availability lookup for a selected hour. |
| `parking_search.py` | Interactive terminal parking search and filters. |
| `availability_by_location.py` | Reserved for future location-based analysis (currently empty). |
| `parksmart.db` | Legacy SQLite database; not used by the migrated MySQL scripts. |
| `requirements.txt` | Python package dependencies. |

## Troubleshooting

- **`ModuleNotFoundError: No module named 'mysql'`:** Activate `.venv` and run `python -m pip install -r requirements.txt`.
- **`Access denied for user`:** Verify the username, password, and MySQL account authentication method. A root account using `auth_socket` is not the same as password-based root login.
- **`Unknown database 'parking_tracker'` or missing tables:** Initialize the schema in step 3.
- **CSV file not found:** Confirm `data/dataset.csv` exists or pass an explicit CSV path.
- **CSV capacity mismatch:** The importer intentionally refuses conflicting capacity values; inspect the CSV and existing `parking_lot` record rather than overwriting it automatically.
- **Unexpected duplicate count:** Import statistics depend on which readings are already present. Repeated imports should not add duplicate lot/timestamp readings.
- **No parking-search results:** Confirm the database contains readings and that the selected hour exists in the historical data. The example dataset has observations for hours 07:00–16:00.

## Development Status

Currently in development for **Phase 1 of the CS 514 Final Database Product Project**. The MySQL CSV importer, original analysis scripts, and terminal search have been tested together against the UCI dataset on Ubuntu 24.04.

## Data Attribution

Sample data: [UCI Machine Learning Repository — Parking Birmingham (ID 482)](https://archive.ics.uci.edu/dataset/482/parking+birmingham), distributed under **CC BY 4.0**. The application uses historical data for educational demonstration and does not provide live parking information.
