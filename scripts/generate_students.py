import csv
from faker import Faker
import random
from datetime import datetime, timezone

fake = Faker()

# Configuration
STUDENTS_PER_DEPARTMENT = 40  # This will give us 760 students total (19 departments * 40 students)
DEPARTMENTS = [
    "DPCS", "DPEC", "DPME", "DPCE", "DPEE", "DPBT", "DPCH", "DPIT", 
    "DPMT", "DPEN", "DPAE", "DPBM", "DPMS", "DPNT", "DPPH", "DPCE2", 
    "DPSE", "DPME2", "DPGE"
]
SEMESTERS = list(range(1, 9))  # 1 to 8
TIMESTAMP = "2025-01-08 18:59:44.216368+00"  # Using a fixed timestamp for consistency

# Starting number for each department to avoid conflicts
START_NUMBER = 600

def generate_student_reg_no(dept_id, count):
    """Generate a student registration number in the format THAWSXX### where XX is dept code"""
    dept_code = dept_id[2:]  # Remove 'DP' prefix
    student_number = START_NUMBER + count
    return f"THAWS{dept_code}{str(student_number).zfill(3)}"

# Prepare the CSV file
fields = ["student_reg_no", "student_name", "dept_id", "semester", "created_at", "updated_at"]

with open("scripts/students.csv", "w", newline="", encoding='utf-8') as file:
    writer = csv.writer(file)
    writer.writerow(fields)  # Write header

    # For each department
    for dept_id in DEPARTMENTS:
        # Generate STUDENTS_PER_DEPARTMENT students for this department
        for i in range(1, STUDENTS_PER_DEPARTMENT + 1):
            student_reg_no = generate_student_reg_no(dept_id, i)
            student_name = fake.name()
            semester = random.choice(SEMESTERS)
            
            # Write the student record
            writer.writerow([
                student_reg_no,
                student_name,
                dept_id,
                semester,
                TIMESTAMP,
                TIMESTAMP
            ])

print(f"Generated {len(DEPARTMENTS) * STUDENTS_PER_DEPARTMENT} students successfully!")
print(f"CSV file has been created at scripts/students.csv")
print(f"Registration numbers start from {START_NUMBER} for each department to avoid conflicts.") 