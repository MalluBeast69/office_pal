import os
from datetime import datetime, timedelta
import csv
from supabase import create_client, Client
import random

# Initialize Supabase client
url = "https://fnxirlpiqciezifongxb.supabase.co"
key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZueGlybHBpcWNpZXppZm9uZ3hiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYzNjIxMzgsImV4cCI6MjA1MTkzODEzOH0.qbqwZJr9ufNbs3mjQHFuJMNlef-mUwBNoCaoeuHDGhM"
supabase: Client = create_client(url, key)

def fetch_courses():
    """Fetch all courses with their department info from the course table."""
    response = supabase.table('course').select(
        'course_code, dept_id, exam_duration'
    ).execute()
    return response.data

def generate_exam_id(course_code: str, counter: int) -> str:
    """Generate a unique exam ID."""
    return f"EX{course_code}{counter}"

def generate_exams():
    """Generate exam records for 1 week with multiple exams per session."""
    courses = fetch_courses()
    if not courses:
        print("No courses found!")
        return []
    
    # Group courses by department
    dept_courses = {}
    for course in courses:
        dept = course['dept_id']
        if dept not in dept_courses:
            dept_courses[dept] = []
        dept_courses[dept].append({
            'course_code': course['course_code'],
            'duration': course.get('exam_duration', 120)  # Use exam_duration from course if available
        })
    
    exams = []
    start_date = datetime.now().date()
    counter = random.randint(1000, 9999)  # Random starting counter for exam IDs
    
    # Define the week's worth of dates (excluding weekends)
    dates = []
    current_date = start_date
    while len(dates) < 5:  # Get 5 weekdays
        if current_date.weekday() < 5:  # Monday to Friday
            dates.append(current_date)
        current_date += timedelta(days=1)
    
    sessions = [
        ('MORNING', '09:00:00'),
        ('AFTERNOON', '14:00:00')
    ]
    
    # For each date
    for exam_date in dates:
        # For each session
        for session, time in sessions:
            # Randomly select 2-4 departments to have exams in this session
            active_depts = random.sample(list(dept_courses.keys()), 
                                      min(random.randint(2, 4), len(dept_courses)))
            
            # For each selected department
            for dept in active_depts:
                # Schedule 2-3 exams from this department in this session
                available_courses = dept_courses[dept]
                if not available_courses:
                    continue
                
                num_exams = min(random.randint(2, 3), len(available_courses))
                selected_courses = random.sample(available_courses, num_exams)
                
                # Create exams for selected courses
                for course in selected_courses:
                    # Use course's exam duration or default to random choice
                    duration = course['duration'] or random.choice([120, 150])
                    
                    # Generate timestamps for next year
                    future_date = datetime.now() + timedelta(days=365)
                    created_at = future_date.isoformat() + "+00"
                    updated_at = created_at
                    
                    exam = {
                        'exam_id': generate_exam_id(course['course_code'], counter),
                        'course_id': course['course_code'],
                        'exam_date': exam_date.isoformat(),
                        'session': session,
                        'time': time,
                        'duration': duration,
                        'created_at': created_at,
                        'updated_at': updated_at
                    }
                    exams.append(exam)
                    counter += 1
                    
                    # Remove the course from available courses
                    dept_courses[dept].remove(course)
    
    return exams

def write_to_csv(exams, filename='exams.csv'):
    """Write exam records to CSV file."""
    if not exams:
        return
    
    fieldnames = ['exam_id', 'course_id', 'exam_date', 'session', 'time', 
                  'duration', 'created_at', 'updated_at']
    
    os.makedirs('scripts', exist_ok=True)
    filepath = os.path.join('scripts', filename)
    
    with open(filepath, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(exams)
    
    print(f"Generated {len(exams)} exam records in {filepath}")

def main():
    print("Fetching courses...")
    exams = generate_exams()
    print(f"Generated {len(exams)} exam records")
    
    # Print summary of exams by date and session
    exam_summary = {}
    for exam in exams:
        date = exam['exam_date']
        session = exam['session']
        if date not in exam_summary:
            exam_summary[date] = {'MORNING': 0, 'AFTERNOON': 0}
        exam_summary[date][session] += 1
    
    print("\nExam Distribution:")
    for date in sorted(exam_summary.keys()):
        print(f"\nDate: {date}")
        for session in ['MORNING', 'AFTERNOON']:
            count = exam_summary[date][session]
            print(f"  {session}: {count} exams")
    
    write_to_csv(exams)
    print("\nDone!")

if __name__ == "__main__":
    main() 