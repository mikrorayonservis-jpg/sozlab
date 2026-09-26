-- ════════════════════════════════════════════════════════════════════════
-- SözLab — TƏHLÜKƏSİZLİK DÜZƏLİŞİ (sentyabr 2026)
-- Supabase → SQL Editor → bu faylı bütövlükdə yapışdırın → Run.
-- Təkrar işə salmaq təhlükəsizdir (idempotent).
--
-- Bağlanan boşluqlar:
--  1) ss_award_points: istənilən şagird özünə limitsiz 205 Points yaza bilirdi.
--     İndi: heyət (admin/direktor/müəllim/mentor) istənilən xalı verə bilər;
--     şagird yalnız özünə və yalnız saytın özünün verdiyi iki hadisə üçün:
--       • "Startap quruldu" — qurduğu hər startap üçün bir dəfə, ≤200
--       • "205 Olympics"   — hər yarış üçün bir dəfə, nəticəsi yazılıbsa, ≤150
--  2) log_xp_gain: başqasının XP jurnalına yazmaq olurdu → yalnız özününkü.
--  3) Şagird "təsdiq/qiymət/səs/medal" sütunlarını özü yaza bilirdi
--     (məs. öz işini birbaşa status='approved' ilə göndərmək → portalda dərhal
--     görünürdü; startapına 9999 səs yazmaq). İndi bu sütunları yalnız heyət
--     və server funksiyaları dəyişir. Saytın normal işinə təsir etmir.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1+2: daxili (yoxlamasız) köməkçilər — API-dən çağırıla bilməz ─────────
create or replace function public._xp_log_add(p_username text, p_date date, p_amount integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_amount is null or p_amount <= 0 then return; end if;
  insert into public.xp_log(username, log_date, xp_gained)
  values (p_username, p_date, p_amount)
  on conflict (username, log_date) do update set xp_gained = xp_log.xp_gained + excluded.xp_gained;
end $$;

create or replace function public._ss_award_internal(p_username text, p_amount integer, p_reason text, p_source text, p_ref_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare v_balance integer;
begin
  if p_username is null or p_username = '' then return 0; end if;
  if p_amount is null or p_amount = 0 then return 0; end if;
  if p_amount < 0 then
    perform 1 from public.profiles where username = p_username for update;   -- eyni anda iki xərcləmənin qarşısı
    select coalesce(sum(amount),0) into v_balance from public.ss_points_ledger where username = p_username;
    if v_balance + p_amount < 0 then raise exception '205 Points kifayət etmir'; end if;
  end if;
  insert into public.ss_points_ledger(username, amount, reason, source, ref_id)
  values (p_username, p_amount, p_reason, p_source, p_ref_id);
  select coalesce(sum(amount),0) into v_balance from public.ss_points_ledger where username = p_username;
  return v_balance;
end $$;

revoke all on function public._xp_log_add(text, date, integer) from public, anon, authenticated;
revoke all on function public._ss_award_internal(text, integer, text, text, bigint) from public, anon, authenticated;

-- Mövcud server funksiyaları daxili köməkçiləri çağırsın (mətn avtomatik yenilənir)
do $$
declare r record; v_def text; v_new text;
begin
  for r in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname not in ('log_xp_gain', 'ss_award_points', '_xp_log_add', '_ss_award_internal')
      and p.prokind = 'f'
  loop
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(replace(v_def, 'public.log_xp_gain(', 'public._xp_log_add('),
                     'public.ss_award_points(', 'public._ss_award_internal(');
    if v_new <> v_def then
      execute v_new;
      raise notice 'yeniləndi: %', r.proname;
    end if;
  end loop;
end $$;

-- ── Açıq (yoxlamalı) versiyalar ──────────────────────────────────────────
create or replace function public.log_xp_gain(p_username text, p_date date, p_amount integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_username is distinct from (select username from public.profiles where id = auth.uid()) then
    raise exception 'İcazə yoxdur';
  end if;
  perform public._xp_log_add(p_username, p_date, p_amount);
end $$;

create or replace function public.ss_award_points(p_username text, p_amount integer, p_reason text, p_source text default 'system', p_ref_id bigint default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v_me text; v_founded integer; v_claimed integer;
begin
  select username into v_me from public.profiles where id = auth.uid();
  if v_me is null then raise exception 'İcazə yoxdur'; end if;

  if not public.ss_is_staff(auth.uid()) then
    if p_username is distinct from v_me or coalesce(p_amount, 0) < 0 then
      raise exception 'İcazə yoxdur';
    end if;
    if p_source = 'startup' then
      if p_amount > 200 or coalesce(p_reason, '') not like 'Startap quruldu:%' then raise exception 'İcazə yoxdur'; end if;
      perform 1 from public.profiles where id = auth.uid() for update;
      select count(*) into v_founded from public.ss_startups where founder = v_me;
      select count(*) into v_claimed from public.ss_points_ledger
        where username = v_me and source = 'startup' and reason like 'Startap quruldu:%';
      if v_claimed >= v_founded then raise exception 'İcazə yoxdur'; end if;
    elsif p_source = 'olympics' then
      if p_amount > 150 or p_ref_id is null then raise exception 'İcazə yoxdur'; end if;
      if not exists (select 1 from public.ss_olympics_results where username = v_me and event_id = p_ref_id) then
        raise exception 'İcazə yoxdur';
      end if;
      perform 1 from public.profiles where id = auth.uid() for update;
      if exists (select 1 from public.ss_points_ledger where username = v_me and source = 'olympics' and ref_id = p_ref_id) then
        return (select coalesce(sum(amount),0) from public.ss_points_ledger where username = v_me);
      end if;
    else
      raise exception 'İcazə yoxdur';
    end if;
  end if;

  return public._ss_award_internal(p_username, p_amount, p_reason, p_source, p_ref_id);
end $$;

grant execute on function public.log_xp_gain(text, date, integer) to authenticated;
grant execute on function public.ss_award_points(text, integer, text, text, bigint) to authenticated;

-- ── 3: təsdiq sütunlarının qoruyucusu ────────────────────────────────────
-- Birbaşa API sorğusunda current_user = 'authenticated' olur; server
-- funksiyalarının (security definer) içində isə sahib roludur — onlara toxunulmur.
-- DİQQƏT: bu funksiya qəsdən SECURITY INVOKER-dir — yoxsa current_user həmişə
-- sahib olardı və yoxlama işləməzdi.
create or replace function public.guard_review_columns()
returns trigger language plpgsql security invoker set search_path = public as $$
declare v_staff boolean;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;

  if tg_table_name = 'school_submissions' then
    v_staff := public.is_school_staff(auth.uid());
  elsif tg_table_name = 'stories' then
    v_staff := public.is_admin(auth.uid()) or public.is_director(auth.uid());
  else
    v_staff := public.ss_is_staff(auth.uid());
  end if;
  if v_staff then return new; end if;

  if tg_op = 'INSERT' then
    case tg_table_name
      when 'school_submissions' then new.status := 'pending'; new.admin_note := ''; new.reviewed_by := null; new.reviewed_at := null;
      when 'ss_submissions' then new.status := 'submitted'; new.score := null; new.feedback := '';
      when 'ss_solutions' then new.status := 'submitted'; new.feedback := ''; if new.stage = 'implemented' then new.stage := 'idea'; end if;
      when 'ss_startups' then new.votes := 0; new.stage := 'idea'; new.status := 'active';
      when 'ss_humanity_projects' then new.stage := 'research'; new.impact_points := 20; new.status := 'active';
      when 'ss_olympics_results' then new.medal := null; new.rank := null;
      when 'stories' then new.likes := 0;
      else null;
    end case;
  else
    case tg_table_name
      when 'ss_submissions' then new.status := old.status; new.score := old.score; new.feedback := old.feedback;
      when 'ss_solutions' then new.status := old.status; new.feedback := old.feedback;
        if new.stage = 'implemented' and old.stage <> 'implemented' then new.stage := old.stage; end if;  -- son mərhələni müəllim təsdiqləyir
      when 'ss_startups' then new.votes := old.votes; new.stage := old.stage; new.status := old.status; new.demo_day := old.demo_day;
      when 'ss_humanity_projects' then new.status := old.status;
        -- Humanity Points mərhələdən hesablanır (sayt da eyni düsturu işlədir: 20 × mərhələ nömrəsi)
        new.impact_points := 20 * coalesce(array_position(array['research','idea','team','solution','prototype','presentation'], new.stage), 1);
      when 'ss_olympics_results' then new.medal := old.medal; new.rank := old.rank;
      else null;
    end case;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['school_submissions','ss_submissions','ss_solutions','ss_startups',
                           'ss_humanity_projects','ss_olympics_results','stories'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists guard_review_columns on public.%I', t);
      execute format('create trigger guard_review_columns before insert or update on public.%I
                      for each row execute function public.guard_review_columns()', t);
    end if;
  end loop;
end $$;

-- Yoxlama: aşağıdakı sorğu "ok" qaytarmalıdır
select case when exists (select 1 from pg_trigger where tgname = 'guard_review_columns')
             and exists (select 1 from pg_proc where proname = '_ss_award_internal')
            then 'ok — təhlükəsizlik düzəlişi tətbiq olundu' else 'XƏTA' end as netice;
