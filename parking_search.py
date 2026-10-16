# ParkSmart - User-Facing Parking Search
# CS 514 Group Project

# This program will display parking lot information
# in a readable table for the user.

# Import the MySQL connector to retrieve real parking data.
import mysql.connector

# Import getpass to securely enter the MySQL password.
from getpass import getpass

# Connect to the ParkSmart MySQL database.
connection = mysql.connector.connect(
    host="localhost",
    user="root",
    password=getpass("Enter your MySQL root password: "),
    database="parking_tracker"
)

# Create a cursor to execute SQL queries.
cursor = connection.cursor()

# Create an empty list to store parking information from MySQL.
parking_lots = []

# Retrieve the parking lot names and capacities from MySQL.
cursor.execute("""
    SELECT
        lot_id,
        COALESCE(display_name, lot_code),
        capacity
    FROM parking_lot
    WHERE capacity > 0
    ORDER BY lot_code
""")

# Store the database results.
database_lots = cursor.fetchall()

# Number each parking lot so we can assign different demo settings.
for index, lot in enumerate(database_lots):

    # Read the information returned by MySQL.
    lot_id = lot[0]
    lot_name = lot[1]

    # Assign simulated parking restrictions for demonstration.
    if index % 3 == 0:
        restriction = "Faculty Only"
    else:
        restriction = "General"

    # Assign simulated parking rates.
    if index % 4 == 0:
        rate = "FREE"
    else:
        rate = "£2/hr"

    # Assign simulated operating hours.
    if index % 2 == 0:
        open_hour = 6
        close_hour = 18
    else:
        open_hour = 7
        close_hour = 22

    # Add the parking lot to our list.
    parking_lots.append({
        "lot_id": lot_id,
        "name": lot_name,
        # Availability will be updated using real MySQL readings.
        "availability": 0.0,

        # The following information is simulated for demonstration.
        "status": "OPEN",
        "restriction": restriction,
        "rate": rate,
        "open_hour": open_hour,
        "close_hour": close_hour
    })

# Ask the user what hour they want to search.
# Use 24-hour time: 8 = 8 AM, 14 = 2 PM.
selected_hour = int(input("Enter the hour you want to search (0-23): "))


# Check that the hour is valid.
if selected_hour < 0 or selected_hour > 23:
    print("Invalid hour. Please enter a number between 0 and 23.")
    exit()

# Retrieve historical average availability for the selected hour.
cursor.execute("""
    SELECT
        p.lot_id,
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
    GROUP BY p.lot_id
""", (selected_hour,))

# Store the availability results from MySQL.
availability_results = cursor.fetchall()

# Create a lookup dictionary using the parking lot ID.
availability_lookup = {
    lot_id: float(average)
    for lot_id, average in availability_results
}

# Update each parking lot with its actual historical availability.
for lot in parking_lots:
    lot["availability"] = availability_lookup.get(lot["lot_id"], 0.0)

# Close the database connection after retrieving the data.
cursor.close()
connection.close()

# Convert the selected hour into 12-hour format.
# Example: 14 becomes 2:00 PM.
if selected_hour == 0:
    display_hour = "12:00 AM"
elif selected_hour < 12:
    display_hour = f"{selected_hour}:00 AM"
elif selected_hour == 12:
    display_hour = "12:00 PM"
else:
    display_hour = f"{selected_hour - 12}:00 PM"

# Ask the user how many parking lots they want to display.
number_of_lots = int(input("How many parking lots would you like to see? "))


# Make sure the number is greater than zero.
if number_of_lots <= 0:
    print("Please enter a number greater than zero.")

    # Stop the program if the number is invalid.
    exit()

# Check each parking lot's operating hours.
for lot in parking_lots:

    # Get the opening and closing hours.
    open_hour = lot["open_hour"]
    close_hour = lot["close_hour"]

    # Determine if the parking lot is open at the selected hour.
    # This also supports operating hours that extend past midnight.
    if open_hour == close_hour:
        lot["status"] = "OPEN"  # Treat equal hours as 24-hour operation.

    elif open_hour < close_hour:
        # Normal operating hours, such as 6 AM to 6 PM.
        if open_hour <= selected_hour < close_hour:
            lot["status"] = "OPEN"
        else:
            lot["status"] = "CLOSED"

    else:
        # Overnight hours, such as 8 PM to 6 AM.
        if selected_hour >= open_hour or selected_hour < close_hour:
            lot["status"] = "OPEN"
        else:
            lot["status"] = "CLOSED"

