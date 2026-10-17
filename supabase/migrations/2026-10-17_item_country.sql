-- item pages (wanted / project / agency) carry their own country, so a link without a country prefix
-- opens the page in the right country (owner, 2026-10-17). Adds one field each; nothing else changes.
CREATE OR REPLACE FUNCTION public.bk_agency_get(p_id bigint)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select row_to_json(x) from (
    select a.id, a.user_id, a.name, a.description,
           case when coalesce(u.hide_phone,false) then null else a.phone end as phone,
           case when coalesce(u.hide_phone,false) then null else a.whatsapp end as whatsapp,
           a.email, a.website, a.address, a.gov_names, a.area_names, a.specialties, a.verified, a.created_at, a.contact_person, a.country_code,
           u.avatar_url as logo_url, u.created_at as member_since, coalesce(u.hide_phone,false) as hide_phone,
           (select count(*) from listings l where l.user_id=a.user_id and l.status='live') as live,
           (select count(*) from listings l where l.user_id=a.user_id and l.status in ('sold','rented')) as closed,
           (select bk_reviews_for(u.id)) as reviews
      from agencies a join users u on u.id=a.user_id
     where a.id=p_id and a.status='approved' and not u.blocked) x;
$function$
;
CREATE OR REPLACE FUNCTION public.bk_wanted_row(w wanted)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select json_build_object(
    'id', w.id, 'ref', w.ref, 'country_code', w.country_code, 'user_id', w.user_id, 'deal', w.deal, 'property_type', w.property_type,
    'property_types', coalesce(w.property_types, case when w.property_type is not null then array[w.property_type] else '{}' end),
    'gov_name', w.gov_name, 'area_names', w.area_names,
    'budget_min', w.budget_min, 'budget_max', w.budget_max, 'currency', w.currency, 'rooms_min', w.rooms_min, 'area_min', w.area_min, 'tabu', w.tabu,
    'title', w.title, 'description', w.description, 'contact', w.contact, 'status', w.status, 'featured', w.featured, 'views', w.views,
    'expires_at', w.expires_at, 'created_at', w.created_at,
    'user_name', (select trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) from users u where u.id=w.user_id),
    'user_avatar', (select u.avatar_url from users u where u.id=w.user_id),
    'phone', case when w.contact in ('phone','both') then (select u.phone from users u where u.id=w.user_id) end,
    'whatsapp', case when w.contact in ('whatsapp','both') then (select u.phone from users u where u.id=w.user_id) end,
    'phone_verified', (select u.phone_verified from users u where u.id=w.user_id)
  );
$function$
;
CREATE OR REPLACE FUNCTION public.bk_project_get(p_id bigint)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select row_to_json(p) from (
    select pr.id, pr.name, pr.developer_name, pr.developer_user_id, pr.gov_name, pr.area_name, pr.address, pr.lat, pr.lng, pr.description, pr.status, pr.delivery, pr.price_from, pr.down_pct, pr.months, pr.handover_pct, pr.photos, pr.units, pr.plans, pr.featured, pr.created_at, pr.country_code,
           u.phone as developer_phone, u.avatar_url as developer_logo, (select a.id from agencies a where a.user_id=pr.developer_user_id and a.status='approved') as agency_id
      from projects pr left join users u on u.id=pr.developer_user_id where pr.id=p_id and pr.published) p;
$function$
;
