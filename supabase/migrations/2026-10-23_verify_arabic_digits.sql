-- A sign-up code typed in Arabic / Persian digits (١٢٣٤٥٦ / ۱۲۳۴۵۶) was counted as a wrong code: the comparison kept them as
-- they are (Postgres \d includes them) against the server's 123456 (owner, 2026-10-23). They are read as 0-9 now.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.bk_verify_check'::regproc);
  d := replace(d, $q$regexp_replace(coalesce(p_code,''), '\D', '', 'g') <> t.otp$q$,
                  $q$regexp_replace(translate(coalesce(p_code,''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'), '[^0-9]', '', 'g') <> t.otp$q$);
  if position('translate(coalesce(p_code' in d) = 0 then raise exception 'bk_verify_check: comparison not found, nothing changed'; end if;
  execute d;
end $$;
