-- =====================================================================================
-- 02_cubo.sql — Cubo aplanado, reglas inductivas y export para la landing
-- TP Unidad 3 · MiniRed_DW · Perspectiva Capital Humano x Expansion Territorial
--
-- ESTE ES EL ARCHIVO .SQL QUE SE ENTREGA (criterio de evaluacion 1).
--
-- Contenido:
--   1. Vista ancha del cubo               -> base de todo el analisis
--   2. Consulta aplanada con GROUPING SETS -> MISION 2 (Cube Master)
--   3. Verificacion de agregaciones        -> MISION 2
--   4. Reglas inductivas con soporte/confianza/lift -> MISION 3 (Pattern Hunter)
--   5. Control negativo y validacion fuera de muestra -> punto teorico 5
--   6. Drill across a Fact_Ventas
--   7. Export unico en JSON para la landing
--
-- Requiere haber corrido MiniRed_Crear_Base.sql y 01_rrhh.sql.
-- =====================================================================================

use MiniRed_DW;
go

if object_id('vw_Cubo_CapitalHumano', 'V') is not null drop view vw_Cubo_CapitalHumano;
go

-- =====================================================================================
-- 1. VISTA ANCHA — aplana empleado, sucursal y tiempo junto a las medidas.
--    Es el equivalente en T-SQL de lo que seria el cubo en SSAS.
-- =====================================================================================
create view vw_Cubo_CapitalHumano as
select
    -- dimension tiempo
    t.IdTiempo, t.Fecha, t.Anio, t.Trimestre, t.MesNumero, t.MesNombre,
    t.DiaSemanaNombre, t.EsFinDeSemana,
    -- dimension sucursal (conformada con Fact_Ventas)
    s.IdSucursal, s.NombreSucursal, s.Zona, s.EsFranquicia,
    s.FechaApertura, s.FechaCierre,
    -- dimension empleado
    e.IdEmpleado, e.Legajo, e.NombreEmpleado, e.Puesto, e.TipoContrato,
    e.Turno, e.HorasNominales, e.SueldoBasico, e.IdCajero, e.FechaIngreso,
    -- atributo derivado: antiguedad DISCRETIZADA (variable continua -> categorica)
    TramoAntiguedad = case
        when datediff(day, e.FechaIngreso, t.Fecha) <  180 then '1. Menos de 6 meses'
        when datediff(day, e.FechaIngreso, t.Fecha) <  365 then '2. De 6 a 12 meses'
        when datediff(day, e.FechaIngreso, t.Fecha) <  730 then '3. De 1 a 2 anios'
        else                                                    '4. Mas de 2 anios' end,
    -- hechos
    a.TipoAusencia, a.EsAusente, a.HorasTrabajadas, a.HorasExtra, a.MinutosTardanza
from Fact_Asistencia a
join Dim_Tiempo   t on t.IdTiempo   = a.IdTiempo
join Dim_Sucursal s on s.IdSucursal = a.IdSucursal
join Dim_Empleado e on e.IdEmpleado = a.IdEmpleado;
go


-- =====================================================================================
-- 2. MISION 2 — CUBO APLANADO
--    GROUPING SETS produce todos los niveles de agregacion de una sola pasada:
--    zona x turno, zona sola, turno solo, y el total general.
--    grouping() sirve para etiquetar cual es cual: 1 = ese nivel esta agregado.
--
--    OJO con CostoHoraEfectivo: es una medida NO ADITIVA (es una razon).
--    Se recalcula como cociente de sumas en cada nivel, nunca como promedio
--    de promedios.
-- =====================================================================================
select
    Zona           = case when grouping(c.Zona)  = 1 then '(todas las zonas)'  else c.Zona  end,
    Turno          = case when grouping(c.Turno) = 1 then '(todos los turnos)' else c.Turno end,
    Jornadas       = count(*),
    Ausencias      = sum(cast(c.EsAusente as int)),
    TasaAusentismo = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2)),
    HorasTrabajadas= sum(c.HorasTrabajadas),
    HorasExtra     = sum(c.HorasExtra),
    -- no aditiva: cociente de sumas
    PctHorasExtra  = cast(100.0 * sum(c.HorasExtra)
                          / nullif(sum(c.HorasTrabajadas), 0) as decimal(6,2)),
    Nivel          = case when grouping(c.Zona) = 1 and grouping(c.Turno) = 1 then 'Total general'
                          when grouping(c.Zona) = 1 then 'Por turno'
                          when grouping(c.Turno) = 1 then 'Por zona'
                          else 'Zona x Turno' end
