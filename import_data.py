# Import Python's built-in CSV module so we can read the dataset
import csv
# Import SQLite so Python can create and work with our database
import sqlite3

# Connect to the SQLite database
# If parksmart.db does not exist, Python will create it automatically
connection = sqlite3.connect("parksmart.db")

# Create a cursor that allows Python to send commands to SQLite
cursor = connection.cursor()

# Create the parking_location table
# parking_id is the primary key
# system_code identifies parking location; UNIQUE prevents accidentally creating system_code hundreds of times
# capacity stores how many spaces that parking location can hold
cursor.execute("""
    CREATE TABLE IF NOT EXISTS parking_location (
        parking_id INTEGER PRIMARY KEY AUTOINCREMENT,
        system_code TEXT NOT NULL UNIQUE,
        capacity INTEGER NOT NULL
    )
""")

# Create the parking_record table
# This table stores the occupancy measurements for each parking location
cursor.execute("""
    CREATE TABLE IF NOT EXISTS parking_record (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        parking_id INTEGER NOT NULL,
        record_datetime TEXT NOT NULL,
        occupancy INTEGER NOT NULL,

        FOREIGN KEY (parking_id)
            REFERENCES parking_location(parking_id)
    )
""")

# Count duplicate parking records before creating the unique index
cursor.execute("""
    SELECT COUNT(*)
    FROM (
        SELECT parking_id, record_datetime
        FROM parking_record
        GROUP BY parking_id, record_datetime
        HAVING COUNT(*) > 1
    )
""")

# Get the number of duplicate parking location/time combinations
duplicate_count = cursor.fetchone()[0]

# Display the number of duplicates
print("Duplicate parking records:", duplicate_count)

# Save the changes to the database
connection.commit()

print("Connected to ParkSmart database!")
print()

# Clear existing parking records before importing the CSV
# This prevents the entire dataset from being duplicated
# if this import program is run more than once
cursor.execute("DELETE FROM parking_record")

# Save the deletion before starting the new import
connection.commit()

# Open the Birmingham parking CSV file
with open("data/dataset.csv", "r") as file:

    # Read the CSV using the column names as keys
    reader = csv.DictReader(file)

    # Loop through each row in the CSV
    # "i" keeps track of the row number
    # "row" contains the parking data for that row
    for i, row in enumerate(reader):

        # Convert capacity and occupancy from text into numbers
        capacity = int(row["Capacity"])
        occupancy = int(row["Occupancy"])

        # Calculate the number of available parking spaces
        available = capacity - occupancy

        # Get the parking lot's system code from the CSV
        system_code = row["SystemCodeNumber"]

        # Insert the parking location into SQLite
        # INSERT OR IGNORE prevents duplicate parking locations
        cursor.execute("""
            INSERT OR IGNORE INTO parking_location (system_code, capacity)
            VALUES (?, ?)
        """, (system_code, capacity))

        # Find the parking_id that belongs to this system code
        cursor.execute("""
            SELECT parking_id
            FROM parking_location
            WHERE system_code = ?
        """, (system_code,))

        # Get the parking_id returned by SQLite
        parking_id = cursor.fetchone()[0]

        # Get the date and time of this parking measurement
        record_datetime = row["LastUpdated"]

        # Insert the occupancy measurement into parking_record
        cursor.execute("""
            INSERT INTO parking_record (parking_id, record_datetime, occupancy)
            VALUES (?, ?, ?)
        """, (parking_id, record_datetime, occupancy))

# Save all inserted parking locations to the database
connection.commit()

print("Parking locations imported successfully!")
print()

# Ask SQLite to count how many parking locations are in the database
cursor.execute("SELECT COUNT(*) FROM parking_location")

# Get the result returned by SQLite
location_count = cursor.fetchone()[0]

# Display the number of parking locations
print("Total parking locations:", location_count)

# Count how many parking records were imported
cursor.execute("SELECT COUNT(*) FROM parking_record")

# Get the total number of parking records
record_count = cursor.fetchone()[0]

# Display the total number of parking records
print("Total parking records:", record_count)

# Close the database connection
connection.close()