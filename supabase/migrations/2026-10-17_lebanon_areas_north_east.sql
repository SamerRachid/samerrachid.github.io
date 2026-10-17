-- Lebanon areas: North, Akkar, Baalbek-Hermel, Bekaa (research 2026-10-17). Deletes only touch Lebanese rows no listing/request uses.
begin;
update areas a set governorate_id=(select id from governorates where slug='akkar' and country_code='LB') from governorates g where a.id=7382 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='bekaa' and country_code='LB') from governorates g where a.id=6709 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بيرة', name_en='Bireh (Rashaya)', governorate_id=(select id from governorates where slug='bekaa' and country_code='LB'), lat=33.6024, lng=35.83931 from governorates g where a.id=7723 and g.id=a.governorate_id and g.country_code='LB';
delete from areas a using governorates g where a.id=7839 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7840 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7932 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
update areas a set name_ar='إده (البترون)', name_en='Eddeh (Batroun)', lat=34.2353, lng=35.68383 from governorates g where a.id=7614 and g.id=a.governorate_id and g.country_code='LB';
delete from areas a using governorates g where a.id=6488 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=6491 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7104 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7675 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7605 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7893 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=6710 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=6965 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7835 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7968 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=6830 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7815 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7912 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
update areas a set name_ar='الطيبة', name_en='Taybeh (Baalbek)' from governorates g where a.id=7407 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='العين', name_en='El Ain (Baalbek)' from governorates g where a.id=7499 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='رحبة', name_en='Rahbeh' from governorates g where a.id=6835 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='شيخلار', name_en='Cheikhlar', lat=34.61994, lng=36.27798 from governorates g where a.id=7919 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='قبة شمرا', name_en='Qoubbet Chamra' from governorates g where a.id=6846 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بشناتا', name_en='Bechennata' from governorates g where a.id=7144 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='كفرببنين', name_en='Kfar Bibnine' from governorates g where a.id=7832 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='رشدبين', name_en='Rechdebbine' from governorates g where a.id=7053 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بتوراتيج', name_en='Btouratij' from governorates g where a.id=7029 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بقاعكفرا', name_en='Bqaa Kafra' from governorates g where a.id=7022 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بقرقاشا', name_en='Bqarqacha' from governorates g where a.id=7706 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='عرطز', name_en='Aartiz', lat=34.23472, lng=35.75104 from governorates g where a.id=7578 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='صورات', name_en='Sourat', lat=34.24033, lng=35.75991 from governorates g where a.id=7911 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='وادي العرايش', name_en='Wadi el Arayech', lat=33.87279, lng=35.90879, kind='area' from governorates g where a.id=7967 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='المعلقة', name_en='Maallaka', lat=33.84364, lng=35.91585, kind='area' from governorates g where a.id=7532 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Haouch ez Zaraaneh', lat=33.8438, lng=35.91021, kind='area' from governorates g where a.id=7972 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='تويتي', name_en='Touaiteh', lat=33.8565, lng=35.83899 from governorates g where a.id=7978 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='عانا', name_en='Aana' from governorates g where a.id=6707 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='عيتنيت', name_en='Aitanit' from governorates g where a.id=7143 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='خربة روحا', name_en='Kherbet Rouha' from governorates g where a.id=7072 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بكيفا', name_en='Bkifa' from governorates g where a.id=7092 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='النبي شيت', name_en='Nabi Chit' from governorates g where a.id=7351 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='السعيدة', name_en='Saaideh' from governorates g where a.id=7376 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الفاكهة', name_en='Al Fakiha' from governorates g where a.id=7350 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الكنيسة', name_en='Kneisseh (Baalbek)' from governorates g where a.id=7417 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Bazzalieh' from governorates g where a.id=7381 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بدنايل (الكورة)', name_en='Bednayel (Koura)' from governorates g where a.id=7488 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Btehline' from governorates g where a.id=7160 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Sebaal' from governorates g where a.id=6515 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Kouba' from governorates g where a.id=6485 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Qboula' from governorates g where a.id=6838 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_en='Kahf el Malloul' from governorates g where a.id=7630 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=34.10841, lng=36.28235 from governorates g where a.id=7383 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='رشعين', lat=34.3977, lng=35.91972 from governorates g where a.id=6549 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='كفرحورا', lat=34.38529, lng=35.87191 from governorates g where a.id=7431 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='كفردلاقوس', lat=34.39914, lng=35.90733 from governorates g where a.id=7819 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='زغرتا المتاولة', lat=34.25496, lng=35.84058 from governorates g where a.id=7747 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الحازمية (المنية)', lat=34.39194, lng=36.04036 from governorates g where a.id=7559 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='عين التينة (المنية)', lat=34.39266, lng=36.0457 from governorates g where a.id=7792 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='عين التينة (البقاع الغربي)' from governorates g where a.id=7929 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='village' from governorates g where a.id=724 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='village' from governorates g where a.id=723 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='village' from governorates g where a.id=725 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='village' from governorates g where a.id=720 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='city' from governorates g where a.id=710 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='area' from governorates g where a.id=6879 and g.id=a.governorate_id and g.country_code='LB';
insert into areas(governorate_id,name_ar,name_en,slug,lat,lng,enabled,kind) values
((select id from governorates where slug='north-lebanon' and country_code='LB'),'القبة','Al Qobbeh','al-qobbeh',34.43551,35.85626,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'باب التبانة','Bab el Tabbaneh','bab-el-tabbaneh',34.44417,35.85083,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'جبل محسن','Jabal Mohsen','jabal-mohsen',34.44314,35.857,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'باب الرمل','Bab el Ramel','bab-el-ramel',34.42674,35.83536,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'أبي سمراء','Abou Samra','abou-samra',34.42276,35.84366,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الزاهرية','Zahrieh','zahrieh',34.43898,35.84389,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'المنكوبين','Al Mankoubin','al-mankoubin',34.44866,35.86384,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'التل','Al Tal','al-tal',34.43809,35.83693,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الزيتون','Zeitoun','zeitoun',34.41922,35.84308,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الحدادين','Haddadine','haddadine',34.431,35.84094,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'النوري','Al Nouri','al-nouri',34.43517,35.84127,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'المهاترة','Al Mhatra','al-mhatra',34.43408,35.84417,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الرمانة','Al Remmaneh','al-remmaneh',34.43607,35.84331,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'السويقة','Al Souayqa','al-souayqa',34.43425,35.84739,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الحديد','Al Hadid','al-hadid',34.43567,35.84554,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بساتين طرابلس','Tripoli Gardens (Basatin)','tripoli-gardens-basatin',34.43833,35.82744,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بساتين الميناء','El Mina Gardens','el-mina-gardens',34.44308,35.82102,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'شارع المئتين','Mitein Street','mitein-street',34.442,35.83797,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'شارع عزمي','Azmi Street','azmi-street',34.44256,35.83287,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الضم والفرز','Dam w Farez','dam-w-farez',null,null,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'المعرض','Al Maarad','al-maarad',null,null,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'ضهر المغر','Dahr el Mogher','dahr-el-mogher',null,null,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الملولة','Mallouleh','mallouleh',null,null,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'البقيعة (الكورة)','Bqaiaa (Koura)','bqaiaa-koura',34.37126,35.85676,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'حارة الخسة','Haret el Khasseh','haret-el-khasseh',34.38012,35.83737,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'ضهور الحواء','Dhour el Hawa','dhour-el-hawa',34.32962,35.82642,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'مزرعة إجبع','Mazraat Ejbeh','mazraat-ejbeh',34.38561,35.88134,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'مزرعة جنيد','Mazraat Jnaid','mazraat-jnaid',34.37419,35.90102,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'دير الجديدة','Deir Jdeideh','deir-jdeideh',34.36306,35.89189,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'حواكير','Hawakir','hawakir',34.36487,35.93321,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'دنها','Danha','danha',34.39494,35.93674,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'المعيزية','Maaiziyeh','maaiziyeh',34.40209,35.91285,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بيت بركات','Beit Barakat','beit-barakat',34.43163,35.90971,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'العقبة (زغرتا)','Aqbeh (Zgharta)','aqbeh-zgharta',34.42912,35.89029,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الرميلة (زغرتا)','Rmaileh (Zgharta)','rmaileh-zgharta',34.41206,35.91342,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'تلة زغرتا','Tallet Zgharta','tallet-zgharta',34.39182,35.87941,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'حريق زغرتا','Hariq Zgharta','hariq-zgharta',34.37919,35.91634,true,'area'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الأرز','The Cedars (Arz)','the-cedars-arz',34.24375,36.04035,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بلا','Billa','billa',34.26527,35.89183,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'كفرعبيدا','Kfar Abida','kfar-abida',34.22802,35.66281,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'محمرش','Mehmarch','mehmarch',34.19877,35.76883,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'علالي','Aalali','aalali',34.20445,35.77268,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'راشا','Racha','racha',34.20017,35.7867,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'كفرخلص','Kfar Khollos','kfar-khollos',34.26407,35.68212,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'الرام (البترون)','Ram (Batroun)','ram-batroun',34.18588,35.79957,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'تنورين الفوقا','Tannourine el Faouqa','tannourine-el-faouqa',34.17227,35.94903,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'تنورين التحتا','Tannourine el Tahta','tannourine-el-tahta',34.20503,35.90906,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بلعا','Balaa','balaa',34.17836,35.87452,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'رمات','Ramate','ramate',34.21762,35.71675,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'فدعوس','Fadous','fadous',34.22839,35.65631,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'قرنعون','Qarnaaoun','qarnaaoun',34.27217,35.6925,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'حوراتا','Hourata','hourata',34.18814,35.93271,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بيت الفقس','Beit el Faqs','beit-el-faqs',34.39256,36.05268,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'كرم المهر','Karm el Mohr','karm-el-mohr',34.36205,35.98692,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'قرين','Qrayn','qrayn',34.39713,36.0333,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'زغرتغرين','Zaghartaghrine','zaghartaghrine',34.35988,35.95326,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'جرجور','Jarjour','jarjour',34.35419,35.9374,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بشحارة','Bechehhara','bechehhara',34.36029,35.93607,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'مزرعة الكريم','Mazraat el Kreim','mazraat-el-kreim',34.36164,35.96347,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'ذوق بحنين','Zouk Bhannine','zouk-bhannine',34.49603,35.95789,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'عدوة','Adweh','adweh',34.45054,35.98612,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بيت حسان','Beit Hassan','beit-hassan',34.38522,35.95933,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'السواقي','Sawaqi','sawaqi',34.33081,36.01159,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'ضريرة','Draira','draira',34.36024,35.9943,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'شميس','Chmis','chmis',34.39732,36.02458,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بحصة','Bahsa','bahsa',34.38241,36.03707,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'وادي النجاص','Wadi en Njass','wadi-en-njass',34.35839,36.0386,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بيت داود','Beit Daoud','beit-daoud',34.37799,35.96009,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بشتايل','Bechtayel','bechtayel',34.40581,35.99457,true,'village'),
((select id from governorates where slug='north-lebanon' and country_code='LB'),'بيت جيدا','Beit Jida','beit-jida',34.39504,36.01047,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'ذوق حدارة','Zouk Haddara','zouk-haddara',34.51552,36.0302,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'ذوق المقشرين','Zouk el Moqachrine','zouk-el-moqachrine',34.51973,36.02871,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'بينو','Beino','beino',34.53845,36.18102,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'العيون (عكار)','Aayoun (Akkar)','aayoun-akkar',34.52794,36.17346,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'الكويخات','Koueikhat','koueikhat',34.58024,36.09111,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'حكر إطي','Hokr Etti','hokr-etti',34.57583,36.10411,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'شير حميرين','Chir Hmairine','chir-hmairine',34.61905,36.11673,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'السمونية','Sammouniyeh','sammouniyeh',34.57575,36.04962,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'تل حميرة','Tall Hmayra','tall-hmayra',34.62625,36.07213,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'برشا','Barcha','barcha',34.62651,36.12084,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'تل سبعل','Tall Sebaal','tall-sebaal',34.55263,36.02923,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'المغراق','Mighraq','mighraq',34.61,36.01857,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'الخرنوبة','Kharnoubeh','kharnoubeh',34.62989,36.12915,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'سمقالي','Semmaqli','semmaqli',34.54287,36.01387,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'جنين (عكار)','Janine (Akkar)','janine-akkar',34.62927,36.14753,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'عمارة (عكار)','Aamaret Akkar','aamaret-akkar',34.53197,36.00987,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'رمول','Rmoul','rmoul',34.57226,36.01345,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'قبعيت','Qabaait','qabaait',34.44963,36.09673,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'صدقة','Sadaqa','sadaqa',34.46515,36.14956,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'القريات','Qraiyat','qraiyat',34.48077,36.15386,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'ممنع','Memnaa','memnaa',34.50018,36.1756,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'كفرنون','Kfar Noun','kfar-noun',34.62446,36.25348,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'خربة الرمان','Khirbet er Remmane','khirbet-er-remmane',34.62676,36.2827,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'خالصة','Khalsa','khalsa',34.63319,36.31243,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'مصلا','Msalla','msalla',34.59166,36.16123,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'مزيحمة','Mzeihmeh','mzeihmeh',34.60953,36.14247,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'حميص','Hmaiss (Akkar)','hmaiss-akkar',34.57385,36.12479,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'العرمة','Aarmeh','aarmeh',34.62973,36.1622,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'مزرعة النهرية','Mazraat en Nahriyeh','mazraat-en-nahriyeh',34.60016,36.2804,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'البياضة','Bayada','bayada',34.51831,35.99103,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'القطلبة','Qatlabeh','qatlabeh',34.54075,36.28017,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'دبادب','Dbadeb','dbadeb',34.61202,36.38506,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'الهيشة','Hisheh','hisheh',34.63649,36.36488,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'خراب الحيات','Khrab el Hayyat','khrab-el-hayyat',34.64972,36.33628,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'حكر جنين','Hokr Janine','hokr-janine',34.63542,36.13177,true,'village'),
((select id from governorates where slug='akkar' and country_code='LB'),'جبل المنصورة','Jabal el Mansoura','jabal-el-mansoura',34.63221,36.31943,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'عرسال','Arsal','arsal',34.18029,36.41877,true,'city'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'القاع','Al Qaa','al-qaa',34.34082,36.48004,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'اليمونة','Yammouneh','yammouneh',34.12976,36.02916,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'مقنة','Maqneh','maqneh',34.07743,36.20646,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'بوداي','Bouday','bouday',34.06179,36.06313,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'دورس','Douris','douris',33.9879,36.17968,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'عدوس','Addous','addous',34.01853,36.15005,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'عمشكي','Aamchki','aamchki',33.99183,36.30352,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حوش تل صفية','Haouch Tall Safiyeh','haouch-tall-safiyeh',34.02478,36.13992,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'نحلة','Nahleh','nahleh',34.056,36.34726,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حوش الذهب','Haouch el Dahab','haouch-el-dahab',34.03664,36.11971,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'بجاجة','Bajjaje','bajjaje',34.22765,36.35117,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'نبحا','Nabha','nabha',34.18307,36.224,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'برقا','Barqa','barqa',34.17331,36.13882,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'ريحا','Riha','riha',34.15233,36.19221,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'تمنين الفوقا','Temnine el Faouqa','temnine-el-faouqa',33.90375,35.97976,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حوش النبي','Haouch en Nabi','haouch-en-nabi',33.92957,36.06507,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'الخضر','Al Khodr','al-khodr',33.90453,36.12106,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'يحفوفا','Yahfoufa','yahfoufa',33.85924,36.12239,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حور تعلا','Haour Taala','haour-taala',33.9179,36.14156,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'بيت مشيك','Beit Mchaik','beit-mchaik',34.04386,36.02807,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'معربون','Maaraboun','maaraboun',33.8517,36.18877,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حام','Ham','ham',33.8721,36.20288,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'عين البنية','Ain el Bniyeh','ain-el-bniyeh',33.9101,36.22692,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'النبي سباط','Nabi Sbat','nabi-sbat',33.93555,36.23519,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'عين الجوزة (بعلبك)','Ain el Jaouzeh (Baalbek)','ain-el-jaouzeh-baalbek',33.84022,36.31605,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'سرعين الفوقا','Saraain el Faouqa','saraain-el-faouqa',33.87804,36.09272,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'سلوقي','Slouqi','slouqi',33.97271,35.91917,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'عيون أرغش','Aayoun Orghoch','aayoun-orghoch',34.26119,36.12908,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'رسم الحدث','Rasm el Hadath','rasm-el-hadath',34.14102,36.2758,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'النبي رشادة','Nabi Rashada','nabi-rashada',33.99386,36.03822,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'زرازير','Zrazir','zrazir',34.15225,36.12295,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'علاق','Allaq','allaq',34.02809,36.10346,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'بيت حبشي','Beit Habshi','beit-habshi',34.15358,36.0994,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'فلاوي','Flaoui','flaoui',34.08347,36.06244,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'الحفير','Hfeir','hfeir',34.07787,36.0715,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'بصيلة','Bsayleh','bsayleh',34.13058,36.12309,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'خورماتا','Khourmata','khourmata',34.0873,36.2528,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'صفرا','Safra','safra',34.14768,36.16502,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'التليلة','Tleileh','tleileh',null,null,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'الحلانية','Hallaniyeh','hallaniyeh',null,null,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'جبولة','Jbouleh','jbouleh',null,null,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'الدمدوم','Damdoum','damdoum',null,null,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'المحفارة','Mahfara','mahfara',null,null,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'الشراونة','Sharawneh','sharawneh',34.01456,36.20426,true,'area'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'العسيرة','Al Assira','al-assira',null,null,true,'area'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'رأس العين (بعلبك)','Ras el Ain (Baalbek)','ras-el-ain-baalbek',null,null,true,'area'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'مرجحين','Mrajhine','mrajhine',34.41255,36.19974,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'البريج','Brayj','brayj',34.45527,36.38189,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'برغش','Barghash','barghash',34.38838,36.2962,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'بديتا','Bdita','bdita',34.39003,36.379,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'الوقف (الهرمل)','Waqf (Hermel)','waqf-hermel',34.39015,36.38876,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'البعول','Baaoul','baaoul',34.41793,36.33502,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حوش بيت إسماعيل','Haouch Beit Ismail','haouch-beit-ismail',34.4548,36.48265,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'تل الفار','Tall el Far','tall-el-far',34.41314,36.41237,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'المجوية','Majwiyeh','majwiyeh',34.49811,36.36631,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'هوشرية','Haouchariyeh','haouchariyeh',34.49404,36.39445,true,'village'),
((select id from governorates where slug='baalbek-hermel' and country_code='LB'),'حي المرح','Hay el Merh','hay-el-merh',34.39524,36.38445,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حوش الأمراء','Hoch el Oumara','hoch-el-oumara',33.83271,35.91304,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'الراسية','Rassieh','rassieh',33.84817,35.8908,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حي الميدان','Midan','midan',33.84729,35.90418,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'البربارة','Berbara','berbara',33.85159,35.89812,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حي مار جرجس','Mar Gerges','mar-gerges',33.84467,35.90268,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حي مار أنطونيوس','Mar Antonios','mar-antonios',33.84781,35.89864,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حي سيدة النجاة','Saydet el Najat','saydet-el-najat',33.84584,35.8943,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حي مار الياس','Mar Elias (Zahle)','mar-elias-zahle',33.84466,35.89853,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'كسارة','Ksara','ksara',33.82796,35.89545,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'المدينة الصناعية (زحلة)','Zahle Industrial City','zahle-industrial-city',33.8286,35.94092,true,'area'),
((select id from governorates where slug='bekaa' and country_code='LB'),'الرمطانية','Remtaniyeh','remtaniyeh',33.83625,35.81744,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'زبدل','Zebdol','zebdol',33.81422,35.83682,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'بوارج','Bouarej','bouarej',33.81891,35.81437,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'دلهمية','Dalhamiyeh','dalhamiyeh',33.81871,35.95821,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'كفرزبد','Kfarzabad','kfarzabad',33.78493,35.99396,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'ناصرية رزق','Nasriyet Rizk','nasriyet-rizk',33.86309,36.05945,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حي الفيكاني','Hay el Fikani','hay-el-fikani',33.8474,36.02664,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'دير زنون','Deir Zenoun','deir-zenoun',33.76024,35.90948,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حوش منذرة','Haouch Mandara','haouch-mandara',33.77672,35.86094,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حوش الصيادي','Haouch es Siyadeh','haouch-es-siyadeh',33.76746,35.82389,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'دير عين الجوزة','Deir Ain el Jaouzeh','deir-ain-el-jaouzeh',33.59325,35.7002,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'لوسيا','Loussia','loussia',33.44208,35.65059,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'عميق','Aammiq','aammiq',33.71339,35.77318,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'كامد اللوز','Kamed el Laouz','kamed-el-laouz',33.62084,35.82319,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'تل ذنوب','Tall Znoub','tall-znoub',33.66182,35.77867,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'حمارة','Hammara','hammara',33.65132,35.88369,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'دكوة','Dakweh','dakweh',33.69138,35.87444,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'الروضة (البقاع الغربي)','Rawda (Western Beqaa)','rawda-western-beqaa',33.74443,35.89334,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'الجزيرة (البقاع الغربي)','Jazira (Western Beqaa)','jazira-western-beqaa',33.72659,35.84327,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'تل الزعزع','Tall ez Zaazaa','tall-ez-zaazaa',null,null,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'عيحا','Aiha','aiha',33.50108,35.87761,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'كفرقوق','Kfar Qouq','kfar-qouq',33.53446,35.89223,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'عين حرشا','Ain Harcha','ain-harcha',33.45621,35.7828,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'عين عطا','Ain Ata','ain-ata',33.43927,35.78028,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'بكا','Bakka','bakka',33.59254,35.92463,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'مدوخا','Mdoukha','mdoukha',33.60383,35.87753,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'ينطا','Yanta','yanta',33.60413,35.9448,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'دير العشاير','Deir el Achayer','deir-el-achayer',33.55656,36.01066,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'النبي صفا','Nabi Safa','nabi-safa',33.49673,35.74211,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'العقبة (راشيا)','Aqabet Rashaya','aqabet-rashaya',33.50404,35.82569,true,'village'),
((select id from governorates where slug='bekaa' and country_code='LB'),'ثلثاثا','Thalthata','thalthata',33.49584,35.7466,true,'village')
on conflict (governorate_id,slug) do nothing;
commit;
