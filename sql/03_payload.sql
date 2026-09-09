-- =====================================================================================
-- 03_payload.sql — Export del cubo en JSON para la landing
--
-- Correr con:
--   sqlcmd -S <ip>,<puerto> -U sa -P "<clave>" -C -d MiniRed_DW ^
--          -y 0 -h -1 -W -i "tp\sql\03_payload.sql" -o "tp\landing\payload.json"
--
--   -y 0   sin limite de ancho de columna (por defecto corta en 256 caracteres)
--   -h -1  sin encabezados
--   -W     sin relleno de espacios
--
-- El archivo resultante es el JSON pelado, listo para pegar en datos.js.
-- =====================================================================================

set nocount on;

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
         from vw_Cubo_CapitalHumano c group by c.Turno for json path)) as fueraDeMuestra

    for json path, without_array_wrapper
) as PayloadJSON;
