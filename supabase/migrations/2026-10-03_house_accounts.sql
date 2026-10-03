-- 2026-10-03 · "browsing accounts" (owner): ten in-house member accounts, no phone number, number hidden, controlled from
-- a panel page (الأعضاء ← حسابات التصفح) where the admin signs in as any of them to browse / post on the site.
-- Reuses bk_admin_login_as() for the sign-in; this file only adds the flag, the ten rows and the list RPC.
alter table users add column if not exists is_house boolean not null default false;
alter table users alter column phone drop not null;   -- house accounts have no number at all (unique() allows many nulls; nobody signs in to them by phone)

-- phone_verified stays false so the welcome trigger has nothing to send; pass_hash is random (nobody signs in with a password)
insert into users (phone, name, family_name, pass_hash, role, country, city, lang, account_type, level, phone_verified, hide_phone, is_house, bio)
select null, n.first_name, n.family_name, encode(gen_random_bytes(24), 'hex'), 'owner', 'SY', n.city, 'ar', 'member', 'member', false, true, true, null
  from (values
    ('أحمد',  'الخطيب',  'دمشق'),
    ('سامر',  'حداد',    'حلب'),
    ('كريم',  'العلي',   'حمص'),
    ('يوسف',  'النجار',  'اللاذقية'),
    ('ماهر',  'سليمان',  'حماة'),
    ('لينا',  'الحمصي',  'دمشق'),
    ('رنا',   'شعبان',   'حلب'),
    ('هبة',   'قباني',   'دمشق'),
    ('ريم',   'عثمان',   'طرطوس'),
    ('نور',   'دياب',    'حمص')
  ) as n(first_name, family_name, city)
 where not exists (select 1 from users u where u.is_house and u.name = n.first_name and u.family_name = n.family_name);

create or replace function public.bk_admin_house_accounts(p_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at, x.id) from (
    select u.id, u.name, u.family_name, u.city, u.country, u.member_no, u.avatar_url, u.bio, u.hide_phone, u.blocked, u.created_at, u.last_seen_at,
           (select count(*) from listings l where l.user_id = u.id and l.status in ('live','pending')) as listings,
           (select count(*) from listings l where l.user_id = u.id) as listings_total,
           (select count(*) from reviews r where r.target_user = u.id) as reviews
      from users u where u.is_house order by u.created_at, u.id) x), '[]'::json);
end $$;
grant execute on function public.bk_admin_house_accounts(text) to anon, authenticated;
