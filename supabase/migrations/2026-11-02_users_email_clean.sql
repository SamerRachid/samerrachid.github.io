-- An «email» without @ is a name typed in the wrong box (SYM1184: the office name landed in users.email).
-- 1) clear that one; 2) from now on any email without @ is saved as empty, whichever form or RPC writes it.
update public.users set email = null where member_no = 'SYM1184' and email not like '%@%';

create or replace function public.bk_users_email_clean() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.email is not null and (trim(new.email) = '' or position('@' in new.email) = 0) then
    new.email := null;
  end if;
  return new;
end $$;

drop trigger if exists users_email_clean on public.users;
create trigger users_email_clean before insert or update of email on public.users
  for each row execute function public.bk_users_email_clean();

select member_no, email from public.users where member_no = 'SYM1184';
