// =====================================================================================
// server.js — backend de la landing MiniRed Capital Humano
//
//   GET  /api/salud                  ping, dice si SQL Server responde
//   GET  /api/cubo                   corre 03_payload.sql y devuelve el cubo agregado
//   GET  /api/reglas                 corre 05_reglas.sql: soporte, confianza y lift
//   POST /api/olap                   MOTOR DEL JUEGO: una operacion OLAP -> SQL real
//   POST /api/partida                abre una partida
//   POST /api/partida/:id/movimiento registra un movimiento
//   POST /api/partida/:id/acusacion  cierra la partida con veredicto y XP
//   GET  /api/ranking                tabla de posiciones
//
// Sirve tambien los estaticos de ../ (index.html y datos.js), asi que con
// `node server.js` levanta todo junto en un solo puerto.
// =====================================================================================

'use strict';
const path = require('path');
const fs = require('fs');
const express = require('express');
const { consultar, sql } = require('./db');
const { construirOlap } = require('./consultas');

const app = express();
const PUERTO = parseInt(process.env.PORT || '3000', 10);
const RAIZ_ESTATICOS = path.resolve(__dirname, '..');
const RUTA_PAYLOAD = path.resolve(__dirname, '..', '..', 'sql', '03_payload.sql');

app.use(express.json({ limit: '256kb' }));
app.use((req, _res, next) => { console.log(`${req.method} ${req.url}`); next(); });

// --------------------------------------------------------------------------- salud
app.get('/api/salud', async (_req, res) => {
  try {
    const r = await consultar('select Jornadas = count(*) from Fact_Asistencia');
    res.json({ ok: true, jornadas: r.recordset[0].Jornadas });
  } catch (e) {
    res.status(503).json({ ok: false, error: e.message });
  }
});

