-- ============================================================
-- Localise the inbound SMS replies (PROFILE / WAGES / PASSBOOK /
-- DISPUTE / vote / help) into the worker's effective language.
-- Commands (PROFILE, DISPUTE, numbers) stay in English. Run alone.
-- ============================================================

insert into message_templates(key, lang, body) values
-- profile
('profile','en','LabourPass Profile: {{name}} | {{id}} | Skills: {{skills}} | Employers: {{employers}} | Days(90d): {{days}}'),
('profile','hi','LabourPass जानकारी: {{name}} | {{id}} | कौशल: {{skills}} | नियोक्ता: {{employers}} | दिन(90d): {{days}}'),
('profile','bn','LabourPass প্রোফাইল: {{name}} | {{id}} | দক্ষতা: {{skills}} | নিয়োগকর্তা: {{employers}} | দিন(90d): {{days}}'),
('profile','ta','LabourPass சுயவிவரம்: {{name}} | {{id}} | திறன்கள்: {{skills}} | முதலாளிகள்: {{employers}} | நாட்கள்(90d): {{days}}'),
('profile','te','LabourPass ప్రొఫైల్: {{name}} | {{id}} | నైపుణ్యాలు: {{skills}} | యజమానులు: {{employers}} | రోజులు(90d): {{days}}'),
('profile','mr','LabourPass माहिती: {{name}} | {{id}} | कौशल्ये: {{skills}} | नियोक्ते: {{employers}} | दिवस(90d): {{days}}'),
('profile','gu','LabourPass પ્રોફાઇલ: {{name}} | {{id}} | કૌશલ્ય: {{skills}} | નિયોક્તા: {{employers}} | દિવસ(90d): {{days}}'),
('profile','kn','LabourPass ಪ್ರೊಫೈಲ್: {{name}} | {{id}} | ಕೌಶಲ್ಯ: {{skills}} | ಉದ್ಯೋಗದಾತರು: {{employers}} | ದಿನಗಳು(90d): {{days}}'),
('profile','or','LabourPass ପ୍ରୋଫାଇଲ୍: {{name}} | {{id}} | ଦକ୍ଷତା: {{skills}} | ନିଯୁକ୍ତିଦାତା: {{employers}} | ଦିନ(90d): {{days}}'),
-- wages
('wages','en','LabourPass Wages: {{list}} | Total: Rs.{{total}}'),
('wages','hi','LabourPass वेतन: {{list}} | कुल: Rs.{{total}}'),
('wages','bn','LabourPass মজুরি: {{list}} | মোট: Rs.{{total}}'),
('wages','ta','LabourPass ஊதியம்: {{list}} | மொத்தம்: Rs.{{total}}'),
('wages','te','LabourPass వేతనం: {{list}} | మొత్తం: Rs.{{total}}'),
('wages','mr','LabourPass वेतन: {{list}} | एकूण: Rs.{{total}}'),
('wages','gu','LabourPass વેતન: {{list}} | કુલ: Rs.{{total}}'),
('wages','kn','LabourPass ವೇತನ: {{list}} | ಒಟ್ಟು: Rs.{{total}}'),
('wages','or','LabourPass ମଜୁରି: {{list}} | ମୋଟ: Rs.{{total}}'),
('wages_none','en','LabourPass: No wage records yet.'),
('wages_none','hi','LabourPass: अभी कोई वेतन रिकॉर्ड नहीं।'),
-- passbook
('passbook','en','LabourPass Passbook: Days {{days}} | Wages Rs.{{total}} | Verify: {{link}}'),
('passbook','hi','LabourPass पासबुक: दिन {{days}} | वेतन Rs.{{total}} | देखें: {{link}}'),
('passbook','bn','LabourPass পাসবুক: দিন {{days}} | মজুরি Rs.{{total}} | যাচাই: {{link}}'),
('passbook','ta','LabourPass பாஸ்புக்: நாட்கள் {{days}} | ஊதியம் Rs.{{total}} | சரிபார்க்க: {{link}}'),
('passbook','te','LabourPass పాస్‌బుక్: రోజులు {{days}} | వేతనం Rs.{{total}} | చూడండి: {{link}}'),
('passbook','mr','LabourPass पासबुक: दिवस {{days}} | वेतन Rs.{{total}} | पहा: {{link}}'),
('passbook','gu','LabourPass પાસબુક: દિવસ {{days}} | વેતન Rs.{{total}} | જુઓ: {{link}}'),
('passbook','kn','LabourPass ಪಾಸ್‌ಬುಕ್: ದಿನ {{days}} | ವೇತನ Rs.{{total}} | ಪರಿಶೀಲಿಸಿ: {{link}}'),
('passbook','or','LabourPass ପାସବୁକ୍: ଦିନ {{days}} | ମଜୁରି Rs.{{total}} | ଯାଞ୍ଚ: {{link}}'),
-- dispute acknowledgement
('dispute_ack','en','LabourPass: Your complaint {{id}} is registered. We will check within 48 hours.'),
('dispute_ack','hi','LabourPass: आपका विवाद {{id}} दर्ज हुआ। हम 48 घंटे में जाँच करेंगे।'),
('dispute_ack','bn','LabourPass: আপনার অভিযোগ {{id}} নথিভুক্ত। আমরা ৪৮ ঘণ্টায় দেখব।'),
('dispute_ack','ta','LabourPass: உங்கள் புகார் {{id}} பதிவு. 48 மணி நேரத்தில் பரிசீலிப்போம்.'),
('dispute_ack','te','LabourPass: మీ ఫిర్యాదు {{id}} నమోదైంది. 48 గంటల్లో పరిశీలిస్తాం.'),
('dispute_ack','mr','LabourPass: तुमची तक्रार {{id}} नोंदली. आम्ही 48 तासांत तपासू.'),
('dispute_ack','gu','LabourPass: તમારી ફરિયાદ {{id}} નોંધાઈ. અમે 48 કલાકમાં તપાસીશું.'),
('dispute_ack','kn','LabourPass: ನಿಮ್ಮ ದೂರು {{id}} ದಾಖಲಾಗಿದೆ. 48 ಗಂಟೆಗಳಲ್ಲಿ ಪರಿಶೀಲಿಸುತ್ತೇವೆ.'),
('dispute_ack','or','LabourPass: ଆପଣଙ୍କ ଅଭିଯୋଗ {{id}} ଦାଖଲ। ଆମେ 48 ଘଣ୍ଟାରେ ଯାଞ୍ଚ କରିବୁ।'),
-- vote thanks
('vote_thanks','en','LabourPass: Thank you! Your response is recorded.'),
('vote_thanks','hi','LabourPass: धन्यवाद! आपका जवाब दर्ज हुआ।'),
('vote_thanks','bn','LabourPass: ধন্যবাদ! আপনার উত্তর নথিভুক্ত হয়েছে।'),
('vote_thanks','ta','LabourPass: நன்றி! உங்கள் பதில் பதிவாகியது.'),
('vote_thanks','te','LabourPass: ధన్యవాదాలు! మీ సమాధానం నమోదైంది.'),
('vote_thanks','mr','LabourPass: धन्यवाद! तुमचे उत्तर नोंदले.'),
('vote_thanks','gu','LabourPass: આભાર! તમારો જવાબ નોંધાયો.'),
('vote_thanks','kn','LabourPass: ಧನ್ಯವಾದ! ನಿಮ್ಮ ಉತ್ತರ ದಾಖಲಾಗಿದೆ.'),
('vote_thanks','or','LabourPass: ଧନ୍ୟବାଦ! ଆପଣଙ୍କ ଉତ୍ତର ଦାଖଲ।'),
('vote_none','en','LabourPass: No pending rating right now.'),
('vote_none','hi','LabourPass: अभी कोई पेंडिंग रेटिंग नहीं।'),
-- not registered / help / unknown
('not_registered','en','LabourPass: You are not registered. Ask your employer to register you.'),
('not_registered','hi','LabourPass: आप पंजीकृत नहीं हैं। अपने नियोक्ता से पंजीकरण कराएं।'),
('help','en','LabourPass: Send PROFILE, WAGES, PASSBOOK, DISPUTE <date>, WAGEDISPUTE <amt>, 1/2 (rating).'),
('help','hi','LabourPass: PROFILE, WAGES, PASSBOOK, DISPUTE <date>, WAGEDISPUTE <amt>, 1/2 bhejein.'),
('unknown','en','LabourPass: Did not understand. Send HELP for the command list.'),
('unknown','hi','LabourPass: Samajh nahi aaya. Commands ke liye HELP bhejein.')
on conflict (key, lang) do update set body = excluded.body;

