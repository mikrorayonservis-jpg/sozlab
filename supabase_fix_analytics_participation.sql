-- ════════════════════════════════════════════════════════════════
-- SözLab — DÜZƏLİŞ: Məktəb analitikasında "Şagird iştirakı" 100%-dən çox çıxırdı
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin (bir dəfə).
--
-- PROBLEM: məxrəc yalnız şagirdləri sayırdı (role='user'), surət isə 205 Points
-- qazanan HƏR KƏSİ (admin, müəllim, direktor da). Müəllimlər də fəal olanda
-- iştirak 133% kimi mənasız rəqəm göstərirdi.
-- HƏLL: surət də yalnız şagirdləri sayır. Başqa heç nə dəyişmir.
-- (supabase_FULL_SETUP.sql-də bu düzəliş artıq var.)
-- ════════════════════════════════════════════════════════════════

create or replace function public.ss_school_analytics()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.ss_is_staff(auth.uid()) then raise exception 'İcazə yoxdur'; end if;
  return jsonb_build_object(
    'students',        (select count(*) from public.profiles where role='user'),
    -- Yalnız ŞAGİRDLƏR sayılır: əvvəl admin/müəllim/direktorun xalları da sayılırdı,
    -- məxrəc isə yalnız şagird idi — iştirak faizi 100%-dən çox çıxırdı (məs. 133%).
    'active_students', (select count(distinct l.username) from public.ss_points_ledger l
                         join public.profiles p on p.username = l.username and p.role = 'user'
                         where l.created_at > now() - interval '30 days'),
    'startups',        (select count(*) from public.ss_startups),
    'startups_by_stage', (select coalesce(jsonb_object_agg(stage, n),'{}'::jsonb)
                           from (select stage, count(*) n from public.ss_startups group by stage) t),
    'problems',        (select count(*) from public.ss_problems),
    'problems_solved', (select count(*) from public.ss_problems where status in ('solved','implemented')),
    'solutions',       (select count(*) from public.ss_solutions),
    'challenges',      (select count(*) from public.ss_challenges),
    'submissions',     (select count(*) from public.ss_submissions),
    'humanity',        (select count(*) from public.ss_humanity_projects),
    'connections',     (select count(*) from public.ss_schools where status='connected' and not is_home),
    'olympics_events', (select count(*) from public.ss_olympics_events),
    'olympics_participants', (select count(distinct username) from public.ss_olympics_results),
    'points_total',    (select coalesce(sum(amount),0) from public.ss_points_ledger where amount>0),
    'teams',           (select count(*) from public.ss_teams),
    'by_category',     (select coalesce(jsonb_object_agg(category, n),'{}'::jsonb)
                         from (select category, count(*) n from public.ss_problems group by category) t),
    'monthly',         (select coalesce(jsonb_agg(row_to_json(m) order by m.ym),'[]'::jsonb) from (
                          select to_char(date_trunc('month',created_at),'YYYY-MM') ym, count(*) n
                          from public.ss_points_ledger
                          where created_at > now() - interval '6 months'
                          group by 1) m)
  );
end;
$$;
grant execute on function public.ss_school_analytics() to authenticated;
