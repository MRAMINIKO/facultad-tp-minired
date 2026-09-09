-- =====================================================================================
-- 01_rrhh.sql — Data mart de Recursos Humanos sobre MiniRed_DW
-- TP Unidad 3 · Perspectiva Capital Humano x Expansion Territorial
--
-- QUE HACE
--   Agrega tres tablas nuevas a la base existente, sin tocar una sola linea del
--   script de la catedra:
--       Dim_Empleado       dimension de personal, ligada a Dim_Sucursal
--       Fact_Asistencia    grano: un empleado, un dia programado, en una sucursal
--       Fact_Liquidacion   grano: un empleado, un mes
--   Dim_Tiempo y Dim_Sucursal quedan como dimensiones CONFORMADAS: las comparten
--   Fact_Ventas (de la catedra) y los dos hechos nuevos. Eso convierte el modelo
--   en una CONSTELACION y habilita el drill across.
--
-- REQUISITO
--   Haber corrido antes MiniRed_Crear_Base.sql completo.
--
-- SUPUESTOS SEMBRADOS EN EL GENERADOR (declarados a proposito, ver docs)
--   R1  El turno noche tiene mas del doble de ausentismo que manana/tarde,
--       y la brecha se agranda los fines de semana.
--   R2  El personal Temporario con menos de 6 meses concentra las faltas.
--   R3  Las franquicias operan con menos dotacion y compensan con horas extra,
--       asi que su costo por hora efectivo es mayor con el mismo basico.
--   R4  En San Justo, entre junio y agosto de 2025, el ausentismo se dispara
--       antes del cierre del 31-08-2025. (Se apoya en el unico patron real que
--       trae la base de la catedra.)
--   CONTROL NEGATIVO: no se sembro ninguna relacion con medio de pago ni con
--   rubro de producto. Si el analisis "encuentra" algo ahi, esta mal calibrado.
--
-- El azar es DETERMINISTICO: se usa checksum() sobre las claves, no newid().
-- Correr el script dos veces da exactamente el mismo dato.
-- Carga por conjuntos, sin WHILE: tarda segundos.
-- =====================================================================================

use MiniRed_DW;
go

-- ---------------------------------------------------------------------
-- 0. Limpieza, para poder correr el script las veces que haga falta
-- ---------------------------------------------------------------------
if object_id('Fact_Liquidacion', 'U') is not null drop table Fact_Liquidacion;
if object_id('Fact_Asistencia',  'U') is not null drop table Fact_Asistencia;
if object_id('Dim_Empleado',     'U') is not null drop table Dim_Empleado;
go


-- =====================================================================================
-- 1. DIM_EMPLEADO
--    Plana a proposito: turno, contrato y horas nominales son atributos, no
--    dimensiones aparte. IdCajero es el PUENTE hacia Fact_Ventas.
-- =====================================================================================
create table Dim_Empleado (
    IdEmpleado      int identity(1,1) primary key,
    Legajo          varchar(10)  not null,          -- clave de negocio
    NombreEmpleado  varchar(100) not null,
    Puesto          varchar(40)  not null,          -- Cajero / Encargado de turno
    TipoContrato    varchar(20)  not null,          -- Efectivo / Part-time / Temporario
    IdSucursal      int          not null foreign key references Dim_Sucursal(IdSucursal),
    Turno           varchar(20)  not null,          -- Manana / Tarde / Noche
    HorasNominales  decimal(4,2) not null,
    SueldoBasico    decimal(12,2) not null,
    IdCajero        int          null foreign key references Dim_Cajero(IdCajero),
    FechaIngreso    date         not null
);
go

-- 64 nombres armados por producto cartesiano de dos listas chicas
declare @Nombres table (rn int, Nombre varchar(100));

insert into @Nombres (rn, Nombre)
select row_number() over (order by n.orden, a.orden),
       n.nombre + ' ' + a.apellido
from (values (1,'Lucia'),(2,'Martin'),(3,'Sofia'),(4,'Diego'),
             (5,'Camila'),(6,'Pablo'),(7,'Valentina'),(8,'Federico')) n(orden, nombre)
