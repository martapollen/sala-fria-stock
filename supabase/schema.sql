-- Sala Fria — Registo de Movimentos de Stock
-- Corre este ficheiro completo no SQL Editor do teu projeto Supabase
-- (Project → SQL Editor → New query → cola tudo → Run).
-- É seguro correr mais que uma vez: as tabelas só são criadas se não existirem
-- e o catálogo de componentes é substituído (upsert) pelos valores abaixo.

-- ────────────────────────────────────────────────────────────────
-- 1. Tabelas
-- ────────────────────────────────────────────────────────────────

create table if not exists items (
  id          text primary key,
  produto     text,
  categoria   text,
  ref         text,
  nome        text not null,
  qty         numeric,              -- stock inicial; null = quantidade por confirmar
  unit        text,                 -- ex. 'm' para cabos medidos em metros
  qty_approx  boolean not null default false,  -- true = valor estimado, não exato
  qty_note    text,                 -- nota livre (ex. texto original do documento)
  created_at  timestamptz not null default now()
);

create table if not exists movements (
  id          uuid primary key default gen_random_uuid(),
  item_id     text not null references items(id),
  nome        text not null,        -- nome do componente à data do movimento
  categoria   text,
  ref         text,
  produto     text,
  person      text not null,        -- quem movimentou
  qty         numeric not null,     -- quantidade movimentada (sempre positiva)
  direction   text not null check (direction in ('in', 'out')),
  delta       numeric not null,     -- +qty (entrada) ou -qty (saída)
  notes       text,                 -- nota livre opcional escrita por quem regista o movimento
  created_at  timestamptz not null default now()
);

alter table movements add column if not exists notes text;

create index if not exists movements_item_id_idx on movements (item_id);
create index if not exists movements_created_at_idx on movements (created_at desc);

-- ────────────────────────────────────────────────────────────────
-- 2. View: stock atual = qty base + soma dos movimentos
--    (mantém a mesma lógica que a app já usava)
-- ────────────────────────────────────────────────────────────────

create or replace view item_stock as
select
  i.*,
  case when i.qty is null then null else i.qty + coalesce(m.net, 0) end as current_stock
from items i
left join (
  select item_id, sum(delta) as net
  from movements
  group by item_id
) m on m.item_id = i.id;

-- ────────────────────────────────────────────────────────────────
-- 3. Row Level Security
--    Catálogo (items): qualquer pessoa com a chave pública (anon) pode ler
--    e adicionar um componente novo (todos os campos obrigatórios, impostos
--    pela app), mas não editar nem apagar os já existentes — isso continua
--    reservado ao SQL Editor.
--    Movimentos: qualquer pessoa com a chave pública pode ler e criar
--    (registar um movimento), mas não editar nem apagar — é um livro de
--    registo, tal como na app original.
-- ────────────────────────────────────────────────────────────────

alter table items enable row level security;
alter table movements enable row level security;

drop policy if exists "items are publicly readable" on items;
create policy "items are publicly readable"
  on items for select
  using (true);

drop policy if exists "anyone can add a new component" on items;
create policy "anyone can add a new component"
  on items for insert
  with check (
    nome is not null and nome <> '' and
    produto is not null and produto <> '' and
    categoria is not null and categoria <> '' and
    ref is not null and ref <> '' and
    qty is not null
  );

drop policy if exists "movements are publicly readable" on movements;
create policy "movements are publicly readable"
  on movements for select
  using (true);

drop policy if exists "anyone can register a movement" on movements;
create policy "anyone can register a movement"
  on movements for insert
  with check (true);

-- ────────────────────────────────────────────────────────────────
-- 4. Realtime — sem isto, os outros separadores/pessoas com a página
--    aberta só veem um movimento novo depois de recarregar a página.
--    (idempotente: não falha se já estiver ativado)
-- ────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'items'
  ) then
    execute 'alter publication supabase_realtime add table public.items';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'movements'
  ) then
    execute 'alter publication supabase_realtime add table public.movements';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lead_times'
  ) then
    execute 'alter publication supabase_realtime add table public.lead_times';
  end if;
end $$;

-- ────────────────────────────────────────────────────────────────
-- 3b. Lead times — tab "Suppliers". Uma linha por componente de BOM
--     (identificado pelo "id" estável gerado para cada linha do
--     BOM_DATA no index.html), com o lead time em dias.
--     A Marta preencheu os valores e pediu para bloquear a edição a
--     partir da app — por isso só há policy de leitura pública.
--     Qualquer alteração futura aos valores é feita diretamente aqui
--     no SQL Editor (ex.: update lead_times set lead_time_days = ...
--     where bom_line_id = '...';).
-- ────────────────────────────────────────────────────────────────

