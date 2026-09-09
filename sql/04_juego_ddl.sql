-- =====================================================================================
-- 04_juego_ddl.sql — Persistencia del juego Data Detective
--
-- Estas tablas son la razon por la que la landing necesita un backend de verdad:
-- no solo LEE el cubo, tambien ESCRIBE en SQL Server cada partida y cada movimiento
-- OLAP que hace el jugador.
--
-- Efecto secundario interesante: Juego_Movimiento termina siendo un dataset propio,
-- generado por la landing, sobre el que se puede correr el mismo analisis del TP
-- (que caminos de navegacion eligio la gente, cuales llevaron a la acusacion
-- correcta). Ver la seccion 5, que es el cierre del pitch.
--
-- Requiere haber corrido 01_rrhh.sql.
-- =====================================================================================

use MiniRed_DW;
go

if object_id('vw_Juego_Ranking', 'V')   is not null drop view  vw_Juego_Ranking;
if object_id('Juego_Acusacion', 'U')    is not null drop table Juego_Acusacion;
if object_id('Juego_Movimiento', 'U')   is not null drop table Juego_Movimiento;
if object_id('Juego_Partida', 'U')      is not null drop table Juego_Partida;
go

-- Grano: una partida de un detective sobre un caso
create table Juego_Partida (
    IdPartida             bigint identity(1,1) primary key,
    Detective             varchar(60)  not null,
    IdCaso                int          not null,
    NombreCaso            varchar(80)  not null,
    MovimientosPermitidos int          not null,
    FechaInicio           datetime2(0) not null constraint DF_Partida_Inicio default sysdatetime(),
    FechaCierre           datetime2(0) null,
    Resuelto              bit          null,          -- null = partida abierta
    XP                    int          null
);
go

-- Grano: un movimiento OLAP dentro de una partida
create table Juego_Movimiento (
    IdMovimiento bigint identity(1,1) primary key,
    IdPartida    bigint       not null foreign key references Juego_Partida(IdPartida),
    Orden        int          not null,
    Operacion    varchar(30)  not null,   -- Roll-up / Drill-down / Slice / Dice
    Dimensiones  varchar(200) not null,   -- que dimensiones pidio
    Filtros      varchar(400) null,
    FilasDevueltas int        null,
    Momento      datetime2(0) not null constraint DF_Mov_Momento default sysdatetime()
);
go

-- Grano: la acusacion final de una partida
create table Juego_Acusacion (
    IdAcusacion   bigint identity(1,1) primary key,
    IdPartida     bigint       not null foreign key references Juego_Partida(IdPartida),
    Sujeto        varchar(40)  not null,
    Causa         varchar(40)  not null,
    PistasCitadas varchar(400) null,
    Acierto       bit          not null,
    XP            int          not null,
    Momento       datetime2(0) not null constraint DF_Acu_Momento default sysdatetime()
);
go

create index IX_Movimiento_Partida on Juego_Movimiento(IdPartida);
go

create view vw_Juego_Ranking as
select top 100
    p.IdPartida, p.Detective, p.NombreCaso,
    Movimientos = (select count(*) from Juego_Movimiento m where m.IdPartida = p.IdPartida),
    p.XP, p.FechaCierre
from Juego_Partida p
where p.Resuelto = 1
order by p.XP desc, p.FechaCierre asc;
go


-- =====================================================================================
-- 5. MINERIA SOBRE LOS DATOS QUE GENERA LA PROPIA LANDING — cierre del pitch
-- =====================================================================================

-- Que operaciones OLAP eligen los jugadores, y cuales aparecen en las partidas
-- que terminan resueltas. Es aprendizaje inductivo sobre nuestro propio dataset.
select
    m.Operacion,
    m.Dimensiones,
    Veces            = count(*),
    EnPartidasOk     = sum(case when p.Resuelto = 1 then 1 else 0 end),
    TasaExito        = cast(100.0 * sum(case when p.Resuelto = 1 then 1 else 0 end)
                            / nullif(count(*), 0) as decimal(5,2))
from Juego_Movimiento m
join Juego_Partida p on p.IdPartida = m.IdPartida
group by m.Operacion, m.Dimensiones
order by Veces desc;
go

-- En que posicion de la investigacion aparece el movimiento decisivo
select
    p.NombreCaso,
    OrdenPromedio = cast(avg(cast(m.Orden as decimal(5,2))) as decimal(5,2)),
    Partidas      = count(distinct p.IdPartida)
from Juego_Movimiento m
join Juego_Partida p on p.IdPartida = m.IdPartida
where p.Resuelto = 1
group by p.NombreCaso;
go
