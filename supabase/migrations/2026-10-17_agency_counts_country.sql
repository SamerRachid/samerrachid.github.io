-- an office counts only its own country's listings (owner, 2026-10-17: Lebanon readiness)
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
           (select count(*) from listings l where l.user_id=a.user_id and coalesce(l.country_code,'SY')=coalesce(a.country_code,'SY') and l.status='live') as live,
           (select count(*) from listings l where l.user_id=a.user_id and coalesce(l.country_code,'SY')=coalesce(a.country_code,'SY') and l.status in ('sold','rented')) as closed,
           (select bk_reviews_for(u.id)) as reviews
      from agencies a join users u on u.id=a.user_id
     where a.id=p_id and a.status='approved' and not u.blocked) x;
$function$
;
CREATE OR REPLACE FUNCTION public.bk_public_agencies(p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(json_agg(row_to_json(x) order by x.verified desc, x.live desc, x.name), '[]'::json) from (
    select a.id, a.user_id, a.name, a.description,
           case when coalesce(u.hide_phone,false) then null else a.phone end as phone,
           case when coalesce(u.hide_phone,false) then null else a.whatsapp end as whatsapp,
           a.email, a.website, a.address, a.gov_names, a.area_names, a.specialties, a.verified, a.created_at, a.country_code,
           u.avatar_url as logo_url, coalesce(u.hide_phone,false) as hide_phone,
           (select count(*) from listings l where l.user_id=a.user_id and coalesce(l.country_code,'SY')=coalesce(a.country_code,'SY') and l.status='live') as live
      from agencies a join users u on u.id=a.user_id
     where a.status='approved' and not u.blocked and (p_country is null or a.country_code = p_country)) x;
$function$
;
