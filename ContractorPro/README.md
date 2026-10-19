# ContractorPro — prototaip interaktif Bahasa Melayu

Apple Light · satu syarikat · MYR. HTML/CSS/JavaScript tanpa proses build.

## Cuba sekarang

1. Ekstrak ZIP. Buka terminal dalam folder ContractorPro.
2. Jika Python tersedia: `python -m http.server 8080`. Atau Node: `node server.cjs`.
3. Buka http://localhost:8080. Jangan gunakan file:// untuk ujian Supabase.

Mod lalai ialah **DEMO: data rekaan sahaja**, disimpan di localStorage pelayar. Tiada pangkalan data jauh digunakan dalam mod ini. Nama pelanggan, syarikat dan transaksi bukan data sebenar. Reset di Tetapan memulihkan demo. Data demo tidak dimuat naik secara automatik ke Supabase.

## Modul dan aliran ujian

- Dashboard: ringkasan kontrak, kutipan, baki, kos, graf nilai projek dan kemajuan.
- Pelanggan/pembekal: tambah, sunting, cari, lihat, eksport.
- Quotation/BOQ: baris kuantiti × kadar, jumlah automatik, status, cetak. Selepas Diluluskan, “Jadi projek” menyediakan borang projek untuk semakan; simpan, kemudian pautkan sebut harga ke projek. Tindakan ini boleh diulang dan belum mempunyai penukaran atomik satu kali.
- Projek: kontrak, bajet, pelanggan dan kemajuan manual.
- Costing/profit: kontrak + VO diluluskan − kos direkodkan; margin mengikut projek. Ini untung unjuran, bukan akaun diaudit.
- VO: nilai tambahan bukan negatif, status kelulusan dan pautan projek.
- Progress claim: nilai kemajuan kumulatif atas kontrak semasa + VO diluluskan, tolak retensi dan jumlah claim terdahulu diluluskan. Jumlah bersih = kontrak × % kemajuan × (1 − % retensi) − claim terdahulu. Claim diluluskan dikunci dalam DB. Tiada pelepasan retensi automatik.
- “Jadi invois” menyediakan borang daripada claim diluluskan; semak dan simpan. Nombor dokumen mesti unik bagi jenisnya di Supabase. Belum ada pencegahan dua invois dengan nombor berbeza bagi satu claim.
- Invois: tarikh akhir, cetak, jumlah dan baki dinamik. Bayaran: berbilang bayaran separa, resit boleh dicetak; jumlah tidak boleh melebihi baki.
- Expenses: kategori, pembekal, projek dan kos. Rekod ini dianggap kos sebenar, bukan purchase order atau lejar akaun belum bayar.
- Reports: ringkasan projek, CSV dan cetakan pelayar (pilih Save as PDF).
- Settings/users: nama paparan tempatan, status sambungan dan matriks peranan. Penyediaan akaun/peranan dibuat dalam Supabase oleh pemilik; tiada butang jemputan pengguna dalam prototaip.

## Sambung pangkalan data PostgreSQL sebenar

1. Cipta projek Supabase sendiri. Dalam SQL Editor, jalankan `schema.sql` **sekali pada projek baharu**. Skema ini bukan migrasi idempotent.
2. Cipta pengguna e-mel/kata laluan dalam Authentication → Users; sahkan e-mel jika diperlukan. Tiada pendaftaran awam dalam UI.
3. Salin UUID pengguna. Jalankan:

```sql
insert into public.profiles(id,role,display_name)
values ('UUID-SEBENAR','admin','Pemilik');
```

4. Dalam `config.js`, isi `url` dengan URL HTTPS projek dan `key` dengan publishable key. Gunakan publishable key/legacy anon sahaja. **Jangan letak secret key atau service_role dalam aplikasi.**
5. Muat semula. Label bertukar SUPABASE. Klik Log masuk Supabase. Pangkalan data bermula kosong; tambah pelanggan → pembekal → projek → dokumen/kos. Tiada fallback ke demo apabila Supabase gagal.
6. Dalam Authentication → URL Configuration tetapkan Site URL dan allowed redirect URLs kepada domain deployment sebenar serta localhost semasa pembangunan. Aplikasi ini menggunakan log masuk kata laluan, bukan magic link. Pemulihan kata laluan boleh diurus pemilik melalui Supabase Dashboard buat masa ini.

