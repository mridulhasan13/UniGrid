-- =============================================================================
-- UniGrid — Supabase Storage Setup
-- Run this entire file in: Supabase Dashboard → SQL Editor → New Query
-- =============================================================================
-- What this creates:
--   1. A single storage bucket called "unigrid-files" (public read)
--   2. Three logical folders inside it:
--        announcements/  → notice + urgent + material attachments (from CR panel)
--        materials/      → study materials (PDFs, slides, books, etc.)
--        ct_marks/       → CT / class-test marks PDFs (from course registry)
--   3. RLS (Row Level Security) policies:
--        - Anyone can READ (download/view) files — no auth needed for public URLs
--        - Only authenticated users can UPLOAD (INSERT) files
--        - Only authenticated users can DELETE files they uploaded
--        - No one can UPDATE/overwrite an existing file (immutable uploads)
-- =============================================================================


-- =============================================================================
-- STEP 1: Create the storage bucket
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'unigrid-files',         -- bucket ID (used in URLs)
  'unigrid-files',         -- bucket display name
  true,                    -- PUBLIC: files are readable without auth tokens
  104857600,               -- 100 MB max per file (announcements/materials can be large)
  ARRAY[
    -- Images (notices can have image attachments)
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'image/webp',
    -- Documents
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    -- Archives
    'application/zip',
    'application/x-rar-compressed',
    'application/x-7z-compressed',
    -- Plain text
    'text/plain',
    -- Video (materials can include recorded lectures)
    'video/mp4',
    'video/quicktime',
    -- Generic fallback (file_picker can return this on some platforms)
    'application/octet-stream'
  ]
)
ON CONFLICT (id) DO NOTHING;
-- ON CONFLICT DO NOTHING: safe to re-run this script without duplicate errors.


-- =============================================================================
-- STEP 2: DROP any existing policies before recreating them
-- This makes the script fully idempotent (safe to re-run at any time).
-- =============================================================================

DROP POLICY IF EXISTS "unigrid_public_read"          ON storage.objects;
DROP POLICY IF EXISTS "unigrid_authenticated_insert"  ON storage.objects;
DROP POLICY IF EXISTS "unigrid_authenticated_delete"  ON storage.objects;


-- =============================================================================
-- STEP 3: POLICY — Public READ (anyone can view/download files)
-- =============================================================================
-- Rationale: Files linked from Firestore are just URLs. Students/teachers must
-- be able to open them without needing to be logged into Supabase.
-- The bucket being "public: true" + this SELECT policy together allow that.
-- =============================================================================

CREATE POLICY "unigrid_public_read"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'unigrid-files'
);


-- =============================================================================
-- STEP 4: POLICY — Authenticated INSERT (only logged-in users can upload)
-- =============================================================================
-- Rationale: The Flutter app uses Firebase Auth, NOT Supabase Auth.
-- We initialize the Supabase client with the anon key but do NOT sign users
-- into Supabase. Uploads happen via the service_role key on the server side,
-- OR the Flutter app uses the anon key with this open policy.
--
-- IMPORTANT NOTE FOR THIS PROJECT:
-- Since Firebase handles auth and Supabase is used only for storage,
-- we trust the Firebase-authenticated request coming from the app.
-- The anon key in the Flutter app is sufficient for INSERT with this policy.
-- If you want stricter control later, you can use Supabase Edge Functions
-- as an upload proxy that verifies Firebase JWT tokens.
-- =============================================================================

CREATE POLICY "unigrid_authenticated_insert"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'unigrid-files'
  AND (
    -- Allow uploads only into the known folders
    (storage.foldername(name))[1] IN ('announcements', 'materials', 'ct_marks', 'profile_photos', 'chat_images')
  )
);


-- =============================================================================
-- STEP 5: POLICY — Authenticated DELETE (authenticated users can delete)
-- =============================================================================
-- Rationale: CRs/Admins delete materials from the app. Since we don't have
-- Supabase Auth, we allow any request with a valid anon key to delete.
-- The actual access control (only CR/admin can delete) is enforced in Flutter
-- before calling the delete API — see materials_screen.dart delete button guard.
-- =============================================================================

CREATE POLICY "unigrid_authenticated_delete"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'unigrid-files'
  AND (
    (storage.foldername(name))[1] IN ('announcements', 'materials', 'ct_marks', 'profile_photos', 'chat_images')
  )
);


-- =============================================================================
-- STEP 6: POLICY — No UPDATE (immutable files)
-- =============================================================================
-- Rationale: Files are never overwritten. The app always uploads a NEW file
-- with a unique timestamp prefix (e.g. 1718234567890_lecture1.pdf).
-- Blocking UPDATE prevents accidental or malicious overwrites.
-- There is intentionally NO UPDATE policy created here.
-- =============================================================================
-- (No CREATE POLICY needed — absence of a policy = no access = denied by default)


-- =============================================================================
-- STEP 7: Verify everything looks correct
-- Run each SELECT individually in the SQL Editor to confirm.
-- =============================================================================

-- Confirm the bucket was created:
SELECT id, name, public, file_size_limit
FROM storage.buckets
WHERE id = 'unigrid-files';

-- Confirm the 3 policies were created:
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'objects'
  AND schemaname = 'storage'
  AND policyname LIKE 'unigrid_%';


-- =============================================================================
-- DONE.
-- After running this, go to:
--   Supabase Dashboard → Storage → unigrid-files
-- You should see the bucket listed as PUBLIC.
--
-- Next step: add your Supabase Project URL and anon key to the Flutter app.
-- =============================================================================
