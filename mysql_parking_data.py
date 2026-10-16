# Import the MySQL connector library.
import mysql.connector

# Import getpass to keep the password hidden.
from getpass import getpass

# Connect to the ParkSmart MySQL database.
connection = mysql.connector.connect(
    host="localhost",
    user="root",
    password=getpass("Enter your MySQL root password: "),
    database="parking_tracker"
)

# Create a cursor for running SQL queries.
cursor = connection.cursor()

# Ask the user which hour they want to search.
selected_hour = int(input("Enter the hour (0-23): "))

# Calculate average parking availability for each lot at that hour.
cursor.execute("""
    SELECT
        p.lot_code,
        p.capacity,
        ROUND(
            AVG(
                (CAST(p.capacity AS SIGNED) - r.occupied_count)
                * 100.0 / p.capacity
            ), 2
        ) AS average_availability
    FROM parking_lot AS p
    JOIN occupancy_reading AS r
        ON p.lot_id = r.lot_id
    WHERE p.capacity > 0
      AND r.occupied_count BETWEEN 0 AND p.capacity
      AND HOUR(r.recorded_at) = %s
    GROUP BY p.lot_id, p.lot_code, p.capacity
    ORDER BY average_availability DESC
    LIMIT 5
""", (selected_hour,))

# Store the results returned by MySQL.
parking_lots = cursor.fetchall()

# Display the retrieved parking lots.
print("\nPARKSMART - MYSQL PARKING LOTS")
print("-" * 40)

# Display the five parking lots with the highest availability.
for lot in parking_lots:

    # Read the values returned from MySQL.
    lot_code = lot[0]
    capacity = lot[1]
    availability = lot[2]

    # Display the parking information.
    print(
        f"{lot_code} | "
        f"Capacity: {capacity} | "
        f"Average Availability: {availability:.2f}%"
    )

# Close the cursor and database connection.
cursor.close()
connection.close()