-- Lebanon areas: Beirut, Mount Lebanon, Keserwan-Jbeil, South, Nabatieh (research 2026-10-17). Deletes only touch Lebanese rows no listing/request uses.
begin;
delete from areas a using governorates g where a.id=7874 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7728 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7812 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7541 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7375 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7323 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7774 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7840 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
update areas a set name_ar='المريجات', governorate_id=(select id from governorates where slug='bekaa' and country_code='LB') from governorates g where a.id=7839 and g.id=a.governorate_id and g.country_code='LB';
delete from areas a using governorates g where a.id=7173 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7517 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7713 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7429 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7178 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7695 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7427 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
delete from areas a using governorates g where a.id=7425 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
update areas a set kind='area' from governorates g where a.id=6467 and g.id=a.governorate_id and g.country_code='LB';
update areas a set kind='area' from governorates g where a.id=7793 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='mount-lebanon' and country_code='LB') from governorates g where a.id=6807 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='mount-lebanon' and country_code='LB'), lat=33.9551, lng=35.7577 from governorates g where a.id=7555 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='south-lebanon' and country_code='LB') from governorates g where a.id=7716 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='nabatieh' and country_code='LB') from governorates g where a.id=7235 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='nabatieh' and country_code='LB') from governorates g where a.id=7664 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='mount-lebanon' and country_code='LB') from governorates g where a.id=7978 and g.id=a.governorate_id and g.country_code='LB';
update areas a set governorate_id=(select id from governorates where slug='nabatieh' and country_code='LB') from governorates g where a.id=6603 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بيرة', lat=33.7218, lng=35.6437 from governorates g where a.id=7723 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=33.89319, lng=35.7157 from governorates g where a.id=6693 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=33.93645, lng=35.63195 from governorates g where a.id=6771 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=33.90788, lng=35.70224 from governorates g where a.id=6672 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=33.88662, lng=35.77501 from governorates g where a.id=6670 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=33.71785, lng=35.57525 from governorates g where a.id=7850 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='منصورية بحمدون', lat=33.77883, lng=35.62654 from governorates g where a.id=6699 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الضاحية الجنوبية', kind='area' from governorates g where a.id=6468 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الحرف', lat=33.57538, lng=35.55808 from governorates g where a.id=7680 and g.id=a.governorate_id and g.country_code='LB';
update areas a set lat=33.48097, lng=35.4011 from governorates g where a.id=6985 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بقعاتة عشقوت', lat=34.00464, lng=35.73529 from governorates g where a.id=7880 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='ذوق الخراب' from governorates g where a.id=6772 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='ضهر الحصين' from governorates g where a.id=6683 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الورهانية' from governorates g where a.id=7960 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الفوارة' from governorates g where a.id=7949 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='بئر العبد' from governorates g where a.id=6478 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='البلونة' from governorates g where a.id=6726 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الكحالة' from governorates g where a.id=6746 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='اللويزة' from governorates g where a.id=7847 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='العباسية' from governorates g where a.id=7264 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='المعشوق' from governorates g where a.id=7186 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='مار مخايل بنابيل' from governorates g where a.id=6702 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='الدوار' from governorates g where a.id=6686 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='مرنبا' from governorates g where a.id=7944 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='كفردبيان' from governorates g where a.id=6824 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='حارة صيدا' from governorates g where a.id=7096 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='درب السيم' from governorates g where a.id=7099 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='برج الملوك' from governorates g where a.id=7444 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='جديدة غزير' from governorates g where a.id=7705 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='حياطة' from governorates g where a.id=7681 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='قنابة برمانا' from governorates g where a.id=6766 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='صموخة' from governorates g where a.id=7278 and g.id=a.governorate_id and g.country_code='LB';
delete from areas a using governorates g where a.id=6948 and g.id=a.governorate_id and g.country_code='LB' and not exists (select 1 from listings l where l.area_id=a.id) and not exists (select 1 from intake_places p where p.area_id=a.id);
update areas a set name_ar='شمع' from governorates g where a.id=7253 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='جورة أرصون' from governorates g where a.id=7749 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='سريرة' from governorates g where a.id=7508 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='رويسة البلوط' from governorates g where a.id=7733 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='دوير الرمان' from governorates g where a.id=7696 and g.id=a.governorate_id and g.country_code='LB';
update areas a set name_ar='رأس العين (صور)' from governorates g where a.id=7294 and g.id=a.governorate_id and g.country_code='LB';
insert into areas(governorate_id,name_ar,name_en,slug,lat,lng,enabled,kind) values
((select id from governorates where slug='beirut' and country_code='LB'),'الكولا','Cola','cola',33.87592,35.49577,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'مار الياس','Mar Elias','mar-elias',33.8757,35.49049,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'البربير','Barbir','barbir',33.87707,35.50605,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'عائشة بكار','Aicha Bakkar','aicha-bakkar',33.88993,35.4876,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'ميناء الحصن','Minet el Hosn','minet-el-hosn',33.8997,35.4977,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'جسر الواطي','Jisr al Wati','jisr-al-wati',33.87984,35.53278,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'ديك المحدي','Dik El Mehdi','dik-el-mehdi',33.93276,35.62008,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'المتحف','Mathaf (Museum)','mathaf-museum',33.87897,35.51498,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'دلغاني','Delghani','delghani',33.59886,35.61096,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مقصبة','Maqsabeh','maqsabeh',33.68825,35.4226,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'السعديات','Es Saadiyat','es-saadiyat',33.695,35.42611,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الزعيترية','Zaaitrieh','zaaitrieh',33.8807,35.56117,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'المسلوخ','El Masloukh','el-masloukh',34.20563,35.64449,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مزرعة البرغوتية','Mazraat El Barghoutiyeh','mazraat-el-barghoutiyeh',33.59006,35.42245,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'القنطاري','Kantari','kantari',33.89757,35.49334,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'باب إدريس','Bab Idriss','bab-idriss',33.89857,35.50137,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الباشورة','Bachoura','bachoura',33.89199,35.5037,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'اليسوعية','Yesouiyeh','yesouiyeh',33.89003,35.50898,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'فرن الحايك','Furn El Hayek','furn-el-hayek',33.89029,35.51387,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الناصرة','Nasrah','nasrah',33.88422,35.51217,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'مار متر','Mar Mitr','mar-mitr',33.88916,35.52197,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'العدلية','Adliyeh','adliyeh',33.87776,35.51867,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'المرفأ','Port (Marfaa)','port-marfaa',33.89864,35.51409,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الروم (مستشفى الروم)','Roum (St George Hospital)','roum-st-george-hospital',33.89342,35.52589,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الجعيتاوي','Ej Jeitaoui','ej-jeitaoui',33.89437,35.52971,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الحكمة','Al Hikmat','al-hikmat',33.89332,35.52133,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'مار نقولا','Mar Nicolas','mar-nicolas',33.89367,35.51488,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'قريطم','Koraytem','koraytem',33.89096,35.47763,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الصنوبرة','Snoubra','snoubra',33.89142,35.48309,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'كورنيش المزرعة','Corniche el Mazraa','corniche-el-mazraa',33.88166,35.48644,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'وطى سلام','Wata Sillam','wata-sillam',34.02156,35.62852,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'الظريف','Zarif','zarif',33.89316,35.4946,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'مونو','Monot','monot',33.88896,35.50784,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'سليم سلام','Salim Slam','salim-slam',33.88538,35.49754,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'حي اللجا','Al-Lija','al-lija',33.88711,35.49498,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'البطركية','Patriarcat','patriarcat',33.89073,35.49829,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'تلة الدروز','Tel Druze','tel-druze',33.89153,35.48606,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'السيوفي','Syoufi','syoufi',33.88547,35.52673,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'كرم الزيتون','Karm El Zeitoun','karm-el-zeitoun',33.89157,35.53047,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الأونيسكو','Unesco','unesco',33.8789,35.48176,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'المشاتي','Mchati','mchati',34.04995,35.76266,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'كفر حباب','Kfar Hbab','kfar-hbab',34.01229,35.65413,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'ميروبا','Mayrouba','mayrouba',34.01905,35.77453,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'قهمز','Qehmez','qehmez',34.056,35.81253,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'زبدين','Zebdine','zebdine',34.09528,35.71705,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'الطيبة','Taybeh (Marjayoun)','taybeh-marjayoun',33.27498,35.52053,true,'city'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'كفر تبنيت','Kfar Tebnit','kfar-tebnit',33.34998,35.51114,true,'city'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'سفيلة','Sfaila','sfaila',33.88562,35.67561,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'عين التينة','Ain El Tineh','ain-el-tineh',33.88643,35.48055,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'وطى المصيطبة','Wata el Msaytbeh','wata-el-msaytbeh',33.87947,35.49374,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'دير طاميش','Deir Tamiche','deir-tamiche',33.94013,35.62093,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مزرعة دير عوكر','Mazraet Deir Aoukar','mazraet-deir-aoukar',33.93188,35.60782,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مار عبدا المشمر','Mar Abda El Mchammar','mar-abda-el-mchammar',33.94264,35.63313,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'قرنة الحمرا','Kornet El Hamra','kornet-el-hamra',33.93595,35.64802,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مزرعة الحضيرة','Mazraet El Hadira','mazraet-el-hadira',33.93072,35.60567,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'غلبون','Ghalboun','ghalboun',34.17382,35.70534,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'بحنس','Bhannes','bhannes',33.90507,35.65664,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'ميسات','Maisat','maisat',33.26265,35.61932,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'الهبارية','Hebbariye','hebbariye',33.36812,35.69617,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'عدلون','Adloun','adloun',33.40482,35.27439,true,'city'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'الصالحية (كسروان)','Salhieh (Keserwan)','salhieh-keserwan',34.0765,35.71249,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'الخرايب (كسروان)','Khrayeb (Keserwan)','khrayeb-keserwan',34.07552,35.70764,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بقعاتة كنعان','Beqaatet Kenaan','beqaatet-kenaan',33.96359,35.76855,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مستيتا','Mastita','mastita',34.1048,35.65964,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'زغرين','Zighrin','zighrin',33.92486,35.71261,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عين الخروبة','Ain Al Kharruba','ain-al-kharruba',33.93569,35.7,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بخعاز','Bekhaaz','bekhaaz',34.188,35.66738,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عبري','Aabri','aabri',34.07545,35.78415,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المسقى','Masqa','masqa',33.88216,35.64599,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عين القبو','Aain El Qabu','aain-el-qabu',33.94041,35.76089,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'دير شمرا','Dair Shamra','dair-shamra',33.94641,35.7114,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'ساقية المسك','Saqiyyat Al Misk','saqiyyat-al-misk',33.9182,35.67757,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'هرهريا','Harharaya','harharaya',34.02485,35.69867,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المطلة','Mtolleh','mtolleh',33.61065,35.5393,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'سرجبال','Sirjbal','sirjbal',33.68459,35.51179,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المسرب','Al Masrab','al-masrab',33.62476,35.48132,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عين القش','Ain El Qash','ain-el-qash',33.92321,35.70173,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'خلة المتين','Khallat Al Mutayn','khallat-al-mutayn',33.89855,35.72615,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مار بطرس كرم التين','Mar Boutros Karm Et Tine','mar-boutros-karm-et-tine',33.93232,35.68562,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'زغلة','Zaghla','zaghla',33.40427,35.69223,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بزيون','Bazyoun','bazyoun',34.09822,35.75519,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'كفر مسحون','Kfar Mashoun','kfar-mashoun',34.147,35.67149,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'غرفين','Ghorfine','ghorfine',34.15329,35.66361,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بحديدات','Behdaydat','behdaydat',34.14835,35.70708,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'هابيل','Habil','habil',34.14903,35.73988,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مزارب','Mzarib','mzarib',34.07975,35.87928,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عبيدات','Aabaydat','aabaydat',34.16413,35.72702,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'فرحت','Ferhet','ferhet',34.10033,35.76229,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'صوانة','Souaneh','souaneh',34.09333,35.77492,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'دملصا','Dmalsa','dmalsa',34.14944,35.6825,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'طورزيا','Tourzaiya','tourzaiya',34.10988,35.75908,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'قرقريا','Qorqraiya','qorqraiya',34.0733,35.81779,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عين جرين','Ain Jrain','ain-jrain',34.085,35.76182,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مار سركيس','Mar Sarkis','mar-sarkis',34.09748,35.85647,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'سقي رشميا','Saqi Richmaya','saqi-richmaya',34.15871,35.78838,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'شامات','Chamate','chamate',34.16567,35.69842,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'جليسة','Jlisseh','jlisseh',34.11609,35.69102,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'راموط','Ramoute','ramoute',34.16747,35.71045,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عين كفاع','Ain Kfaa','ain-kfaa',34.18964,35.69506,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بنتاعل','Bentael','bentael',34.14632,35.69269,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'فراط','Frat','frat',34.08768,35.78939,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'هدينة','Hdayneh','hdayneh',34.09152,35.86841,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'فغال','Fghal','fghal',34.20615,35.67542,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'بتبيات','Btebyat','btebyat',33.83432,35.70668,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الفياضية','Fayadieh','fayadieh',33.84827,35.55079,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عين موفق','Ain Mouaffaq','ain-mouaffaq',33.82248,35.6517,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الهلالية (بعبدا)','Hlaliyeh (Baabda)','hlaliyeh-baabda',33.83302,35.63702,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'ضهر العقلين','Dahr El Aaqline','dahr-el-aaqline',33.68098,35.47369,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'قناة باكيش','Qanat Bakish','qanat-bakish',33.96258,35.82,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'شبريحا','Shabriha','shabriha',33.2921,35.23199,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'الشومرة','Ash Shumara','ash-shumara',33.11916,35.14237,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'شحيم','Chhim','chhim',33.62419,35.4846,true,'city'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'شمليخ','Shamlikh','shamlikh',33.78239,35.70633,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'بطحانيه','Bathaniyeh','bathaniyeh',33.42113,35.70898,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'عين طنطا','Ain Tanta','ain-tanta',33.41273,35.72719,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'دحيرجات','Dehayrjate','dehayrjate',33.30948,35.65461,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'المجيدية','El Majidiye','el-majidiye',33.28431,35.65761,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'الصليب','Slaiyeb','slaiyeb',33.2932,35.63097,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'عرب اللويزة','Aarab El Louaizeh','aarab-el-louaizeh',33.274,35.61462,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'برغز','Berghoz','berghoz',33.40811,35.63574,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'دلافي','Dlafy','dlafy',33.42989,35.64587,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'كوكبا','Kaukaba','kaukaba',33.39742,35.64229,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'حصنا','Hosna','hosna',34.10341,35.77566,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'شربينه','Charbineh','charbineh',34.11821,35.86097,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مخاضة','Moukhada','moukhada',34.13281,35.84427,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بقرتا','Bqarta','bqarta',34.12707,35.79848,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مديرج','Mdairej','mdairej',33.80115,35.7281,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'قطع','Qataa','qataa',33.53058,35.53458,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'بيقون','Baiqoun','baiqoun',33.617,35.58169,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'بيصور (جزين)','Baissour (Jezzine)','baissour-jezzine',33.5357,35.44861,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بلحص','Balhoss','balhoss',34.09378,35.80785,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'الرانسية','Ransiyeh','ransiyeh',33.5241,35.49214,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الصرونية','As Sarawuniyya','as-sarawuniyya',33.58237,35.443,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الجميلية','Jmailiyeh','jmailiyeh',33.60017,35.4263,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الصابونية','As Sabuniyya','as-sabuniyya',33.59622,35.4214,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'حارة شبيب','Haret Chbib','haret-chbib',33.77352,35.4723,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مزمورة','Mazmourah','mazmourah',33.59567,35.50881,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الجلالية','Jleiliyeh','jleiliyeh',33.60584,35.52914,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'العقبة (الشوف)','Aaqabeh (Chouf)','aaqabeh-chouf',33.58293,35.46804,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'سبرين','Sebrine','sebrine',34.11068,35.71023,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'فدار التحتا','Fdar Et Tahta','fdar-et-tahta',34.13337,35.69283,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'فدار الفوقا','Fdar El Faouqa','fdar-el-faouqa',34.13273,35.70297,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'جباع الشوف','Jbaa (Chouf)','jbaa-chouf',33.6104,35.6292,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'النبي يونس','Nabi Younes','nabi-younes',33.6622,35.41905,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'ضهور عين الحور','Dahr Ain El Haour','dahr-ain-el-haour',33.66048,35.49775,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المعنية','Maaniyeh','maaniyeh',33.63101,35.44774,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'حارة بيت ماضي','Haret Beit Madi','haret-beit-madi',33.66075,35.42479,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مراح المير','Mrah El Mir','mrah-el-mir',33.96109,35.69912,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'سبايل','Sbail','sbail',34.17667,35.74279,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'حصن العر','Hosn Aar','hosn-aar',34.14493,35.72928,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'جربتا','Jrebta','jrebta',34.14062,35.72131,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بمهرين','Bmahrain','bmahrain',34.12368,35.67664,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'الجناح','Jnah','jnah',33.8657,35.48399,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'كفر حمل','Kfar Hamel','kfar-hamel',33.71233,35.57379,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'سبعل','Sebaal','sebaal',33.76093,35.61715,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'منزلة','Manzala','manzala',33.35728,35.49847,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بير الهيت','Bir El Hait','bir-el-hait',34.08842,35.72242,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'المصيلح','Msaileh','msaileh',33.47912,35.35182,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'شبيل','Shbail','shbail',33.42793,35.60034,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'بصفرين','Bsifrine','bsifrine',33.88514,35.70021,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'ملحون','Malhoun','malhoun',34.14439,35.70056,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مربعه','Marbaa','marbaa',34.14963,35.69773,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'منيطرة','Mnaitra','mnaitra',34.07374,35.88919,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'القص','Qass','qass',34.08422,35.72642,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الجمهور','Jamhour','jamhour',33.82825,35.56958,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عبود','Aaboud','aaboud',34.10282,35.85399,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'شلوماس','Chaloumas','chaloumas',34.10269,35.74248,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'بئر حسن','Bir Hassan','bir-hassan',33.86121,35.48934,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الباروك','Barouk','barouk',33.70411,35.68119,true,'city'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المختارة','Moukhtara','moukhtara',33.65738,35.61336,true,'city'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عين الزيتونة','Ain Zaitoune','ain-zaitoune',33.90601,35.74191,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الخلوات (بعبدا)','Khalouat (Baabda)','khalouat-baabda',33.83956,35.73453,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المنتزه','Mountazah','mountazah',33.85472,35.57738,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'دير مشموشة','Deir Machmouche','deir-machmouche',33.5756,35.56537,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'حرازمين','Hrazmin','hrazmin',34.12515,35.79463,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عيدامون','Aydamoun','aydamoun',34.15298,35.65738,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'المعروفية','Maaroufiye','maaroufiye',33.7961,35.53908,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عين التفاحة','Ain Et Toufaha','ain-et-toufaha',33.93356,35.72469,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'ريحانة','Rihane','rihane',34.16722,35.63904,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مشحلان','Mechhellene','mechhellene',34.14306,35.68393,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بركة حجولا','Berket Hejoula','berket-hejoula',34.14017,35.73055,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'عيون السيمان','Aayoun El Siman','aayoun-el-siman',33.99252,35.83922,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مزرعة الجميل','Mazraat Ej Jmaiyel','mazraat-ej-jmaiyel',34.14005,35.68477,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'حاصبيا المتن','Hasbaya El Metn','hasbaya-el-metn',33.87407,35.72423,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'ضهور العبادية','Dhour Al Aabaydiyeh','dhour-al-aabaydiyeh',33.81528,35.62447,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مونتيفردي','Montiverdi','montiverdi',33.84859,35.58844,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'الحوش (صور)','Hosh (Tyre)','hosh-tyre',33.24343,35.23848,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الطيونة','Tayouneh','tayouneh',33.86986,35.51351,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'عطشانة','Aatchaneh','aatchaneh',33.91275,35.64927,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'قصقص','Qasqas','qasqas',33.876,35.50893,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مياسة','Mayasseh','mayasseh',33.93938,35.69409,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'مزرعة كوثرية الرز','Mazraat Kaoutariyet Er Riz','mazraat-kaoutariyet-er-riz',33.37127,35.30006,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'وادي الكرم','Wadi El Karm','wadi-el-karm',33.95036,35.75087,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'المغاير','Mghayer','mghayer',34.03607,35.76846,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بشلي','Bshille','bshille',34.10371,35.7166,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'مزرعة البياض','Mazraat El Bayad','mazraat-el-bayad',33.4208,35.48405,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'وادي شاهين','Wadi Shahine','wadi-shahine',33.93165,35.69248,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مزيرعة بعبدا','Mzairaa Baabda','mzairaa-baabda',33.82986,35.65244,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'كفر قواص','Kfar Qouas','kfar-qouas',34.12412,35.69724,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'بشامون المدارس','Bchamoun El Madares','bchamoun-el-madares',33.77858,35.50703,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'مار الياس (صيدا)','Mar Elias (Saida)','mar-elias-saida',33.55623,35.39153,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الرملة البيضاء','Ramlet El-Baydaa','ramlet-el-baydaa',33.87891,35.48215,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'حرش تابت','Horsh Tabet','horsh-tabet',33.8862,35.57562,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'كورنيش النهر','Corniche Al Naher','corniche-al-naher',33.8881,35.53263,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'أوتيل ديو','Hôtel Dieu','hotel-dieu',33.88154,35.5179,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'شوان','Chouane','chouane',34.07404,35.77551,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'دير بقلوش','Deir Baqlouch','deir-baqlouch',33.99018,35.65759,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'رب التلاتين','Rabb Et Tlatine','rabb-et-tlatine',33.25341,35.51411,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'محيليب','Mheilib','mheilib',33.30679,35.23989,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'الدكرمان','Dekermane','dekermane',33.55104,35.37334,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'الوسطاني (صيدا)','Wastani (Saida)','wastani-saida',33.57635,35.38512,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'مزرعة العيتانية','Mazraat El Yahoudiyeh','mazraat-el-yahoudiyeh',33.35531,35.25434,true,'village'),
((select id from governorates where slug='nabatieh' and country_code='LB'),'عدشيت القصير','Aadchit El Qoussair','aadchit-el-qoussair',33.26971,35.47419,true,'village'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'شويفات القبة','Choueifat El Qobbeh','choueifat-el-qobbeh',33.78664,35.49112,true,'area'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'مزرعة المعادن','Mazraat El Maaden','mazraat-el-maaden',34.11776,35.79449,true,'village'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'الرمانة (جزين)','Roummaneh (Jezzine)','roummaneh-jezzine',33.5076,35.55454,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'جورة القطين','Jouret E Qattine','jouret-e-qattine',34.10458,35.72304,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'ساقية الخيط','Saqiet El Khayt','saqiet-el-khayt',34.162,35.71312,true,'village'),
((select id from governorates where slug='keserwan-jbeil' and country_code='LB'),'بكركي','Bkerke','bkerke',null,null,true,'village'),
((select id from governorates where slug='beirut' and country_code='LB'),'البسطة','Basta','basta',33.8862,35.5038,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'ساسين','Sassine','sassine',33.8873,35.5209,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'التباريس','Tabaris','tabaris',null,null,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الخندق الغميق','Khandak el Ghamik','khandak-el-ghamik',null,null,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الفاكهاني','Fakhani','fakhani',null,null,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'رياض الصلح','Riad el Solh','riad-el-solh',33.8965,35.503,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الملا','Mulla','mulla',null,null,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الوتوات','Watwat','watwat',33.8931,35.4923,true,'area'),
((select id from governorates where slug='beirut' and country_code='LB'),'الزيدانية','Zeidanieh','zeidanieh',33.8883,35.4899,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'مار تقلا','Mar Takla','mar-takla',33.8559,35.5462,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'برازيليا','Brasilia (Baabda)','brasilia-baabda',33.8471,35.5469,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الكفاءات','Kafaat','kafaat',33.8417,35.5279,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'الرويس','Rweiss','rweiss',33.848,35.5148,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'حي ماضي','Hay Madi','hay-madi',null,null,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'صفير','Sfeir','sfeir',null,null,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'دوحة الحص','Doha el Hoss','doha-el-hoss',33.7627,35.4607,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'النبعة','Nabaa','nabaa',null,null,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'نهر الموت','Nahr el Mot','nahr-el-mot',33.8974,35.5663,true,'area'),
((select id from governorates where slug='mount-lebanon' and country_code='LB'),'وادي الزينة','Wadi el Zeineh','wadi-el-zeineh',null,null,true,'city'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'صيدا القديمة','Old Saida','old-saida',33.563,35.3695,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'القياعة','Qiyaa (Saida)','qiyaa-saida',33.5658,35.3883,true,'area'),
((select id from governorates where slug='south-lebanon' and country_code='LB'),'التعمير','Taamir (Saida)','taamir-saida',33.5484,35.381,true,'area')
on conflict (governorate_id,slug) do nothing;
commit;
