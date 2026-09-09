-- =====================================================================================
-- 05_reglas.sql — Reglas inductivas con soporte, confianza y lift
--
-- Misma consulta que la seccion 4 de 02_cubo.sql, en archivo aparte para que el
-- backend la ejecute tal cual y la landing no pueda mostrar numeros distintos de
-- los que devuelve el entregable. La sirve GET /api/reglas.
--
--   soporte   = jornadas que cumplen antecedente Y consecuente / jornadas totales
--   confianza = jornadas que cumplen las dos / jornadas del antecedente
--   lift      = confianza / probabilidad base del consecuente
--               lift = 1 significa que el antecedente no aporta NADA
-- =====================================================================================

set nocount on;

;with Base as (
    select
        Total     = cast(count(*) as decimal(18,4)),
        Ausencias = cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano
),
Antecedentes as (
    select Regla = 'RI-1  SI Turno = Noche',
           Orden = 1,
           Ant   = cast(count(*) as decimal(18,4)),
           AntYCons = cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano where Turno = 'Noche'
    union all
    select 'RI-2  SI Contrato = Temporario Y antiguedad < 6 meses', 2,
           cast(count(*) as decimal(18,4)),
           cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano
    where TipoContrato = 'Temporario' and TramoAntiguedad = '1. Menos de 6 meses'
    union all
    select 'RI-3  SI Sucursal = San Justo Y mes >= 2025-06', 3,
           cast(count(*) as decimal(18,4)),
           cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano
    where NombreSucursal = 'San Justo' and Fecha >= '2025-06-01'
    union all
    -- CONTROL NEGATIVO: no se sembro ninguna relacion aca.
    -- Si diera lift alto, el metodo estaria mal calibrado y no se podria
    -- creer en ninguna de las tres reglas de arriba.
    select 'CN-1  (control) SI Zona = CABA', 4,
           cast(count(*) as decimal(18,4)),
           cast(sum(cast(EsAusente as int)) as decimal(18,4))
    from vw_Cubo_CapitalHumano where Zona = 'CABA'
)
select
    a.Regla,
    a.Orden,
    Jornadas      = cast(a.Ant as int),
    Coincidencias = cast(a.AntYCons as int),
    Soporte       = cast(100.0 * a.AntYCons / b.Total as decimal(6,2)),
    Confianza     = cast(100.0 * a.AntYCons / a.Ant   as decimal(6,2)),
    Base          = cast(100.0 * b.Ausencias / b.Total as decimal(6,2)),
    Lift          = cast((a.AntYCons / a.Ant) / (b.Ausencias / b.Total) as decimal(6,3))
from Antecedentes a cross join Base b
order by a.Orden;
