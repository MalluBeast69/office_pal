CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    type VARCHAR NOT NULL,
    from_faculty_id VARCHAR REFERENCES faculty(faculty_id),
    title VARCHAR NOT NULL,
    message TEXT NOT NULL,
    status VARCHAR NOT NULL DEFAULT 'pending',
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add RLS policies
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Allow superintendents to read and update all notifications
CREATE POLICY "Superintendents can read all notifications" ON notifications
    FOR SELECT USING (auth.role() = 'superintendent');

CREATE POLICY "Superintendents can update notifications" ON notifications
    FOR UPDATE USING (auth.role() = 'superintendent');

-- Allow faculty to create notifications and read their own
CREATE POLICY "Faculty can create notifications" ON notifications
    FOR INSERT WITH CHECK (auth.role() = 'faculty');

CREATE POLICY "Faculty can read their own notifications" ON notifications
    FOR SELECT USING (
        auth.role() = 'faculty' AND
        from_faculty_id = auth.uid()
    );

-- Create trigger for updated_at
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_updated_at(); 