create table if not exists lead_times (
  bom_line_id     text primary key,
  lead_time_days  numeric,
  updated_at      timestamptz not null default now()
);

alter table lead_times enable row level security;

drop policy if exists "lead times are publicly readable" on lead_times;
create policy "lead times are publicly readable"
  on lead_times for select
  using (true);

drop policy if exists "anyone can set a lead time" on lead_times;
drop policy if exists "anyone can update a lead time" on lead_times;
drop policy if exists "anyone can clear a lead time" on lead_times;

-- ────────────────────────────────────────────────────────────────
-- 5. Catálogo de componentes (134 itens, com as 7 quantidades
--    corrigidas: cabos "<25m" → ~25m, "100m" → 100m, "varios" → por confirmar)
-- ────────────────────────────────────────────────────────────────

insert into items (id, produto, categoria, ref, nome, qty, unit, qty_approx, qty_note) values
  ('shell-elephant', 'Battery', '4 - Battery', NULL, 'Shell elephant', 9.0, NULL, false, NULL),
  ('shell-fox', 'Battery', '4 - Battery', NULL, 'shell fox', 20.0, NULL, false, NULL),
  ('daly-bms', 'Battery', '4 - Battery', NULL, 'Daly BMS', 39.0, NULL, false, NULL),
  ('smart-circuit-breaker', 'Station', '3.1 - Dune electrical area', NULL, 'Smart circuit breaker', 47.0, NULL, false, NULL),
  ('dune-slot-motherboard-pcb', 'Station', '2.2 - Dune SLOT', NULL, 'Dune Slot motherboard PCB', 20.0, NULL, false, NULL),
  ('dune-slot-antenna-pcb', 'Station', '2.2 - Dune SLOT', NULL, 'Dune slot antenna pcb', 50.0, NULL, false, NULL),
  ('fan-dust-cover', 'Station', '2.1 - Dune STATION', NULL, 'Fan dust cover', 214.0, NULL, false, NULL),
  ('station-can-next-v', 'Station', '2.1 - Dune STATION', NULL, 'Station_CAN_Next_V', 20.0, NULL, false, NULL),
  ('station-ntc-ea', 'Station', '2.1 - Dune STATION', NULL, 'Station_NTC_EA', 7.0, NULL, false, NULL),
  ('station-can-next-h', 'Station', '2.1 - Dune STATION', NULL, 'Station_CAN_Next_H', 110.0, NULL, false, NULL),
  ('servo-mg996r-old-servos-servo-horns', 'Station', '1 - On hold', NULL, 'Servo MG996R (OLD SERVOS) + servo horns', 297.0, NULL, false, NULL),
  ('old-horwin-slave-side', 'Dock', '1 - On hold', NULL, 'Old horwin slave side', 8.0, NULL, false, NULL),
  ('old-horwin-master-side', 'Dock', '1 - On hold', NULL, 'Old horwin master side', 4.0, NULL, false, NULL),
  ('old-horwin-master-bottom', 'Dock', '1 - On hold', NULL, 'Old horwin master bottom', 3.0, NULL, false, NULL),
  ('old-super-soco-master-side', 'Dock', '1 - On hold', NULL, 'Old Super soco master side', 8.0, NULL, false, NULL),
  ('old-super-soco-slave-side', 'Dock', '1 - On hold', NULL, 'Old super soco slave side', 4.0, NULL, false, NULL),
  ('old-horwin-master', 'Dock', '1 - On hold', NULL, 'Old horwin master', 3.0, NULL, false, NULL),
  ('old-horwin-slave-side-2', 'Dock', '1 - On hold', NULL, 'Old horwin slave side', 2.0, NULL, false, NULL),
  ('old-supersoco-master', 'Dock', '1 - On hold', NULL, 'Old supersoco master', 5.0, NULL, false, NULL),
  ('old-supersoco-slave', 'Dock', '1 - On hold', NULL, 'old supersoco slave', 1.0, NULL, false, NULL),
  ('chogori-connector-horwin-sem-ficha-fim', 'Dock', '1 - On hold', NULL, 'chogori connector (horwin) sem ficha fim', 51.0, NULL, false, NULL),
  ('red-cable', 'Station', '3.1 - Dune electrical area', NULL, 'Red cable', 25.0, 'm', true, '<25m no documento original — estimativa'),
  ('brown-cable', 'Station', '3.1 - Dune electrical area', NULL, 'Brown cable', 25.0, 'm', true, '<25m no documento original — estimativa'),
  ('black-cable', 'Station', '3.1 - Dune electrical area', NULL, 'Black cable', 25.0, 'm', true, '<25m no documento original — estimativa'),
  ('blue-cable', 'Station', '3.1 - Dune electrical area', NULL, 'Blue cable', 25.0, 'm', true, '<25m no documento original — estimativa'),
  ('yellow-green-cable', 'Station', '3.1 - Dune electrical area', NULL, 'Yellow/ green cable', 25.0, 'm', true, '<25m no documento original — estimativa'),
  ('conector-de-alimentacao-ac-3-fases-cabos', 'Station', '3.1 - Dune electrical area', NULL, 'Conector de alimentação AC 3 fases (CABOS ficha macho)', 1.0, NULL, false, NULL),
  ('conector-de-alimentacao-ac-3-fases-cabos-2', 'Station', '3.1 - Dune electrical area', NULL, 'Conector de alimentação AC 3 fases (CABOS ficha macho) + conector macho', 4.0, NULL, false, NULL),
  ('kit-jigs-de-baterias', 'Battery', '3.2 - Battery Jigs', NULL, 'kit jigs de baterias', 1.0, NULL, false, NULL),
  ('fox-10s-pcb', 'Battery', '4 - Battery', NULL, 'fox 10s PCB', 42.0, NULL, false, NULL),
  ('fox-ecs-pcb', 'Battery', '4 - Battery', NULL, 'fox ecs pcb', 29.0, NULL, false, NULL),
  ('nfc-tag', 'Battery', '4 - Battery', NULL, 'NFC tag', 606.0, NULL, false, NULL),
  ('termistor-ntc-jst', 'Battery', '4 - Battery', NULL, 'Termistor NTC JST', 20.0, NULL, false, NULL),
  ('oring-d4x2mm', 'Battery', '4 - Battery', NULL, 'Oring D4x2mm', 315.0, NULL, false, NULL),
  ('oring-d7x1-5mm', 'Battery', '4 - Battery', NULL, 'Oring D7x1.5mm', 500.0, NULL, false, NULL),
  ('m4-screw-cap', 'Battery', '4 - Battery', NULL, 'M4 screw cap', 390.0, NULL, false, NULL),
  ('power-cables-bedrock', 'Station', '4 - Battery', NULL, 'power cables bedrock', NULL, NULL, false, '"varios" no documento original — quantidade por confirmar'),
  ('roda-de-carroca', 'Battery', '4 - Battery', NULL, 'roda de carroça', 58.0, NULL, false, NULL),
  ('roda-de-carroca-c-goretex', 'Battery', '4 - Battery', NULL, 'roda de carroça c goretex', 120.0, NULL, false, NULL),
  ('m6-screw-cap', 'Battery', '4 - Battery', NULL, 'M6 screw cap', 169.0, NULL, false, NULL),
  ('bms-rubber-bottom', 'Battery', '4 - Battery', NULL, 'BMS rubber bottom', 57.0, NULL, false, NULL),
  ('bms-rubber-cover', 'Battery', '4 - Battery', NULL, 'BMS rubber cover', 59.0, NULL, false, NULL),
  ('gnd-screw-holder', 'Battery', '4 - Battery', NULL, 'GND screw holder', 20.0, NULL, false, NULL),
  ('lock-o-ring', 'Battery', '4 - Battery', NULL, 'lock o ring', 127.0, NULL, false, NULL),
  ('copper-gnd-plate', 'Battery', '4 - Battery', NULL, 'copper gnd plate', 18.0, NULL, false, NULL),
  ('cable-uart-bms', 'Battery', '4 - Battery', NULL, 'Cable - UART-BMS', 15.0, NULL, false, NULL),
  ('cable-ecs', 'Battery', '4 - Battery', NULL, 'Cable - ECS', 9.0, NULL, false, NULL),
  ('cable-bms', 'Battery', '4 - Battery', NULL, 'Cable - BMS', 3.0, NULL, false, NULL),
  ('power-switch-disconnector-3-phase-isolat', 'Station', '3.1 - Dune electrical area', NULL, 'Power switch disconnector / 3-Phase Isolator (botoneira)', 1.0, NULL, false, NULL),
  ('fan-and-lighting-fuse-holder', 'Station', '3.1 - Dune electrical area', '1SNF100023R0000', 'Fan and lighting fuse holder', 9.0, NULL, false, NULL),
  ('fan-and-lighting-fuse-2a-32mm-x-8mm', 'Station', '3.1 - Dune electrical area', NULL, 'Fan and lighting fuse, 2A, 32mm x 8mm', 19.0, NULL, false, NULL),
  ('tomada-shucko', 'Station', '3.1 - Dune electrical area', NULL, 'Tomada Shucko', 8.0, NULL, false, NULL),
  ('rpi-router-power-supply', 'Station', '3.1 - Dune electrical area', NULL, 'RPi + Router Power Supply', 1.0, NULL, false, NULL),
  ('shelly-plug-gen-3', 'Station', '3.1 - Dune electrical area', NULL, 'Shelly plug gen 3', 2.0, NULL, false, NULL),
  ('shelly-smart-switch-gen-4', 'Station', '3.1 - Dune electrical area', NULL, 'Shelly smart switch gen 4', 1.0, NULL, false, NULL),
  ('calha-din', 'Station', '3.1 - Dune electrical area', NULL, 'Calha din', 6.0, NULL, false, NULL),
  ('antenna-lte', 'Station', '3.1 - Dune electrical area', NULL, 'Antenna LTE', 12.0, NULL, false, NULL),
  ('antenna-wifi', 'Station', '3.1 - Dune electrical area', NULL, 'Antenna WiFi', 2.0, NULL, false, NULL),
  ('rpi-can-hat', 'Station', '3.1 - Dune electrical area', NULL, 'RPI Can HAT', 1.0, NULL, false, NULL),
  ('electrical-area-fan-heat-sink', 'Station', '3.1 - Dune electrical area', NULL, 'Electrical Area Fan / Heat sink', 4.0, NULL, false, NULL),
  ('fita-de-calafetagem-borracha-2-6mmx6m', 'Station', '3.1 - Dune electrical area', NULL, 'Fita de calafetagem BORRACHA 2-6MMX6M', 16.0, NULL, false, NULL),
  ('pin-locks', 'Station', '2.2 - Dune SLOT', NULL, 'Pin locks', 150.0, NULL, false, NULL),
  ('pin-locks-retificados', 'Station', '2.2 - Dune SLOT', NULL, 'Pin locks retificados', 56.0, NULL, false, NULL),
  ('handle-with-square-bases', 'Station', '2.1 - Dune STATION', NULL, 'HANDLE WITH SQUARE BASES', 19.0, NULL, false, NULL),
  ('rpi-hat-pcb', 'Station', '2.2 - Dune SLOT', NULL, 'RPI-HAT PCB', 11.0, NULL, false, NULL),
  ('rfid-pcb', 'Station', '2.2 - Dune SLOT', NULL, 'RFID PCB', 19.0, NULL, false, NULL),
  ('station-logo-led', 'Station', '2.1 - Dune STATION', NULL, 'Station Logo led', 24.0, NULL, false, NULL),
  ('station-led-cables', 'Station', '2.1 - Dune STATION', NULL, 'station Led cables', 22.0, NULL, false, NULL),
  ('castle-power-cable-slot-2', 'Station', NULL, NULL, 'Castle Power cable slot 2', 2.0, NULL, false, NULL),
  ('castle-power-cable-slot-3', 'Station', NULL, NULL, 'Castle Power cable slot 3', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-5', 'Station', NULL, NULL, 'Castle Power cable slot 5', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-6', 'Station', NULL, NULL, 'Castle Power cable slot 6', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-7', 'Station', NULL, NULL, 'Castle Power cable slot 7', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-8', 'Station', NULL, NULL, 'Castle Power cable slot 8', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-9', 'Station', NULL, NULL, 'Castle Power cable slot 9', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-10', 'Station', NULL, NULL, 'Castle Power cable slot 10', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-13', 'Station', NULL, NULL, 'Castle Power cable slot 13', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-14', 'Station', NULL, NULL, 'Castle Power cable slot 14', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-15', 'Station', NULL, NULL, 'Castle Power cable slot 15', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-16', 'Station', NULL, NULL, 'Castle Power cable slot 16', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-17', 'Station', NULL, NULL, 'Castle Power cable slot 17', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-18', 'Station', NULL, NULL, 'Castle Power cable slot 18', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-19', 'Station', NULL, NULL, 'Castle Power cable slot 19', 1.0, NULL, false, NULL),
  ('castle-power-cable-slot-20', 'Station', NULL, NULL, 'Castle Power cable slot 20', 1.0, NULL, false, NULL),
  ('cell-holder-spacer', 'Battery', '4 - Battery', NULL, 'Cell holder spacer', 918.0, NULL, false, NULL),
  ('acrilicos-electrical-area', 'Station', '3.1 - Dune electrical area', NULL, 'Acrilicos electrical area', 8.0, NULL, false, NULL),
  ('bms-holder', 'Battery', '4 - Battery', NULL, 'BMS holder', 11.0, NULL, false, NULL),
  ('lock-mech-body', 'Station', '2.2 - Dune SLOT', 'SLT-D-PLS-023', 'LOCK MECH BODY', 39.0, NULL, false, NULL),
  ('motherboard-cover-v0', 'Station', '2.2 - Dune SLOT', 'SLT-D-PLS-008', 'MOTHERBOARD COVER (v0)', 4.0, NULL, false, NULL),
  ('front-top-cover-v0', 'Station', '2.2 - Dune SLOT', 'SLT-D-PLS-009', 'FRONT TOP COVER (v0)', 3.0, NULL, false, NULL),
  ('rear-top-cover-v0', 'Station', '2.2 - Dune SLOT', 'SLT-D-PLS-010', 'REAR TOP COVER (v0)', 7.0, NULL, false, NULL),
  ('powerswitch-station-pcb', 'Station', '2.1 - Dune STATION', NULL, 'PowerSwitch Station PCB', 27.0, NULL, false, NULL),
  ('motherboard-station-pcb', 'Station', '2.1 - Dune STATION', NULL, 'Motherboard Station PCB', 12.0, NULL, false, NULL),
  ('cable-uart-bms-2', 'Battery', '4 - Fox spare parts', NULL, 'Cable - UART-BMS', 65.0, NULL, false, NULL),
  ('cable-ecs-2', 'Battery', '4 - Fox spare parts', NULL, 'Cable - ECS', 52.0, NULL, false, NULL),
  ('cable-bms-2', 'Battery', '4 - Fox spare parts', NULL, 'Cable - BMS', 55.0, NULL, false, NULL),
  ('enclosure-esq', 'Battery', '4 - Fox spare parts', NULL, 'enclosure esq', 18.0, NULL, false, NULL),
  ('enclosure-drt', 'Battery', '4 - Fox spare parts', NULL, 'enclosure Drt', 18.0, NULL, false, NULL),
  ('isolamento-laterial-esq', 'Battery', '4 - Fox spare parts', NULL, 'Isolamento Laterial Esq', 26.0, NULL, false, NULL),
  ('isolamento-laterial-drt', 'Battery', '4 - Fox spare parts', NULL, 'Isolamento Laterial Drt', 7.0, NULL, false, NULL),
  ('isolamento-laterial-10s', 'Battery', '4 - Fox spare parts', NULL, 'Isolamento Laterial 10S', 4.0, NULL, false, NULL),
  ('handle-not-ok', 'Battery', '4 - Fox spare parts', NULL, 'Handle (NOT OK)', 6.0, NULL, false, NULL),
  ('handle', 'Battery', '4 - Fox spare parts', NULL, 'Handle', 15.0, NULL, false, NULL),
  ('vedante-inferior', 'Battery', '4 - Fox spare parts', NULL, 'Vedante inferior', 415.0, NULL, false, NULL),
  ('adesivo-termico', 'Battery', '4 - Fox spare parts', NULL, 'Adesivo termico', 163.0, NULL, false, NULL),
  ('chapa-de-ligacao-18x16x8mm', 'Battery', '4 - Fox spare parts', NULL, 'chapa de ligação (18x16x8mm)', 20.0, NULL, false, NULL),
  ('isolamento-lateral-20s', 'Battery', '4 - Fox spare parts', NULL, 'isolamento lateral 20S', 423.0, NULL, false, NULL),
  ('chapa-ligacao-18x26x8mm', 'Battery', '4 - Fox spare parts', NULL, 'chapa ligacao (18x26x8mm)', 25.0, NULL, false, NULL),
  ('bottom-cover-assembled', 'Battery', '4 - Fox spare parts', NULL, 'Bottom cover assembled', 18.0, NULL, false, NULL),
  ('routers-antigos', 'Station', '1 - On hold', NULL, 'Routers antigos', 4.0, NULL, false, NULL),
  ('vedante-inferior-2', 'Battery', '4 - Battery', NULL, 'vedante inferior', 22.0, NULL, false, NULL),
  ('suporte-pollen', 'Battery', '4 - Battery', NULL, 'Suporte Pollen', 10.0, NULL, false, NULL),
  ('chapa-de-ligacao-18x16x18mm', 'Battery', '4 - Battery', NULL, 'chapa de ligação (18x16x18mm)', 20.0, NULL, false, NULL),
  ('suporte-potencia', 'Battery', '4 - Battery', NULL, 'Suporte potencia', 73.0, NULL, false, NULL),
  ('bottom-wall-mounting-plate', 'Station', '2.1 - Dune STATION', 'STN-D-PRT-073', 'BOTTOM WALL MOUNTING PLATE', 40.0, NULL, false, NULL),
  ('top-wall-mounting-plate', 'Station', '2.1 - Dune STATION', 'STN-D-WLD-009', 'TOP WALL MOUNTING PLATE', 40.0, NULL, false, NULL),
  ('ms413y-zinc-alloy-industrial-cabinet-cam', 'Station', '2.1 - Dune STATION', 'MS413Y', 'MS413Y - Zinc Alloy Industrial Cabinet Cam Lock', 44.0, NULL, false, NULL),
  ('m12-x-1-5-cable-gland', 'Station', '3.1 - Dune electrical area', 'RITTAL-2411601', 'M12 x 1.5 - CABLE GLAND', 31.0, NULL, false, NULL),
  ('m32-cable-gland', 'Station', '3.1 - Dune electrical area', '1SNF100023R0000', 'M32 CABLE GLAND', 14.0, NULL, false, NULL),
  ('3-phase-connector', 'Station', '3.1 - Dune electrical area', '100017', '3-Phase Connector', 1.0, NULL, false, NULL),
  ('cabos-ventiladores-old-electrical-area', 'Station', '1 - On hold', 'A2-20', 'Cabos ventiladores old electrical area', 9.0, NULL, false, NULL),
  ('schaffner-line-filter', 'Station', '1 - On hold', 'FN3256H-36-33', 'Schaffner line filter', 5.0, NULL, false, NULL),
  ('door-panel', 'Station', '2.1 - Dune STATION', 'STN-D-WLD-003', 'DOOR PANEL', 1.0, NULL, false, NULL),
  ('lock-cover', 'Station', '2.1 - Dune STATION', 'STN-D-WLD-005', 'LOCK COVER', 5.0, NULL, false, NULL),
  ('rear-3ph-cover', 'Station', '2.1 - Dune STATION', 'STN-D-PRT-065', 'REAR 3PH COVER', 1.0, NULL, false, NULL),
  ('pollen-logo', 'Station', '2.1 - Dune STATION', NULL, 'Pollen Logo', 1.0, NULL, false, NULL),
  ('lighting-fuse-2a-10-3mm-x-38mm', 'Station', '3.1 - Dune electrical area', NULL, 'lighting fuse, 2A, 10.3mm x 38mm', 10.0, NULL, false, NULL),
  ('neutral-din-conector', 'Station', '3.1 - Dune electrical area', 'BMQM108007C', 'Neutral Din Conector', 3.0, NULL, false, NULL),
  ('flexible-thin-cable-brown', 'Station', '3.1 - Dune electrical area', NULL, 'Flexible Thin Cable Brown', 100.0, 'm', false, NULL),
  ('circuit-breaker-for-fan-light-and-router', 'Station', '3.1 - Dune electrical area', 'UEB6-63L/C061', 'Circuit Breaker for Fan, Light and Router', 6.0, NULL, false, NULL),
  ('conectores-de-cabo-bm00510', 'Station', '3.1 - Dune electrical area', 'BM00510', 'Conectores de cabo BM00510', 400.0, NULL, false, NULL),
  ('conectores-de-cabo-bm00561', 'Station', '3.1 - Dune electrical area', 'BM00561', 'Conectores de cabo BM00561', 75.0, NULL, false, NULL),
  ('conectores-de-cabo-bm00702', 'Station', '3.1 - Dune electrical area', 'BM00702', 'Conectores de cabo BM00702', 200.0, NULL, false, NULL),
  ('water-detector', 'Station', '3.1 - Dune electrical area', 'BAF147B002', 'Water Detector', 3.0, NULL, false, NULL)
on conflict (id) do update set
  produto = excluded.produto,
  categoria = excluded.categoria,
  ref = excluded.ref,
  nome = excluded.nome,
  qty = excluded.qty,
  unit = excluded.unit,
  qty_approx = excluded.qty_approx,
  qty_note = excluded.qty_note;
