import csv
import os
from datetime import datetime, timedelta
import random
from supabase import create_client, Client

# Initialize Supabase client
url = "https://fnxirlpiqciezifongxb.supabase.co"
key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZueGlybHBpcWNpZXppZm9uZ3hiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYzNjIxMzgsImV4cCI6MjA1MTkzODEzOH0.qbqwZJr9ufNbs3mjQHFuJMNlef-mUwBNoCaoeuHDGhM"
supabase: Client = create_client(url, key)

def fetch_students():
    """Fetch all students from the database."""
    response = supabase.table('student').select('student_reg_no, dept_id').execute()
    return response.data

def fetch_courses():
    """Fetch all courses from the database."""
    response = supabase.table('course').select('course_code, dept_id').execute()
    return response.data

def fetch_exams():
    """Fetch all exams from the database."""
    response = supabase.table('exam').select('exam_id, course_id').execute()
    return response.data

def generate_course_registrations():
    """Generate course registrations for students."""
    students = fetch_students()
    courses = fetch_courses()
    
    print(f"Found {len(students)} students")
    print(f"Found {len(courses)} courses")
    
    # Group courses by department
    dept_courses = {}
    for course in courses:
        dept = course['dept_id']
        if dept not in dept_courses:
            dept_courses[dept] = []
        dept_courses[dept].append(course['course_code'])
    
    registrations = []
    future_date = datetime(2025, 1, 10, 16, 0, 16, 130197)
    timestamp = future_date.isoformat() + '+00'
    
    # For each student
    for student in students:
        student_dept = student['dept_id']
        student_reg_no = student['student_reg_no']
        
        # Get courses for student's department
        dept_course_list = dept_courses.get(student_dept, [])
        if not dept_course_list:
            continue
        
        # Register for 3-4 courses from their department
        num_courses = random.randint(3, 4)
        selected_courses = random.sample(dept_course_list, min(num_courses, len(dept_course_list)))
        
        # Add some courses from other departments (20% chance)
        if random.random() < 0.2:
            other_depts = [d for d in dept_courses.keys() if d != student_dept]
            if other_depts:
                other_dept = random.choice(other_depts)
                other_courses = dept_courses[other_dept]
                if other_courses:
                    other_course = random.choice(other_courses)
                    selected_courses.append(other_course)
        
        # Create registrations for selected courses
        for course_code in selected_courses:
            # 80% chance of being a regular course
            is_regular = random.random() < 0.8
            
            registration = {
                'student_reg_no': student_reg_no,
                'course_code': course_code,
                'created_at': timestamp,
                'updated_at': timestamp,
                'is_reguler': is_regular
            }
            registrations.append(registration)
    
    print(f"Generated {len(registrations)} course registrations")
    return registrations

def generate_exam_registrations(course_registrations):
    """Generate exam registrations based on course registrations."""
    exams = fetch_exams()
    print(f"Found {len(exams)} exams")
    
    # Group exams by course
    course_exams = {}
    for exam in exams:
        course_id = exam['course_id']
        if course_id not in course_exams:
            course_exams[course_id] = []
        course_exams[course_id].append(exam['exam_id'])
    
    registrations = []
    future_date = datetime(2025, 1, 10, 16, 0, 16, 130197)
    timestamp = future_date.isoformat() + '+00'
    
    # Create a map of student to courses
    student_courses = {}
    for reg in course_registrations:
        student_reg_no = reg['student_reg_no']
        if student_reg_no not in student_courses:
            student_courses[student_reg_no] = []
        student_courses[student_reg_no].append(reg['course_code'])
    
    # For each student
    for student_reg_no, courses in student_courses.items():
        # Register for exams of registered courses
        for course_code in courses:
            # Get available exams for this course
            available_exams = course_exams.get(course_code, [])
            if not available_exams:
                continue
            
            # Register for all available exams of the course
            for exam_id in available_exams:
                registration = {
                    'student_reg_no': student_reg_no,
                    'exam_id': exam_id,
                    'created_at': timestamp,
                    'updated_at': timestamp,
                    'status': random.choice(['REGISTERED', 'REGISTERED', 'REGISTERED', 'ABSENT'])  # 75% chance of REGISTERED
                }
                registrations.append(registration)
    
    print(f"Generated {len(registrations)} exam registrations")
    return registrations

def write_to_csv(registrations, filename):
    """Write registrations to CSV file."""
    if not registrations:
        return
        
    fieldnames = list(registrations[0].keys())
    
    os.makedirs('scripts', exist_ok=True)
    filepath = os.path.join('scripts', filename)
    
    with open(filepath, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(registrations)
    
    print(f"Generated {len(registrations)} records in {filepath}")
    
    if 'status' in fieldnames:  # For exam registrations
        # Print registration summary
        student_count = len({reg['student_reg_no'] for reg in registrations})
        exam_count = len({reg['exam_id'] for reg in registrations})
        status_count = {}
        for reg in registrations:
            status = reg['status']
            status_count[status] = status_count.get(status, 0) + 1
        
        print("\nRegistration Summary:")
        print(f"Total Students: {student_count}")
        print(f"Total Exams: {exam_count}")
        print("\nStatus Distribution:")
        for status, count in status_count.items():
            percentage = (count / len(registrations)) * 100
            print(f"{status}: {count} ({percentage:.1f}%)")

def main():
    """Main function to generate and save registrations."""
    try:
        # First generate course registrations
        course_registrations = generate_course_registrations()
        write_to_csv(course_registrations, 'course_registrations.csv')
        
        # Then generate exam registrations based on course registrations
        exam_registrations = generate_exam_registrations(course_registrations)
        write_to_csv(exam_registrations, 'exam_registrations.csv')
        
        print("\nRegistration data generated successfully!")
    except Exception as e:
        print(f"Error generating registrations: {str(e)}")

if __name__ == "__main__":
    main() 