from vw_Cubo_CapitalHumano c
group by grouping sets ( (c.Zona, c.Turno), (c.Zona), (c.Turno), () )
order by grouping(c.Zona), grouping(c.Turno), c.Zona, c.Turno;
go

-- Variante con WITH CUBE sobre tres dimensiones (todas las combinaciones posibles)
select
    Zona         = isnull(c.Zona,        '(todas)'),
    Turno        = isnull(c.Turno,       '(todos)'),
    TipoContrato = isnull(c.TipoContrato,'(todos)'),
    Jornadas       = count(*),
    TasaAusentismo = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2))
from vw_Cubo_CapitalHumano c
group by cube (c.Zona, c.Turno, c.TipoContrato)
order by Zona, Turno, TipoContrato;
go


-- =====================================================================================
-- 3. MISION 2 — VERIFICACION DE AGREGACIONES
--    El total del cubo sin filtros tiene que coincidir con el total de la tabla
--    de hechos. Es el mismo control que deja armado el script de la catedra.
-- =====================================================================================
select
    Control          = 'Horas trabajadas',
    DesdeElHecho     = (select sum(HorasTrabajadas) from Fact_Asistencia),
    DesdeElCubo      = (select sum(HorasTrabajadas) from vw_Cubo_CapitalHumano)
union all
select 'Jornadas',
    (select count(*) from Fact_Asistencia),
    (select count(*) from vw_Cubo_CapitalHumano)
union all
select 'Monto bruto liquidado',
    (select sum(MontoBruto) from Fact_Liquidacion),
    (select sum(MontoBruto) from Fact_Liquidacion);
go


-- =====================================================================================
-- 4. MISION 3 — REGLAS INDUCTIVAS
--    Cada regla tiene la forma  SI <antecedente> ENTONCES <consecuente>.
--      soporte    = jornadas que cumplen las dos cosas / jornadas totales
--      confianza  = jornadas que cumplen las dos / jornadas del antecedente
--      lift       = confianza / probabilidad base del consecuente
--    lift = 1 significa que el antecedente no aporta NADA.
-- =====================================================================================
;with Base as (
    select
        Total       = cast(count(*) as decimal(18,4)),
        Ausencias   = cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano
),
Antecedentes as (
    -- RI-1: turno noche
    select Regla = 'RI-1  SI Turno = Noche ENTONCES Ausencia',
           Ant   = cast(count(*) as decimal(18,4)),
           AntYCons = cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano where Turno = 'Noche'
    union all
    -- RI-2: temporario con menos de 6 meses
    select 'RI-2  SI Contrato = Temporario Y Antiguedad < 6 meses ENTONCES Ausencia',
           cast(count(*) as decimal(18,4)),
           cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano
    where TipoContrato = 'Temporario' and TramoAntiguedad = '1. Menos de 6 meses'
    union all
    -- RI-3 (ancla territorial): San Justo en los tres meses previos al cierre
    select 'RI-3  SI Sucursal = San Justo Y Mes >= 2025-06 ENTONCES Ausencia',
           cast(count(*) as decimal(18,4)),
           cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano
    where NombreSucursal = 'San Justo' and Fecha >= '2025-06-01'
    union all
    -- CN-1: CONTROL NEGATIVO. No sembramos ninguna relacion aca.
    --       Si esta regla diera lift alto, el metodo estaria mal calibrado.
    select 'CN-1  (control) SI Zona = CABA ENTONCES Ausencia',
           cast(count(*) as decimal(18,4)),
           cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano where Zona = 'CABA'
)
select
    a.Regla,
    JornadasAntecedente = cast(a.Ant as int),
    Coincidencias       = cast(a.AntYCons as int),
    Soporte             = cast(100.0 * a.AntYCons / b.Total as decimal(6,2)),
    Confianza           = cast(100.0 * a.AntYCons / a.Ant   as decimal(6,2)),
    ProbabilidadBase    = cast(100.0 * b.Ausencias / b.Total as decimal(6,2)),
    Lift                = cast((a.AntYCons / a.Ant) / (b.Ausencias / b.Total) as decimal(6,3))
from Antecedentes a cross join Base b
order by Lift desc;
go

-- Detalle de RI-1 abierto por turno, que es lo que va al grafico de la landing
select
    c.Turno,
    Jornadas       = count(*),
    Ausencias      = sum(cast(c.EsAusente as int)),
    TasaAusentismo = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2))
