// =====================================================================================
// consultas.js — diccionario de consultas permitidas
//
// El navegador manda NOMBRES de dimensiones, nunca SQL. Este archivo es el unico
// lugar donde un nombre se convierte en un fragmento de consulta, y todo valor de
// filtro viaja como parametro. Cualquier nombre fuera del diccionario se rechaza
// con 400. Es lo que evita que /api/olap sea un agujero de inyeccion SQL.
// =====================================================================================

'use strict';

// nombre publico -> expresion SQL sobre vw_Cubo_CapitalHumano
const DIMENSIONES = {
  turno:        { sql: 'c.Turno',          alias: 'Turno' },
  zona:         { sql: 'c.Zona',           alias: 'Zona' },
  sucursal:     { sql: 'c.NombreSucursal', alias: 'Sucursal' },
  contrato:     { sql: 'c.TipoContrato',   alias: 'Contrato' },
  antiguedad:   { sql: 'c.TramoAntiguedad',alias: 'Antiguedad' },
  tipoAusencia: { sql: 'c.TipoAusencia',   alias: 'TipoAusencia' },
  puesto:       { sql: 'c.Puesto',         alias: 'Puesto' },
  empleado:     { sql: 'c.NombreEmpleado', alias: 'Empleado' },
  anio:         { sql: 'c.Anio',           alias: 'Anio' },
  mes:          { sql: "cast(c.Anio as varchar(4)) + '-' + right('0' + cast(c.MesNumero as varchar(2)), 2)", alias: 'Mes' },
  franquicia:   { sql: "case when c.EsFranquicia = 1 then 'Franquicia' else 'Propia' end", alias: 'Tipo' },
  finDeSemana:  { sql: "case when c.EsFinDeSemana = 1 then 'Fin de semana' else 'Dia de semana' end", alias: 'Periodo' }
};

// nombre publico -> columna filtrable y tipo del parametro
const FILTROS = {
  sucursal:  { sql: 'c.NombreSucursal', tipo: 'varchar' },
  zona:      { sql: 'c.Zona',           tipo: 'varchar' },
  turno:     { sql: 'c.Turno',          tipo: 'varchar' },
  contrato:  { sql: 'c.TipoContrato',   tipo: 'varchar' },
  anio:      { sql: 'c.Anio',           tipo: 'int' },
  desdeMes:  { sql: 'c.Fecha',          tipo: 'date', op: '>=' },
  hastaMes:  { sql: 'c.Fecha',          tipo: 'date', op: '<=' }
};

// Las medidas son fijas: el cliente no elige agregaciones.
// Tasa y PctHorasExtra son NO ADITIVAS: se recalculan como cociente de sumas
// en cada nivel de agregacion, nunca como promedio de promedios.
const MEDIDAS = `
    Jornadas      = count(*),
    Ausencias     = sum(cast(c.EsAusente as int)),
    Tasa          = cast(100.0 * sum(cast(c.EsAusente as int)) / count(*) as decimal(5,2)),
    Horas         = sum(c.HorasTrabajadas),
    Extra         = sum(c.HorasExtra),
    PctHorasExtra = cast(100.0 * sum(c.HorasExtra) / nullif(sum(c.HorasTrabajadas), 0) as decimal(6,2)),
    Empleados     = count(distinct c.IdEmpleado),
    ExtraPorEmpleado = cast(sum(c.HorasExtra) / nullif(count(distinct c.IdEmpleado), 0) as decimal(8,2))`;

/**
 * Arma la consulta OLAP a partir de nombres validados.
 * @returns {{sql:string, params:Array<{nombre,tipo,valor}>, cols:string[]}}
 * @throws  {Error} con .status = 400 si algun nombre no esta en el diccionario
 */
function construirOlap({ dims = [], where = {}, orden = null, limite = 200 }) {
  if (!Array.isArray(dims)) {
    const e = new Error('dims tiene que ser una lista'); e.status = 400; throw e;
  }
  if (dims.length > 3) {
    const e = new Error('Maximo tres dimensiones por consulta'); e.status = 400; throw e;
  }

  const cols = [];
  const exprs = [];
  for (const d of dims) {
    const def = DIMENSIONES[d];
    if (!def) {
      const e = new Error(`Dimension no permitida: ${d}`); e.status = 400; throw e;
    }
    exprs.push(def.sql);
    cols.push(def.alias);
  }

  const params = [];
  const condiciones = [];
  let i = 0;
  for (const [k, v] of Object.entries(where)) {
    if (v === null || v === undefined || v === '') continue;
    const def = FILTROS[k];
    if (!def) {
      const e = new Error(`Filtro no permitido: ${k}`); e.status = 400; throw e;
    }
    const nombre = `p${i++}`;
    condiciones.push(`${def.sql} ${def.op || '='} @${nombre}`);
    params.push({ nombre, tipo: def.tipo, valor: v });
  }

  const lim = Math.min(Math.max(parseInt(limite, 10) || 200, 1), 500);

  // Roll-up al total: sin dimensiones no hay group by, una sola fila
  if (exprs.length === 0) {
    const sqlTotal =
`select${MEDIDAS}
from vw_Cubo_CapitalHumano c${condiciones.length ? '\nwhere ' + condiciones.join('\n  and ') : ''};`;
    return { sql: sqlTotal, params, cols: ['Jornadas', 'Ausencias', 'Tasa', 'Horas', 'Extra', 'PctHorasExtra', 'Empleados', 'ExtraPorEmpleado'] };
  }

  const seleccion = exprs.map((e, n) => `${e} as [${cols[n]}]`).join(',\n    ');
  const ordenSql = orden && DIMENSIONES[orden]
    ? `[${DIMENSIONES[orden].alias}]`
    : (dims.length === 1 ? 'Tasa desc' : `[${cols[0]}], [${cols[1] || cols[0]}]`);

  const sql =
`select top (${lim})
    ${seleccion},${MEDIDAS}
from vw_Cubo_CapitalHumano c${condiciones.length ? '\nwhere ' + condiciones.join('\n  and ') : ''}
group by ${exprs.join(', ')}
order by ${ordenSql};`;

  return { sql, params, cols: cols.concat(['Jornadas', 'Ausencias', 'Tasa', 'Horas', 'Extra', 'PctHorasExtra', 'Empleados', 'ExtraPorEmpleado']) };
}

module.exports = { DIMENSIONES, FILTROS, construirOlap };