-- ---- rewired inbound parser ----
create or replace function sms_inbound(p_sender text, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_w workers; v_body text; v_reply text; v_lang language_code;
        v_tr trust_ratings; v_disp uuid; v_list text; v_total numeric;
begin
  v_body := upper(trim(p_body));
  insert into sms_logs(direction, phone, message, status) values ('inbound', p_sender, p_body, 'received');

  select * into v_w from workers where phone = p_sender;
  if v_w.id is null then
    v_reply := render_msg('not_registered', 'en');
    perform _send_sms(p_sender, v_reply, 'en', 'inbound', null);
    return jsonb_build_object('reply', v_reply);
  end if;

  v_lang := effective_lang(v_w.preferred_language, v_w.state);

  if v_body = 'PROFILE' then
    v_reply := render_msg('profile', v_lang, jsonb_build_object(
      'name', v_w.full_name, 'id', v_w.public_id,
      'skills', coalesce((select string_agg(skill::text, ', ') from worker_skills where worker_id = v_w.id), '-'),
      'employers', (select count(distinct employer_id) from engagements where worker_id = v_w.id)::text,
      'days', (select count(*) from attendance_records
               where worker_id = v_w.id and status in ('present','half_day') and attendance_date > current_date - 90)::text));

  elsif v_body = 'WAGES' then
    select string_agg(to_char(payment_date,'DD-Mon')||' Rs.'||amount, ' | ' order by payment_date desc),
           coalesce(sum(amount),0)
      into v_list, v_total
      from (select payment_date, amount from wage_records where worker_id = v_w.id order by payment_date desc limit 3) x;
    if v_list is null then
      v_reply := render_msg('wages_none', v_lang);
    else
      v_reply := render_msg('wages', v_lang, jsonb_build_object('list', v_list, 'total', v_total::text));
    end if;

  elsif v_body = 'PASSBOOK' then
    v_reply := render_msg('passbook', v_lang, jsonb_build_object(
      'days', (select count(*) from attendance_records where worker_id = v_w.id and status in ('present','half_day'))::text,
      'total', (select coalesce(sum(amount),0) from wage_records where worker_id = v_w.id)::text,
      'link', '/verify/passbook/' || v_w.public_id));

  elsif v_body like 'WAGEDISPUTE%' then
    insert into disputes(worker_id, employer_id, dispute_type, description, reported_via)
      values (v_w.id, (select employer_id from wage_records where worker_id = v_w.id order by created_at desc limit 1),
              'wage', p_body, 'sms') returning id into v_disp;
    v_reply := render_msg('dispute_ack', v_lang, jsonb_build_object('id', substr(v_disp::text,1,8)));

  elsif v_body like 'DISPUTE%' then
    insert into disputes(worker_id, employer_id, dispute_type, description, reported_via)
      values (v_w.id, (select employer_id from attendance_records where worker_id = v_w.id order by created_at desc limit 1),
              'attendance', p_body, 'sms') returning id into v_disp;
    v_reply := render_msg('dispute_ack', v_lang, jsonb_build_object('id', substr(v_disp::text,1,8)));

  elsif v_body in ('1','2') then
    select * into v_tr from trust_ratings
      where worker_id = v_w.id and sms_sent_at is not null and responded_at is null
      order by sms_sent_at desc limit 1;
    if v_tr.id is null then
      v_reply := render_msg('vote_none', v_lang);
    else
      update trust_ratings set rating = v_body::smallint, responded_at = now(), response_raw = v_body where id = v_tr.id;
      perform recompute_trust(v_tr.employer_id);
      v_reply := render_msg('vote_thanks', v_lang);
    end if;

  elsif v_body = 'HELP' then
    v_reply := render_msg('help', v_lang);
  else
    v_reply := render_msg('unknown', v_lang);
  end if;

  perform _send_sms(p_sender, v_reply, v_lang, 'inbound', null);
  return jsonb_build_object('reply', v_reply);
end; $$;