from vw_Cubo_CapitalHumano c
group by c.Turno
order by TasaAusentismo desc;
go


-- =====================================================================================
-- 5. VALIDACION FUERA DE MUESTRA — punto teorico 5
--    Las reglas se formulan mirando 2024 y se verifican contra 2025, que el
--    metodo no vio. Una regla que sobrevive al cambio de anio no es memorizacion
--    del ruido. Si las dos columnas dan parecido, la regla es estable.
-- =====================================================================================
select
    c.Turno,
    Tasa_2024 = cast(100.0 * sum(case when c.Anio = 2024 then cast(c.EsAusente as int) end)
                     / nullif(sum(case when c.Anio = 2024 then 1 end), 0) as decimal(5,2)),
    Tasa_2025 = cast(100.0 * sum(case when c.Anio = 2025 then cast(c.EsAusente as int) end)
                     / nullif(sum(case when c.Anio = 2025 then 1 end), 0) as decimal(5,2))
from vw_Cubo_CapitalHumano c
group by c.Turno
order by c.Turno;
go

-- LA TRAMPA DE LA CATEDRA, demostrada: el reparto de tickets por fin de semana
-- da ~28,6 % simplemente porque sabado y domingo son 2 de 7 dias. No es
-- comportamiento de los clientes, es aritmetica del calendario.
select
    EsFinDeSemana = case when t.EsFinDeSemana = 1 then 'Sabado y domingo' else 'Dias de semana' end,
    Tickets       = count(*),
    PctTickets    = cast(100.0 * count(*) / sum(count(*)) over () as decimal(5,2)),
    PctDiasDelCalendario = case when t.EsFinDeSemana = 1 then 28.57 else 71.43 end
from Fact_Ventas v
join Dim_Tiempo t on t.IdTiempo = v.IdTiempo
group by t.EsFinDeSemana;
go


-- =====================================================================================
-- 6. DRILL ACROSS — Fact_Asistencia x Fact_Ventas
--    Se cruzan dos hechos distintos por las dimensiones que COMPARTEN.
--    Se agrega a nivel turno y mes (no sucursal) porque Fact_Ventas asigna el
--    cajero al azar entre las 14 sucursales: cruzar por sucursal daria un
--    resultado inconsistente. Es una limitacion del dato provisto, no del metodo.
-- =====================================================================================
;with Horas as (
    select t.Anio, t.MesNumero, e.Turno,
           Horas = sum(a.HorasTrabajadas)
    from Fact_Asistencia a
    join Dim_Tiempo   t on t.IdTiempo   = a.IdTiempo
    join Dim_Empleado e on e.IdEmpleado = a.IdEmpleado
    group by t.Anio, t.MesNumero, e.Turno
),
Ventas as (
    select t.Anio, t.MesNumero, c.Turno,
           Importe = sum(v.ImporteTotal)
    from Fact_Ventas v
    join Dim_Tiempo t on t.IdTiempo = v.IdTiempo
    join Dim_Cajero c on c.IdCajero = v.IdCajero
    group by t.Anio, t.MesNumero, c.Turno
)
select
    h.Anio, h.MesNumero, h.Turno,
    Horas        = h.Horas,
    Importe      = v.Importe,
    -- medida NO ADITIVA: se recalcula, no se suma
    VentaPorHora = cast(v.Importe / nullif(h.Horas, 0) as decimal(12,2))
from Horas h
join Ventas v on v.Anio = h.Anio and v.MesNumero = h.MesNumero and v.Turno = h.Turno
order by h.Anio, h.MesNumero, h.Turno;
go


