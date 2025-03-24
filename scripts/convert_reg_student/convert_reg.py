import pandas as pd
from datetime import datetime
import random

# Read course.csv and create a set of valid course codes
course_df = pd.read_csv("course.csv")
valid_course_codes = set(course_df["course_code"].str.strip())

# Read the Excel file, setting the header row (4th row, 0-based index 3)
df = pd.read_excel("2016 admission.xlsx", header=3)

# Initialize an empty list to store registration entries
registration = []

# Get the current UTC timestamp with milliseconds
now = datetime.utcnow().isoformat()[:-3] + "+00"

# Iterate through each row in the DataFrame
for index, row in df.iterrows():
    # Check if the row is a student row by ensuring 'Register Number' is not NaN
    if pd.notna(row['Register Number']):
        # Extract and clean the registration number and course codes
        student_reg_no = str(row['Register Number']).strip()
        major_code = str(row['MAJOR CODE']).strip()
        minor_code = str(row['MINOR 1 CODE']).strip()
        mdc_code = str(row['MDC CODE']).strip()
        
        # List of course codes for this student
        course_codes = [major_code, minor_code, mdc_code]
        
        # Create registration entries only for valid course codes
        for course_code in course_codes:
            if course_code in valid_course_codes:
                # Set is_regular to "false" with 1% probability, "true" otherwise
                is_regular = "false" if random.random() < 0.01 else "true"
                # Append the entry to the registration list
                registration.append([student_reg_no, course_code, now, now, is_regular])

# Define the column headers for the CSV
columns = ["student_reg_no", "course_code", "created_at", "updated_at", "is_regular"]

# Create a DataFrame from the registration list
registration_df = pd.DataFrame(registration, columns=columns)

# Write the DataFrame to a CSV file named "registration.csv"
registration_df.to_csv("registration.csv", index=False)

print("Conversion complete. 'registration.csv' has been created.")