cross join
     (values (1,'Gomez'),(2,'Fernandez'),(3,'Sosa'),(4,'Torres'),
             (5,'Molina'),(6,'Diaz'),(7,'Romero'),(8,'Acosta')) a(orden, apellido);

-- Plantilla de dotacion por sucursal.
-- R3: las franquicias NO llevan encargado de turno -> 3 personas en vez de 4.
;with Plantilla as (
    select * from (values
        ('Cajero',             'Manana', 8.00, 1, 1),
        ('Cajero',             'Tarde',  8.00, 1, 2),
        ('Cajero',             'Noche',  8.00, 1, 3),
        ('Encargado de turno', 'Manana', 9.00, 0, 4)
    ) p(Puesto, Turno, HorasNominales, EsCaja, Orden)
),
Dotacion as (
    select
        s.IdSucursal,
        s.FechaApertura,
        p.Puesto, p.Turno, p.HorasNominales, p.EsCaja,
        rn = row_number() over (order by s.IdSucursal, p.Orden)
    from Dim_Sucursal s
    cross join Plantilla p
    where not (s.EsFranquicia = 1 and p.Puesto = 'Encargado de turno')
)
insert into Dim_Empleado
    (Legajo, NombreEmpleado, Puesto, TipoContrato, IdSucursal, Turno,
     HorasNominales, SueldoBasico, IdCajero, FechaIngreso)
select
    'L-' + right('0000' + cast(d.rn as varchar(4)), 4),
    n.Nombre,
    d.Puesto,
    -- R2: un tercio del personal de caja es Temporario, el resto Efectivo
    case when d.Puesto = 'Encargado de turno' then 'Efectivo'
         when d.rn % 3 = 0                    then 'Temporario'
         when d.rn % 7 = 0                    then 'Part-time'
         else 'Efectivo' end,
    d.IdSucursal,
    d.Turno,
    d.HorasNominales,
    -- basico por puesto y turno (adicional nocturno). Mismo esquema para
    -- franquicias y locales propios: la diferencia de costo la hacen las extras.
    case when d.Puesto = 'Encargado de turno' then 1150000.00
         when d.Turno  = 'Noche'              then  980000.00
         else                                       890000.00 end,
    -- PUENTE: solo el personal de caja se mapea a un cajero del mismo turno
    case when d.EsCaja = 1 then (
        select top 1 c.IdCajero
        from Dim_Cajero c
        where c.Turno = d.Turno
        order by (c.IdCajero + d.rn) % 4, c.IdCajero
    ) end,
    -- antiguedad escalonada: entre 2018 y mediados de 2025
    dateadd(day, -((d.rn * 137) % 2600), '2025-07-01')
from Dotacion d
join @Nombres n on n.rn = d.rn;
go

-- La fecha de ingreso nunca puede ser anterior a la apertura del local
update e
set    e.FechaIngreso = s.FechaApertura
from   Dim_Empleado e
join   Dim_Sucursal s on s.IdSucursal = e.IdSucursal
where  e.FechaIngreso < s.FechaApertura;
go


-- =====================================================================================
-- 2. FACT_ASISTENCIA
--    Grano: un empleado, un dia programado, en una sucursal.
--    Una fila por jornada, este presente o ausente.
-- =====================================================================================
create table Fact_Asistencia (
    IdAsistencia    bigint identity(1,1) primary key,
    IdTiempo        int not null foreign key references Dim_Tiempo(IdTiempo),
    IdEmpleado      int not null foreign key references Dim_Empleado(IdEmpleado),
    IdSucursal      int not null foreign key references Dim_Sucursal(IdSucursal),
    TipoAusencia    varchar(30)  not null,   -- 'Presente' es el miembro "no aplica"
    EsAusente       bit          not null,   -- aditiva como conteo
    HorasTrabajadas decimal(4,2) not null,   -- aditiva
    HorasExtra      decimal(4,2) not null,   -- aditiva
    MinutosTardanza int          not null    -- aditiva
);
go

