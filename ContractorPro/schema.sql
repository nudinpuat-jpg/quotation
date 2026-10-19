-- ContractorPro v1. Jalankan sekali pada projek Supabase baharu.
begin;
create table public.company (
 id boolean primary key default true check(id), name text not null,
 currency text not null default 'MYR' check(currency='MYR')
);
insert into public.company(name) values ('CP Bina Enterprise');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('admin','finance','manager','viewer')),
 display_name text not null default ''
);
-- Jenis dokumen dibezakan secara eksplisit. Payload JSONB membenarkan
-- medan khusus modul; semua rujukan, amaun & akses disemak oleh trigger/RLS.
create table public.records (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('customers','suppliers','projects','quotations','variations','claims','invoices','payments','expenses')),
 data jsonb not null check(jsonb_typeof(data)='object'),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 created_by uuid default auth.uid() references auth.users(id)
);
create index records_kind on public.records(kind);
create index records_data on public.records using gin(data);
create unique index document_number on public.records(kind,lower(data->>'name'))
 where kind in ('quotations','variations','claims','invoices','payments');
create table public.audit_log (
 id bigint generated always as identity primary key,
 actor uuid, record_id uuid not null, operation text not null,
 before_data jsonb, after_data jsonb, at timestamptz not null default now()
);
create function public.cp_role() returns text language sql stable security definer
set search_path=public as $$ select role from public.profiles where id=auth.uid() $$;
revoke all on function public.cp_role() from public;
grant execute on function public.cp_role() to authenticated;
create function public.cp_can_write(k text) returns boolean language sql stable as $$
 select coalesce(public.cp_role()='admin'
 or (public.cp_role()='finance' and k in ('customers','suppliers','invoices','payments','expenses'))
 or (public.cp_role()='manager' and k in ('customers','projects','quotations','variations','claims')),false)
