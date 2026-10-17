"""Retrieve parking occupancy records from MySQL."""

import mysql.connector

from import_data import connect


def analyze_parking():
    """Retrieve and display five valid parking occupancy readings."""

    connection = connect()

    try:
        cursor = connection.cursor()

        # The view joins parking lots with their occupancy readings
        # and identifies invalid measurements using quality_flag.
        cursor.execute("""
            SELECT
                lot_code,
                capacity,
                occupied_count,
                recorded_at
            FROM v_occupancy
            WHERE quality_flag = 'OK'
            ORDER BY recorded_at
            LIMIT 5
        """)

        parking_records = cursor.fetchall()

        # Calculate available spaces using the recorded occupancy.
        for lot_code, capacity, occupancy, recorded_at in parking_records:
            available = capacity - occupancy

            print("Parking Lot:", lot_code)
            print("Capacity:", capacity)
            print("Occupancy:", occupancy)
            print("Available Spaces:", available)
            print("Date/Time:", recorded_at)
            print()

    finally:
        connection.close()


if __name__ == "__main__":
    try:
        analyze_parking()
    except mysql.connector.Error as exc:
        print(f"Database error: {exc}")
        raise SystemExit(1) from exc