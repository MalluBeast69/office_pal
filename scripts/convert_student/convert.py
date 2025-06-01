import pandas as pd
from datetime import datetime

# Define department mapping
department_mapping = {
    "STATISTICS": "DPST",
    "PHYSICS": "DPPY",
    "CHEMISTRY": "DPCH",
    "ELECTRONICS": "DPEL",
    "COMPUTER SCIENCE": "DPCS",
    "MATHEMATICS": "DPMT",
    "ECONOMICS": "DPEC",
    "BACHELOR OF COMPUTER APPLICATION": "DPCA"
}

# Read the Excel file, skipping the first 3 rows (headers before column names)
df = pd.read_excel("2016 admission.xlsx", header=None, skiprows=3)

# Initialize variables
current_dept = None
students = []

# Get current timestamp
now = datetime.now().isoformat() + "+00"

# Iterate through rows
for index, row in df.iterrows():
    first_cell = row[0]
    # Check if the row is a department name
    if isinstance(first_cell, str) and first_cell.strip().upper() in department_mapping:
        current_dept = first_cell.strip().upper()
    # Check if it’s a student row (Register Number in column 1 is not NaN)
    elif current_dept and pd.notna(row[1]):
        student_reg_no = row[1]  # Register Number
        student_name = row[2]    # Student Name
        dept_id = department_mapping[current_dept]
        semester = "1"
        created_at = now
        updated_at = now
        students.append([student_reg_no, student_name, dept_id, semester, created_at, updated_at])

# Create a DataFrame
student_df = pd.DataFrame(students, columns=[
    "student_reg_no", "student_name", "dept_id", "semester", "created_at", "updated_at"
])

# Write to CSV
student_df.to_csv("Student information.csv", index=False)

print("Conversion complete. 'Student information.csv' has been created.")