# Ask the user if they want to include closed parking lots.
show_closed = input(
    "Do you want to include closed parking lots? (yes/no): "
).strip().lower()


# Check if the user entered a valid answer.
if show_closed not in ["yes", "no"]:
    print("Invalid answer. Please enter yes or no.")
    exit()


# Create a new list to store the parking lots that match the user's choice.
filtered_lots = []


# Check each parking lot's status.
for lot in parking_lots:

    # Include all parking lots if the user answered yes.
    if show_closed == "yes":
        filtered_lots.append(lot)

    # Otherwise, include only parking lots that are open.
    elif lot["status"] == "OPEN":
        filtered_lots.append(lot)

# Ask the user what type of parking they want.
parking_type = input(
    "Enter parking type (all/general/faculty): "
).strip().lower()


# Check if the parking type is valid.
if parking_type not in ["all", "general", "faculty"]:
    print("Invalid parking type.")
    exit()

# Create a list for parking lots matching the restriction.
restriction_filtered_lots = []

# Check the restriction for each lot that passed the open/closed filter.
for lot in filtered_lots:

    # Include all parking types if the user chooses "all".
    if parking_type == "all":
        restriction_filtered_lots.append(lot)

    # Include only general parking.
    elif parking_type == "general" and lot["restriction"] == "General":
        restriction_filtered_lots.append(lot)

    # Include only faculty parking.
    elif parking_type == "faculty" and lot["restriction"] == "Faculty Only":
        restriction_filtered_lots.append(lot)

# Ask the user whether they want free or paid parking.
payment_type = input(
    "Enter payment type (all/free/paid): "
).strip().lower()

# Check if the answer is valid.
if payment_type not in ["all", "free", "paid"]:
    print("Invalid payment type.")
    exit()

# Create a list for parking lots matching the payment preference.
payment_filtered_lots = []

# Check the parking lots that passed the previous filters.
for lot in restriction_filtered_lots:

    # Include every parking lot.
    if payment_type == "all":
        payment_filtered_lots.append(lot)

    # Include only free parking lots.
    elif payment_type == "free" and lot["rate"] == "FREE":
        payment_filtered_lots.append(lot)

    # Include only paid parking lots.
    elif payment_type == "paid" and lot["rate"] != "FREE":
        payment_filtered_lots.append(lot)

# Sort parking lots after applying all filters.
sorted_lots = sorted(
    payment_filtered_lots,
    key=lambda lot: lot["availability"],
    reverse=True
)


# Select the number of parking lots requested by the user.
# The program now selects from the sorted list.
selected_lots = sorted_lots[:number_of_lots]

# Display the program title.
print("\nPARKSMART - PARKING SEARCH RESULTS")

# Display the time selected by the user.
print(f"Selected Time: {display_hour}")

# Display a line to separate the title from the results.
print("-" * 85)


# Display the table column headings.
print(
    f"{'Parking Lot':<20}"
    f"{'Availability':<16}"
    f"{'Status':<12}"
    f"{'Restriction':<18}"
    f"{'Rate':<10}"
    f"{'Hours':<18}"
)

# Display another line under the headings.
print("-" * 85)

# Check if any parking lots match the user's search.
if not selected_lots:
    print("No parking lots match your search criteria.")
    print("Try changing the time or parking preferences.")

# Display only the parking lots requested by the user.
for lot in selected_lots:

    # Format the availability percentage to two decimal places.
    availability = f"{lot['availability']:.2f}%"

    # Format the opening and closing hours.
    hours = f"{lot['open_hour']:02d}:00-{lot['close_hour']:02d}:00"

    # Display the parking lot information in aligned columns.
    print(
        f"{lot['name']:<20}"
        f"{availability:<16}"
        f"{lot['status']:<12}"
        f"{lot['restriction']:<18}"
        f"{lot['rate']:<10}"
        f"{hours:<18}"
    )


# Display a closing line at the bottom of the table.
print("-" * 85)

# Explain where the parking information comes from.
print()
print("DATA SOURCE INFORMATION")
print("Availability: Historical UCI parking data stored in MySQL.")
print("Restrictions, rates, and operating hours: Simulated for demonstration.")
print("Results are historical averages, not live parking availability.")