$$;
revoke all on function public.cp_can_write(text) from public;
grant execute on function public.cp_can_write(text) to authenticated;
alter table public.company enable row level security;
alter table public.profiles enable row level security;
alter table public.records enable row level security;
alter table public.audit_log enable row level security;
create policy company_read on public.company for select to authenticated using(public.cp_role() is not null);
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.cp_role()='admin');
-- Tiada polisi INSERT/UPDATE profil: peranan hanya boleh ditetapkan oleh pemilik DB.
create policy records_read on public.records for select to authenticated using(public.cp_role() is not null);
create policy records_insert on public.records for insert to authenticated with check(public.cp_can_write(kind));
create policy records_update on public.records for update to authenticated using(public.cp_can_write(kind)) with check(public.cp_can_write(kind));
-- Tiada delete API: mengelakkan rekod kewangan hilang atau rujukan yatim.
create policy audit_read on public.audit_log for select to authenticated using(public.cp_role()='admin');
revoke all on public.company,public.profiles,public.records,public.audit_log from anon,authenticated;
grant select on public.company,public.profiles,public.audit_log to authenticated;
grant select,insert,update on public.records to authenticated;
create function public.cp_validate() returns trigger language plpgsql security definer
set search_path=public as $$
declare f text; expected text; rid uuid; ref public.records; total numeric; paid numeric; contract numeric; previous numeric; p uuid;
begin
 -- Lock keseluruhan lejar kecil satu syarikat; serializes semakan bayaran serentak.
 perform pg_advisory_xact_lock(742019);
 if TG_OP='UPDATE' then
   if new.kind<>old.kind then raise exception 'Jenis rekod tidak boleh diubah'; end if;
   new.created_at=old.created_at; new.created_by=old.created_by;
 end if;
 new.updated_at=now();
 if length(trim(coalesce(new.data->>'name','')))=0 then raise exception 'Nama/nombor wajib diisi'; end if;
 foreach f in array array['customer_id','project_id','supplier_id','invoice_id'] loop
   expected=case f when 'customer_id' then 'customers' when 'project_id' then 'projects' when 'supplier_id' then 'suppliers' else 'invoices' end;
   if new.data ? f then
     rid=(new.data->>f)::uuid;
     select * into ref from public.records where id=rid and kind=expected;
     if ref.id is null then raise exception 'Rujukan % tidak sah',f; end if;
   end if;
 end loop;
 if new.kind in ('projects','quotations') and not(new.data ? 'customer_id') then raise exception 'Pelanggan wajib'; end if;
 if new.kind in ('variations','claims','invoices','expenses') and not(new.data ? 'project_id') then raise exception 'Projek wajib'; end if;
 if new.kind='expenses' and not(new.data ? 'supplier_id') then raise exception 'Pembekal wajib'; end if;
 if new.kind='payments' and not(new.data ? 'invoice_id') then raise exception 'Invois wajib'; end if;
 foreach f in array array['amount','budget','progress','retention'] loop
   if new.data ? f and ((new.data->>f)::numeric <0 or (new.data->>f)::numeric='NaN'::numeric) then raise exception 'Nilai % tidak sah',f; end if;
 end loop;
 if new.kind in ('projects','variations','invoices','payments','expenses') and coalesce(new.data->>'amount','')='' then raise exception 'Amaun wajib'; end if;
 if coalesce((new.data->>'progress')::numeric,0)>100 or coalesce((new.data->>'retention')::numeric,0)>100 then raise exception 'Peratus melebihi 100'; end if;
 if new.kind='quotations' then
   if jsonb_typeof(new.data->'items') is distinct from 'array' or jsonb_array_length(new.data->'items')=0 then raise exception 'BOQ wajib'; end if;
   if exists(select 1 from jsonb_array_elements(new.data->'items') i where coalesce((i->>'qty')::numeric,0)<=0 or coalesce((i->>'rate')::numeric,-1)<0 or coalesce(trim(i->>'description'),'')='') then raise exception 'Baris BOQ tidak sah'; end if;
   select sum((i->>'qty')::numeric*(i->>'rate')::numeric) into total from jsonb_array_elements(new.data->'items') i;
   new.data=jsonb_set(new.data,'{amount}',to_jsonb(round(total,2)));
 end if;
 if new.kind in ('projects','quotations','variations','claims','invoices') then
   if not coalesce(new.data->>'status','') = any(case new.kind when 'projects' then array['Draf','Aktif','Siap'] when 'claims' then array['Draf','Dihantar','Diluluskan'] when 'invoices' then array['Draf','Dihantar'] else array['Draf','Dihantar','Diluluskan','Ditolak'] end) then raise exception 'Status tidak sah'; end if;
 end if;
 if new.kind='claims' then
   if TG_OP='UPDATE' and old.data->>'status'='Diluluskan' and new.data<>old.data then raise exception 'Tuntutan diluluskan dikunci; buat pelarasan melalui pemilik DB'; end if;
   if TG_OP='INSERT' or new.data<>old.data then
    p=(new.data->>'project_id')::uuid;
    select (data->>'amount')::numeric into contract from public.records where id=p;
    select contract+coalesce(sum((data->>'amount')::numeric),0) into contract from public.records where kind='variations' and data->>'project_id'=p::text and data->>'status'='Diluluskan';
    select coalesce(sum((data->>'amount')::numeric),0) into previous from public.records where kind='claims' and id<>new.id and data->>'project_id'=p::text and data->>'status'='Diluluskan';
    total=round(contract*(new.data->>'progress')::numeric/100*(1-(new.data->>'retention')::numeric/100)-previous,2);
    if total is null or total<=0 then raise exception 'Tuntutan bersih mesti positif'; end if;
    new.data=jsonb_set(new.data,'{amount}',to_jsonb(total));
   end if;
 end if;
 if new.kind='payments' then
   rid=(new.data->>'invoice_id')::uuid;
   select (data->>'amount')::numeric into total from public.records where id=rid;
   select coalesce(sum((data->>'amount')::numeric),0) into paid from public.records where kind='payments' and id<>new.id and data->>'invoice_id'=rid::text;
   if (new.data->>'amount')::numeric<=0 or paid+(new.data->>'amount')::numeric>total then raise exception 'Bayaran melebihi baki / tidak positif'; end if;
 end if;
 if new.kind='invoices' then
   select coalesce(sum((data->>'amount')::numeric),0) into paid from public.records where kind='payments' and data->>'invoice_id'=new.id::text;
   if (new.data->>'amount')::numeric<paid then raise exception 'Nilai invois kurang daripada bayaran diterima'; end if;
 end if;
 return new;
end $$;
create trigger records_validate before insert or update on public.records for each row execute function public.cp_validate();
create function public.cp_audit() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.audit_log(actor,record_id,operation,before_data,after_data) values(auth.uid(),new.id,TG_OP,case when TG_OP='UPDATE' then old.data else null end,new.data);
 return new;
end $$;
create trigger records_audit after insert or update on public.records for each row execute function public.cp_audit();
revoke all on function public.cp_validate(),public.cp_audit() from public;
commit;

-- Selepas cipta pengguna dalam Authentication > Users, jalankan secara berasingan:
-- insert into public.profiles(id,role,display_name)
-- values ('UUID-PENGGUNA-DARI-AUTH','admin','Pemilik');
-- Peranan lain: finance, manager, viewer. Jangan benarkan pengguna menaikkan peranan sendiri.