;with Jornadas as (
    select
        t.IdTiempo, t.Fecha, t.EsFinDeSemana,
        e.IdEmpleado, e.IdSucursal, e.Turno, e.TipoContrato, e.HorasNominales,
        e.FechaIngreso,
        s.NombreSucursal, s.EsFranquicia,
        -- pseudo-azar determinista: misma clave -> mismo valor, siempre
        r = abs(checksum(t.IdTiempo * 7919 + e.IdEmpleado * 104729) % 1000)
    from Dim_Empleado e
    join Dim_Sucursal s on s.IdSucursal = e.IdSucursal
    join Dim_Tiempo   t on t.Fecha >= e.FechaIngreso
                       and t.Fecha >= s.FechaApertura
                       and (s.FechaCierre is null or t.Fecha <= s.FechaCierre)
    -- franco rotativo: cada empleado descansa un dia distinto de la semana
    where (datediff(day, '19000101', t.Fecha) + e.IdEmpleado) % 7 <> 0
),
ConProbabilidad as (
    select j.*,
           prob =
                 55                                                                    -- base 5,5 %
               + case when j.Turno = 'Noche' then 80 else 0 end                         -- R1
               + case when j.Turno = 'Noche' and j.EsFinDeSemana = 1 then 45 else 0 end -- R1 (finde)
               + case when j.TipoContrato = 'Temporario'
                       and datediff(day, j.FechaIngreso, j.Fecha) < 180 then 65 else 0 end -- R2
               + case when j.NombreSucursal = 'San Justo'
                       and j.Fecha >= '2025-06-01' then 155 else 0 end                  -- R4
    from Jornadas j
),
Resuelto as (
    select c.*, EsAusente = case when c.r < c.prob then 1 else 0 end
    from ConProbabilidad c
)
insert into Fact_Asistencia
    (IdTiempo, IdEmpleado, IdSucursal, TipoAusencia, EsAusente,
     HorasTrabajadas, HorasExtra, MinutosTardanza)
select
    r.IdTiempo, r.IdEmpleado, r.IdSucursal,
    case when r.EsAusente = 0        then 'Presente'
         when (r.r % 10) < 4         then 'Enfermedad'
         when (r.r % 10) < 7         then 'Licencia ordinaria'
         else                             'Falta injustificada' end,
    r.EsAusente,
    case when r.EsAusente = 1 then 0.00 else r.HorasNominales end,
    -- R3: en las franquicias se hacen muchas mas horas extra
    case when r.EsAusente = 1 then 0.00
         when (r.r % 100) < (case when r.EsFranquicia = 1 then 38 else 14 end)
              then cast(((r.r % 5) + 1) * 0.5 as decimal(4,2))
         else 0.00 end,
    case when r.EsAusente = 1 then 0
         when (r.r % 97) < 11 then (r.r % 25) + 1
         else 0 end
from Resuelto r;
go


-- =====================================================================================
-- 3. FACT_LIQUIDACION
--    Grano: un empleado, un mes. Se ancla al ultimo dia del mes.
--    Derivada de Fact_Asistencia, asi los numeros cierran entre los dos hechos.
-- =====================================================================================
create table Fact_Liquidacion (
    IdLiquidacion      bigint identity(1,1) primary key,
    IdTiempo           int not null foreign key references Dim_Tiempo(IdTiempo),
    IdEmpleado         int not null foreign key references Dim_Empleado(IdEmpleado),
    IdSucursal         int not null foreign key references Dim_Sucursal(IdSucursal),
    SueldoBasico       decimal(12,2) not null,   -- SEMIADITIVA: no se suma en el tiempo
    ImporteHorasExtra  decimal(12,2) not null,   -- aditiva
    DescuentoAusencias decimal(12,2) not null,   -- aditiva
    MontoBruto         decimal(12,2) not null    -- aditiva
);
go

