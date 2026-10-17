"""Import UCI Parking Birmingham-compatible CSV files into the existing MySQL schema."""
import argparse
import csv
import os
from datetime import datetime

import mysql.connector


def connect():
    """Connect using environment variables, without storing credentials in code."""
    return mysql.connector.connect(
        host=os.getenv('MYSQL_HOST', 'localhost'),
        port=int(os.getenv('MYSQL_PORT', '3306')),
        user=os.getenv('MYSQL_USER', 'root'),
        password=os.getenv('MYSQL_PASSWORD', ''),
        database=os.getenv('MYSQL_DATABASE', 'parking_tracker'),
    )


def import_csv(path):
    """Import readings atomically into existing MySQL tables."""
    stats = {'rows': 0, 'lots_added': 0, 'readings_added': 0, 'duplicates': 0}
    connection = connect()
    try:
        cursor = connection.cursor()
        lot_ids = {}
        lot_capacities = {}
        with open(path, newline='', encoding='utf-8-sig') as file:
            reader = csv.DictReader(file)
            required = {'SystemCodeNumber', 'Capacity', 'Occupancy', 'LastUpdated'}
            if not required.issubset(reader.fieldnames or []):
                raise ValueError('CSV missing columns: ' + ', '.join(sorted(required - set(reader.fieldnames or []))))
            for line, row in enumerate(reader, start=2):
                try:
                    code = row['SystemCodeNumber'].strip()
                    capacity = int(row['Capacity'])
                    occupied = int(row['Occupancy'])
                    recorded = datetime.strptime(row['LastUpdated'].strip(), '%Y-%m-%d %H:%M:%S')
                    if not code or capacity <= 0:
                        raise ValueError('lot code must be present and capacity must be positive')
                except (ValueError, TypeError, AttributeError) as exc:
                    raise ValueError(f'Invalid CSV row {line}: {exc}') from exc
                stats['rows'] += 1
                # Each lot has one capacity; reject inconsistent CSV rows.
                if code in lot_capacities and lot_capacities[code] != capacity:
                    raise ValueError(
                        f'Row {line}: capacity mismatch for {code}: '
                        f'expected={lot_capacities[code]}, CSV={capacity}'
                    )
                if code not in lot_ids:
                    cursor.execute('SELECT lot_id, capacity FROM parking_lot WHERE lot_code = %s', (code,))
                    existing = cursor.fetchone()
                    if existing:
                        lot_id, saved_capacity = existing
                        if saved_capacity != capacity:
                            raise ValueError(f'Row {line}: capacity mismatch for {code}: database={saved_capacity}, CSV={capacity}')
                    else:
                        cursor.execute('INSERT INTO parking_lot (lot_code, capacity) VALUES (%s, %s)', (code, capacity))
                        lot_id = cursor.lastrowid
                        stats['lots_added'] += 1
                    # Reuse existing lots instead of modifying their metadata.
                    lot_ids[code] = lot_id
                    lot_capacities[code] = capacity
                # Keep negative/over-capacity readings: v_occupancy flags them.
                # The unique (lot_id, recorded_at) key prevents duplicates.
                # Existing readings are left unchanged on repeat imports.
                cursor.execute('''INSERT INTO occupancy_reading
                    (lot_id, recorded_at, occupied_count)
                    VALUES (%s, %s, %s)
                    ON DUPLICATE KEY UPDATE reading_id = reading_id''',
                    (lot_ids[code], recorded, occupied))
                if cursor.rowcount == 1:
                    stats['readings_added'] += 1
                else:
                    stats['duplicates'] += 1
        # Commit only after every row succeeds; failures roll back the import.
        connection.commit()
        return stats
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv_file', nargs='?', default='data/dataset.csv')
    args = parser.parse_args()
    try:
        for key, value in import_csv(args.csv_file).items():
            print(f'{key}: {value}')
    except (OSError, ValueError, mysql.connector.Error) as exc:
        parser.exit(1, f'Import failed: {exc}\n')
