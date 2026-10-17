-- Lebanon ownership statuses (owner, 2026-10-17). Lebanese law: a sale exists only once inscribed at the Land Registry
-- (السجل العقاري); undivided property is held in shares (2,400 per plot); an apartment gets its own title after partition
-- (الإفراز); in unsurveyed areas ownership rests on a mukhtar's «علم وخبر». The old «إفادة عقارية» row is a registry
-- extract (proof of a title), not a status of its own, so it goes. No Lebanese listing uses these codes yet.
begin;
delete from deed_types where country_code='LB';
insert into deed_types(country_code,code,name_ar,name_en,name_de,name_fr,is_strong,enabled,sort_order) values
('LB','title','سند تمليك مفرز (مسجّل في السجل العقاري)','Registered title deed (own unit)','Eingetragener Eigentumstitel (eigene Einheit)','Titre de propriété enregistré (lot séparé)',true,true,1),
('LB','ifraz','قيد الإفراز (السند قيد الإصدار)','Partition in progress (title pending)','Teilung läuft (Titel ausstehend)','En cours de division (titre en attente)',false,true,2),
('LB','shares','أسهم في عقار غير مفرز (ملكية شائعة)','Shares in an undivided property','Anteile an ungeteiltem Grundstück','Parts dans un bien indivis',false,true,3),
('LB','contract','عقد بيع لدى الكاتب العدل','Notarised sale contract','Notarieller Kaufvertrag','Contrat de vente notarié',false,true,4),
('LB','poa','وكالة بيع غير قابلة للعزل','Irrevocable power of attorney','Unwiderrufliche Vollmacht','Procuration irrévocable',false,true,5),
('LB','ilm','علم وخبر (منطقة غير ممسوحة)','Unsurveyed area – mukhtar certificate','Nicht vermessenes Gebiet – Bescheinigung des Mukhtar','Zone non cadastrée – certificat du moukhtar',false,true,6),
('LB','none','بدون أوراق ملكية','No ownership papers','Ohne Eigentumspapiere','Sans titre de propriété',false,true,7);
commit;
