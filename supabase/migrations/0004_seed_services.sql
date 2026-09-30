-- ============================================================
-- QuickServe — 0004_seed_services.sql
-- ============================================================
insert into public.services (name, description) values
  ('AC Servicing',    'Installation, gas refill, deep cleaning and repair of split/window AC units.'),
  ('Plumbing',        'Leak repairs, tap and mixer fitting, drain unclogging and pipe replacement.'),
  ('Electrical',      'Wiring repair, switch/socket installation, fan fitting and load testing.'),
  ('Cleaning',        'Deep cleaning of kitchen, bathroom, living space and post-renovation cleanup.')
on conflict (name) do nothing;
