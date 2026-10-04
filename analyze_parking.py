# Import SQLite so Python can communicate with our ParkSmart database
import sqlite3


# Connect to the existing ParkSmart SQLite database
connection = sqlite3.connect("parksmart.db")

# Create a cursor so Python can send SQL queries to the database
cursor = connection.cursor()

print("Connected to ParkSmart database!")
print()

# Join parking_location and parking_record together
# This lets us see the parking lot information and its occupancy records
cursor.execute("""
    SELECT
        parking_location.system_code,
        parking_location.capacity,
        parking_record.occupancy,
        parking_record.record_datetime
    FROM parking_record
    JOIN parking_location
        ON parking_record.parking_id = parking_location.parking_id
    ORDER BY parking_record.record_datetime
    LIMIT 5
""")

# Get all rows returned by the SQL query
parking_records = cursor.fetchall()


# Loop through the first 5 parking records
for record in parking_records:

    # Store each returned value in an easy-to-understand variable
    system_code = record[0]
    capacity = record[1]
    occupancy = record[2]
    record_datetime = record[3]

    # Calculate how many parking spaces were available
    available = capacity - occupancy

    # Display the parking information
    print("Parking Lot:", system_code)
    print("Capacity:", capacity)
    print("Occupancy:", occupancy)
    print("Available Spaces:", available)
    print("Date/Time:", record_datetime)
    print()


# Close the database connection when we are finished
connection.close()