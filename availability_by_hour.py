# Import SQLite so Python can communicate with the ParkSmart database
import sqlite3


# Connect to the existing ParkSmart database
connection = sqlite3.connect("parksmart.db")

# Create a cursor so Python can send SQL queries to SQLite
cursor = connection.cursor()


# Calculate average parking availability percentage for each hour
cursor.execute("""
    SELECT
        strftime('%H', parking_record.record_datetime) AS hour,

        AVG(
            (parking_location.capacity - parking_record.occupancy)
            * 100.0 / parking_location.capacity
        ) AS average_available_percentage

    FROM parking_record

    JOIN parking_location
        ON parking_record.parking_id = parking_location.parking_id

    GROUP BY hour
    ORDER BY hour
""")

# Get all results returned by the database
hourly_results = cursor.fetchall()


print("Average Parking Availability Percentage by Hour")
print("-----------------------------------------------")


# Display the average availability for each hour
for result in hourly_results:

    # Get the hour and average availability percentage
    hour = result[0]
    average_percentage = result[1]

    # Display the results
    print(
        hour + ":00",
        "- Average Availability:",
        round(average_percentage, 2),
        "%"
    )


# Close the database connection
connection.close()