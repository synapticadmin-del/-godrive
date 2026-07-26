-- 0008: Add rejection_reason to driver_documents
-- Stores the preset or custom rejection reason from the admin verification modal.
-- This column is written by POST /admin/captains/:id/documents/:docId/reject
-- and by the legacy POST /admin/documents/:id/review when status = 'rejected'.

ALTER TABLE driver_documents ADD COLUMN rejection_reason TEXT;