;with Mensual as (
    select
        t.Anio, t.MesNumero,
        a.IdEmpleado, a.IdSucursal,
        Horas       = sum(a.HorasTrabajadas),
        Extras      = sum(a.HorasExtra),
        AusenCobra  = sum(case when a.EsAusente = 1
                                and a.TipoAusencia = 'Falta injustificada'
                               then 1 else 0 end)
    from Fact_Asistencia a
    join Dim_Tiempo t on t.IdTiempo = a.IdTiempo
    group by t.Anio, t.MesNumero, a.IdEmpleado, a.IdSucursal
),
CierreMes as (
    select Anio, MesNumero, IdTiempo = max(IdTiempo)
    from Dim_Tiempo
    group by Anio, MesNumero
)
insert into Fact_Liquidacion
    (IdTiempo, IdEmpleado, IdSucursal, SueldoBasico,
     ImporteHorasExtra, DescuentoAusencias, MontoBruto)
select
    c.IdTiempo,
    m.IdEmpleado,
    m.IdSucursal,
    e.SueldoBasico,
    -- hora extra al 50 %: valor hora = basico / 176
    cast(m.Extras * (e.SueldoBasico / 176.0) * 1.5 as decimal(12,2)),
    cast(m.AusenCobra * (e.SueldoBasico / 176.0) * e.HorasNominales as decimal(12,2)),
    cast(e.SueldoBasico
         + m.Extras * (e.SueldoBasico / 176.0) * 1.5
         - m.AusenCobra * (e.SueldoBasico / 176.0) * e.HorasNominales
         as decimal(12,2))
from Mensual m
join CierreMes c   on c.Anio = m.Anio and c.MesNumero = m.MesNumero
join Dim_Empleado e on e.IdEmpleado = m.IdEmpleado;
go


-- =====================================================================================
-- 4. INDICES (el juego consulta esto en vivo)
-- =====================================================================================
create index IX_Asistencia_Tiempo    on Fact_Asistencia(IdTiempo)   include (EsAusente, HorasTrabajadas, HorasExtra);
create index IX_Asistencia_Empleado  on Fact_Asistencia(IdEmpleado);
create index IX_Asistencia_Sucursal  on Fact_Asistencia(IdSucursal);
go


-- =====================================================================================
-- 5. VERIFICACION — correr esto y mirar que los numeros tengan sentido
-- =====================================================================================
select 'Dim_Empleado' as Tabla, count(*) as Filas from Dim_Empleado
union all select 'Fact_Asistencia',  count(*) from Fact_Asistencia
union all select 'Fact_Liquidacion', count(*) from Fact_Liquidacion;
go

-- R1: el turno noche tiene que dar mas del doble que manana y tarde
select
    e.Turno,
    Jornadas         = count(*),
    Ausencias        = sum(cast(a.EsAusente as int)),
    TasaAusentismo   = cast(100.0 * sum(cast(a.EsAusente as int)) / count(*) as decimal(5,2))
from Fact_Asistencia a
join Dim_Empleado e on e.IdEmpleado = a.IdEmpleado
group by e.Turno
order by TasaAusentismo desc;
go

-- R3: las franquicias tienen que mostrar mas horas extra por empleado
select
    Tipo             = case when s.EsFranquicia = 1 then 'Franquicia' else 'Propia' end,
    Empleados        = count(distinct a.IdEmpleado),
    HorasExtra       = sum(a.HorasExtra),
    ExtrasPorEmpleado= cast(sum(a.HorasExtra) / count(distinct a.IdEmpleado) as decimal(8,2))
from Fact_Asistencia a
join Dim_Sucursal s on s.IdSucursal = a.IdSucursal
group by case when s.EsFranquicia = 1 then 'Franquicia' else 'Propia' end;
go

-- R4: San Justo tiene que trepar en junio, julio y agosto de 2025
select
    t.Anio, t.MesNumero,
    TasaAusentismo = cast(100.0 * sum(cast(a.EsAusente as int)) / count(*) as decimal(5,2))
from Fact_Asistencia a
join Dim_Sucursal s on s.IdSucursal = a.IdSucursal
join Dim_Tiempo   t on t.IdTiempo   = a.IdTiempo
where s.NombreSucursal = 'San Justo' and t.Anio = 2025
group by t.Anio, t.MesNumero
order by t.MesNumero;
go