// ---------------------------------------------------------------------------- cubo
// Reusa el mismo archivo .sql que se entrega, para que la landing y el entregable
// no puedan divergir: una sola fuente de verdad.
let cacheCubo = null, cacheCuboAt = 0;
app.get('/api/cubo', async (_req, res) => {
  try {
    if (cacheCubo && Date.now() - cacheCuboAt < 60000) return res.json(cacheCubo);
    const texto = fs.readFileSync(RUTA_PAYLOAD, 'utf8');
    const r = await consultar(texto);
    const fila = r.recordset[0];
    const bruto = fila[Object.keys(fila)[0]];
    cacheCubo = typeof bruto === 'string' ? JSON.parse(bruto) : bruto;
    cacheCuboAt = Date.now();
    res.json(cacheCubo);
  } catch (e) {
    console.error('[cubo]', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ---------------------------------------------------------------------------- olap
// Cada movimiento del jugador entra por aca y sale como una consulta real al cubo.
// Devuelve el SQL ejecutado para poder mostrarlo en pantalla.
app.post('/api/olap', async (req, res) => {
  try {
    const { dims, where, orden, limite } = req.body || {};
    const { sql: texto, params, cols } = construirOlap({ dims, where, orden, limite });
    const t0 = Date.now();
    const r = await consultar(texto, params);
    res.json({
      sql: texto,
      cols,
      filas: r.recordset,
      ms: Date.now() - t0
    });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

// ------------------------------------------------------------------------- partida
app.post('/api/partida', async (req, res) => {
  try {
    const { detective, idCaso, nombreCaso, movimientos } = req.body || {};
    const r = await consultar(
      `insert into Juego_Partida (Detective, IdCaso, NombreCaso, MovimientosPermitidos)
       output inserted.IdPartida
       values (@detective, @idCaso, @nombreCaso, @movs)`,
      [
        { nombre: 'detective',  tipo: 'varchar', valor: String(detective || 'Anonimo').slice(0, 60) },
        { nombre: 'idCaso',     tipo: 'int',     valor: parseInt(idCaso, 10) || 0 },
        { nombre: 'nombreCaso', tipo: 'varchar', valor: String(nombreCaso || '').slice(0, 80) },
        { nombre: 'movs',       tipo: 'int',     valor: parseInt(movimientos, 10) || 0 }
      ]
    );
    res.json({ idPartida: r.recordset[0].IdPartida });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/partida/:id/movimiento', async (req, res) => {
  try {
    const { orden, operacion, dimensiones, filtros, filas } = req.body || {};
    await consultar(
      `insert into Juego_Movimiento (IdPartida, Orden, Operacion, Dimensiones, Filtros, FilasDevueltas)
       values (@id, @orden, @op, @dims, @filtros, @filas)`,
      [
        { nombre: 'id',      tipo: 'int',     valor: parseInt(req.params.id, 10) },
        { nombre: 'orden',   tipo: 'int',     valor: parseInt(orden, 10) || 0 },
        { nombre: 'op',      tipo: 'varchar', valor: String(operacion || '').slice(0, 30) },
        { nombre: 'dims',    tipo: 'varchar', valor: String(dimensiones || '').slice(0, 200) },
        { nombre: 'filtros', tipo: 'varchar', valor: String(filtros || '').slice(0, 400) },
        { nombre: 'filas',   tipo: 'int',     valor: parseInt(filas, 10) || 0 }
      ]
    );
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/partida/:id/acusacion', async (req, res) => {
  try {
    const { sujeto, causa, pistas, acierto, xp, detective } = req.body || {};
    const p = [
      { nombre: 'id',      tipo: 'int',     valor: parseInt(req.params.id, 10) },
      { nombre: 'sujeto',  tipo: 'varchar', valor: String(sujeto || '').slice(0, 40) },
      { nombre: 'causa',   tipo: 'varchar', valor: String(causa || '').slice(0, 40) },
      { nombre: 'pistas',  tipo: 'varchar', valor: String(pistas || '').slice(0, 400) },
      { nombre: 'acierto', tipo: 'bit',     valor: acierto ? 1 : 0 },
      { nombre: 'xp',      tipo: 'int',     valor: parseInt(xp, 10) || 0 },
      { nombre: 'det',     tipo: 'varchar', valor: String(detective || 'Anonimo').slice(0, 60) }
    ];
    await consultar(
      `insert into Juego_Acusacion (IdPartida, Sujeto, Causa, PistasCitadas, Acierto, XP)
       values (@id, @sujeto, @causa, @pistas, @acierto, @xp);
       update Juego_Partida
          set Resuelto = @acierto, XP = @xp, Detective = @det, FechaCierre = sysdatetime()
        where IdPartida = @id;`,
      p
    );
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// -------------------------------------------------------------------------- reglas
// Corre el mismo SQL que se entrega (05_reglas.sql, identico a la seccion 4 de
// 02_cubo.sql), asi la tabla de la landing no puede mostrar numeros distintos
// de los que da el entregable.
const RUTA_REGLAS = path.resolve(__dirname, '..', '..', 'sql', '05_reglas.sql');
app.get('/api/reglas', async (_req, res) => {
  try {
    const texto = fs.readFileSync(RUTA_REGLAS, 'utf8');
    const t0 = Date.now();
    const r = await consultar(texto);
    res.json({ sql: texto, filas: r.recordset, ms: Date.now() - t0 });
  } catch (e) {
    console.error('[reglas]', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ------------------------------------------------------------------------- ranking
app.get('/api/ranking', async (_req, res) => {
  try {
    const r = await consultar('select * from vw_Juego_Ranking');
    res.json(r.recordset);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ------------------------------------------------------------------------ estaticos
app.use(express.static(RAIZ_ESTATICOS, { extensions: ['html'] }));

app.listen(PUERTO, '0.0.0.0', () => {
  console.log(`MiniRed Capital Humano escuchando en http://0.0.0.0:${PUERTO}`);
  console.log(`Estaticos desde ${RAIZ_ESTATICOS}`);
  consultar('select 1 as ok')
    .then(() => console.log('SQL Server: conectado'))
    .catch((e) => console.error('SQL Server: SIN CONEXION ->', e.message));
});
