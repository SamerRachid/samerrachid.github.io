-- 2026-10-30 · owner's decision: SY10610 (هدى محمد) is $15,000, not $15; every member with a live listing that has no price
-- or a fake price gets ONE WhatsApp message (all their listings in it) asking for the real price within 48 hours,
-- after which those listings are hidden. Messages go through the normal direct-message queue (campaigns + campaign_sends),
-- titled «price48h: …» so they can be found when the 48 hours are up.

update listings set price_usd = 15000 where id = 646 and ref = 'SY10610';
update listings set orig_price = 15000 where id = 646;
delete from price_history where listing_id = 646 and old_price = 15 and new_price = 15000;

do $do$
declare r record; camp uuid; body text;
begin
  for r in
    with bad as (
      select l.user_id, string_agg(l.ref, '، ' order by l.ref) refs
        from listings l
       where l.status = 'live' and (coalesce(l.price_usd,0) <= 0 or l.price_usd <= 15 or l.price_usd in (123,123456))
       group by l.user_id)
    select b.user_id, b.refs, trim(u.name||' '||coalesce(u.family_name,'')) who, u.country,
           (select c.id from contacts c where c.user_id = b.user_id order by c.created_at limit 1) contact_id
      from bad b join users u on u.id = b.user_id
  loop
    continue when r.contact_id is null;
    body := 'مرحباً '||r.who||' 🌿'||E'\n'||
      'نشكركم على ثقتكم ببلكون ونشر إعلاناتكم معنا.'||E'\n\n'||
      'وصلتنا مؤخراً شكاوى كثيرة من زوار الموقع بسبب إعلانات بلا سعر أو بسعر غير حقيقي. هذا يضيّع وقت الباحثين ويُضعف الثقة بكل الإعلانات، ومنها إعلاناتكم. لذلك نتواصل الآن مع جميع الأعضاء والمكاتب دون استثناء.'||E'\n\n'||
      'إعلاناتكم التي تحتاج إلى سعر حقيقي:'||E'\n'||r.refs||E'\n\n'||
      'نرجو منكم بكل محبة إضافة السعر الحقيقي خلال 48 ساعة، بتعديل الإعلان من حسابكم في الموقع، أو أرسلوا لنا الأسعار هنا ونعدّلها عنكم.'||E'\n'||
      'بعد هذه المدة ستُزال الإعلانات التي بقيت دون سعر حقيقي، ويمكنكم نشرها من جديد في أي وقت بالسعر الصحيح.'||E'\n\n'||
      'شكراً لتفهّمكم وتعاونكم 🙏'||E'\n'||'فريق بلكون';
    insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
      values ('price48h: '||r.who, 'manual', array['whatsapp'], null, body, body, coalesce(r.country,'SY'), false, 'sending',
              '6ec60333-3cca-47b6-bf83-7f62cb76bb42', now())
      returning id into camp;
    insert into campaign_sends (campaign_id, trigger_type, contact_id, channel, status) values (camp, 'manual', r.contact_id, 'whatsapp', 'queued');
  end loop;
end $do$;

select count(*) as queued_messages from campaigns where title like 'price48h:%';