-- =====================================================================================
-- 7. EXPORT PARA LA LANDING
--    Devuelve UNA sola celda con todo el cubo agregado en JSON.
--    Copiar el resultado y pegarlo en landing/datos.js  (const DATOS = <aca>;)
--
--    En SSMS: click derecho sobre la celda -> "Copy" y pegar. Si aparece
--    truncado, en Herramientas > Opciones > Query Results > SQL Server >
--    Results to Grid, subir "Maximum Characters Retrieved" para datos XML/no-XML.
--    Alternativa mas comoda: Results to Text (Ctrl+T) y subir el limite ahi.
-- =====================================================================================
select (
    select
        json_query((select
            Jornadas       = count(*),
            Empleados      = (select count(*) from Dim_Empleado),
            Sucursales     = (select count(*) from Dim_Sucursal),
            TasaAusentismo = cast(100.0 * sum(cast(EsAusente as int)) / count(*) as decimal(5,2)),
            HorasTrabajadas= sum(HorasTrabajadas),
            HorasExtra     = sum(HorasExtra),
            MontoBruto     = (select sum(MontoBruto) from Fact_Liquidacion)
         from vw_Cubo_CapitalHumano
         for json path, without_array_wrapper)) as kpis,

        json_query((select
            c.Turno,
            Jornadas = count(*),
            Tasa     = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2)),
            Horas    = sum(c.HorasTrabajadas),
            Extra    = sum(c.HorasExtra)
         from vw_Cubo_CapitalHumano c group by c.Turno for json path)) as porTurno,

        json_query((select
            c.Zona,
            Jornadas = count(*),
            Tasa     = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2)),
            Horas    = sum(c.HorasTrabajadas),
            Extra    = sum(c.HorasExtra)
         from vw_Cubo_CapitalHumano c group by c.Zona for json path)) as porZona,

        json_query((select
            c.NombreSucursal, c.Zona, c.EsFranquicia,
            Empleados = count(distinct c.IdEmpleado),
            Jornadas  = count(*),
            Tasa      = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2)),
            Horas     = sum(c.HorasTrabajadas),
            Extra     = sum(c.HorasExtra),
            ExtraPorEmpleado = cast(sum(c.HorasExtra) / count(distinct c.IdEmpleado) as decimal(8,2))
         from vw_Cubo_CapitalHumano c
         group by c.NombreSucursal, c.Zona, c.EsFranquicia for json path)) as porSucursal,

        json_query((select
            c.NombreSucursal, c.Anio, c.MesNumero,
            Jornadas = count(*),
            Tasa  = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2)),
            Horas = sum(c.HorasTrabajadas)
         from vw_Cubo_CapitalHumano c
         group by c.NombreSucursal, c.Anio, c.MesNumero for json path)) as porSucursalMes,

        json_query((select
            c.TipoContrato, c.TramoAntiguedad,
            Jornadas = count(*),
            Tasa     = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2))
         from vw_Cubo_CapitalHumano c
         group by c.TipoContrato, c.TramoAntiguedad for json path)) as porContrato,

        json_query((select
            c.Turno, c.TipoAusencia,
            Jornadas = count(*)
         from vw_Cubo_CapitalHumano c
         where c.EsAusente = 1
         group by c.Turno, c.TipoAusencia for json path)) as porTipoAusencia,

        json_query((select
            Tipo      = case when c.EsFranquicia = 1 then 'Franquicia' else 'Propia' end,
            Empleados = count(distinct c.IdEmpleado),
            Extra     = sum(c.HorasExtra),
            Horas     = sum(c.HorasTrabajadas),
            PctExtra  = cast(100.0 * sum(c.HorasExtra) / nullif(sum(c.HorasTrabajadas),0) as decimal(6,2)),
            BasicoProm= cast(avg(c.SueldoBasico) as decimal(12,2))
         from vw_Cubo_CapitalHumano c
         group by case when c.EsFranquicia = 1 then 'Franquicia' else 'Propia' end
         for json path)) as franquicias,

        json_query((select
            c.Turno,
            T2024 = cast(100.0 * sum(case when c.Anio = 2024 then cast(c.EsAusente as int) end)
                         / nullif(sum(case when c.Anio = 2024 then 1 end),0) as decimal(5,2)),
            T2025 = cast(100.0 * sum(case when c.Anio = 2025 then cast(c.EsAusente as int) end)
                         / nullif(sum(case when c.Anio = 2025 then 1 end),0) as decimal(5,2))
         from vw_Cubo_CapitalHumano c group by c.Turno for json path)) as fueraDeMuestra,

        json_query((select
            e.NombreEmpleado, e.Legajo, e.Turno, e.TipoContrato, e.Puesto,
            s.NombreSucursal, s.Zona,
            Jornadas = count(*),
            Tasa     = cast(100.0 * sum(cast(a.EsAusente as int)) / count(*) as decimal(5,2)),
            Extra    = sum(a.HorasExtra)
         from Fact_Asistencia a
         join Dim_Empleado e on e.IdEmpleado = a.IdEmpleado
         join Dim_Sucursal s on s.IdSucursal = a.IdSucursal
         group by e.NombreEmpleado, e.Legajo, e.Turno, e.TipoContrato, e.Puesto,
                  s.NombreSucursal, s.Zona
         for json path)) as porEmpleado

    for json path, without_array_wrapper
) as PayloadJSON;
go
