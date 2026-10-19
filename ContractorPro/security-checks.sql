-- Jalankan selepas schema.sql. Ujian transaksi dibatalkan pada penghujung.
-- Gunakan UUID profil sebenar. Jangan jalankan sebagai service_role sahaja
-- kerana ia memintas RLS. Ini skrip semakan manual dengan expected results.
begin;
set local role anon;
-- EXPECT: permission denied (grant anon tiada). Jalankan berasingan untuk melihatnya:
-- select * from public.records;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
-- EXPECT: 0 (pengguna tiada profil)
select count(*) as must_be_zero from public.records;
reset role;
rollback;

-- Semakan manual selepas anda mempunyai empat pengguna/peranan:
-- 1. Log masuk viewer, cubaan insert/update melalui Data API mesti ditolak.
-- 2. Manager boleh tulis projek, tidak boleh tulis payments.
-- 3. Finance boleh tulis payments, tidak boleh tulis variations.
-- 4. Insert/update profiles melalui API oleh mana-mana peranan mesti ditolak.
-- 5. Dua bayaran serentak yang jumlahnya > baki: hanya yang muat baki berjaya.
-- 6. UUID project_id salah/jenis salah mesti ditolak.
-- 7. Ubah amount invois menjadi kurang daripada bayaran sedia ada: ditolak.
-- 8. Edit claim diluluskan: ditolak. Audit log hanya boleh dibaca admin.