Pustaka Supabase dimuat melalui esm.sh; internet diperlukan dalam mod Supabase. Untuk pengeluaran, pin versi tepat yang disahkan dan bundle SDK sendiri, gunakan CSP yang sesuai serta lockfile.

## Skema dan akses

`company`: satu baris syarikat. `profiles`: FK auth.users dan peranan. `records`: id UUID, kind, payload JSONB, pencipta, masa. `audit_log`: sejarah perubahan automatik. Rekod dokumen dan BOQ menggunakan JSONB untuk fleksibiliti prototaip; rujukan pelanggan/projek/pembekal/invois disemak trigger. Ini reka bentuk prototaip, bukan skema perakaunan ternormal penuh. Tiada fail upload atau Supabase Storage.

| Peranan | Baca | Tulis |
|---|---|---|
| admin | Semua modul dan audit | Semua rekod |
| finance | Semua rekod | Pelanggan, pembekal, invois, bayaran, expenses |
| manager | Semua rekod | Pelanggan, projek, quotation, VO, claim |
| viewer | Semua rekod | Tiada |
| Tanpa profil/log masuk | Tiada rekod | Tiada |

RLS diaktifkan pada semua jadual. Profil tidak boleh diubah melalui API browser. Admin aplikasi juga tidak boleh menaikkan peranan melalui API. Pemilik DB mengubah peranan melalui SQL Editor. Audit hanya boleh dibaca admin; trigger yang menulisnya. Tiada delete API. Tiada pemisahan akses kos bagi manager/viewer: kedua-duanya boleh baca semua rekod syarikat, seperti matriks di atas.

Validasi DB: jenis/nombor dokumen, rujukan, amaun tidak negatif, had peratus, jumlah BOQ, pengiraan claim, had bayaran dan nilai invois berbanding bayaran. Advisory lock transaksi menyusun mutasi lejar; sesuai prototaip satu syarikat kecil. Penyuntingan serentak belum mempunyai kawalan versi/optimistic locking, maka suntingan terakhir boleh menindih medan sebelumnya.

## Deployment statik

1. Uji setempat. Isi config.js untuk Supabase sebenar jika diperlukan.
2. Muat naik `index.html`, `style.css`, `app.js`, `config.js` ke hos statik HTTPS (contohnya Netlify, Cloudflare Pages atau Vercel). Tiada build command; direktori publish ialah folder fail ini. Skema SQL dan README tidak perlu dimuat naik ke web root.
3. Tambah domain pada konfigurasi Auth Supabase. Pastikan browser boleh mencapai esm.sh dan endpoint Supabase HTTPS.
4. Uji login setiap peranan, tambah rekod, refresh, logout, dan pastikan tiada data dipaparkan selepas logout. Semak ujian akses SQL dalam `security-checks.sql`.

Fail disediakan untuk deployment sendiri; tiada deployment jauh atau projek Supabase dicipta/dihubungkan oleh pembina. Pemilik menyediakan akaun hosting, projek Supabase dan kunci.

## Had sebelum pengeluaran

Prototaip belum menyokong e-Invoice LHDN, SST/cukai, mata wang berganda, tandatangan, kelulusan berasingan pembuat/penyemak, notifikasi, lampiran, penomboran automatik transaksi, pemulihan kata laluan dalam app, pelepasan retensi, nota kredit/VO negatif, penguncian invois muktamad atau lejar dwi catatan. Pautan penukaran dokumen masih perlu disemak manusia. Perubahan kontrak/VO selepas tuntutan boleh mengubah asas claim seterusnya. Selesaikan keperluan tersebut dan ujian integrasi PostgreSQL sebelum penggunaan kewangan sebenar.

## Sumber konfigurasi

- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/auth/managing-user-data

## Pengesahan yang dibekalkan

`node --check app.js` menyemak sintaks. `node verify.cjs` menjalankan ujian logik demo (BOQ, untung, bayaran separa) dan aset. Ujian sebenar RLS/trigger memerlukan projek PostgreSQL Supabase anda; jalankan `security-checks.sql` selepas konfigurasi. Tiada dakwaan sambungan DB telah diuji tanpa projek tersebut.
