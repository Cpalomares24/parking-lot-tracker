"""Calculate average hourly parking availability using MySQL."""

import mysql.connector

from import_data import connect


def availability_by_hour():
    """Calculate average availability percentages for each hour."""

    connection = connect()

    try:
        cursor = connection.cursor()

        # The occupancy view provides readings and data-quality flags.
        # Exclude invalid readings from availability calculations while
        # preserving them in the database for future analysis.
        cursor.execute("""
            SELECT
                HOUR(recorded_at) AS hour,
                AVG(
                    (CAST(capacity AS SIGNED) - occupied_count)
                    * 100.0 / capacity
                ) AS average_available_percentage
            FROM v_occupancy
            WHERE quality_flag = 'OK'
            GROUP BY HOUR(recorded_at)
            ORDER BY hour
        """)

        hourly_results = cursor.fetchall()

        print("Average Parking Availability Percentage by Hour")
        print("-----------------------------------------------")

        # Display each hour in 24-hour format.
        for hour, average_percentage in hourly_results:
            print(
                f"{hour:02d}:00",
                "- Average Availability:",
                round(average_percentage, 2),
                "%"
            )

    finally:
        connection.close()


if __name__ == "__main__":
    try:
        availability_by_hour()
    except mysql.connector.Error as exc:
        print(f"Database error: {exc}")
        raise SystemExit(1) from exc