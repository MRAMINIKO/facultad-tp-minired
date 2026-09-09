// =====================================================================================
// db.js — pool de conexiones a SQL Server
// =====================================================================================

'use strict';
const fs = require('fs');
const path = require('path');
const sql = require('mssql');

// ---------------------------------------------------------------------------
// Carga de configuracion SIN dependencias (Node no lee .env por su cuenta).
// Busca, en este orden, y toma el primero que exista de cada uno:
//     backend/.env        lo normal en desarrollo
//     landing/.env
//     tp/.env
//     tp/conn.txt         el mismo archivo que usa sqlcmd, con host/port/user/password
// Las variables de entorno REALES tienen prioridad, asi que en Docker o dokploy
// se configuran ahi y estos archivos se ignoran.
// ---------------------------------------------------------------------------
const ALIAS = {
  host: 'DB_HOST', server: 'DB_HOST', port: 'DB_PORT',
  user: 'DB_USER', usuario: 'DB_USER',
  password: 'DB_PASSWORD', clave: 'DB_PASSWORD',
  database: 'DB_NAME', db: 'DB_NAME'
};

function cargarEntorno() {
  const candidatos = [
    path.resolve(__dirname, '.env'),
    path.resolve(__dirname, '..', '.env'),
    path.resolve(__dirname, '..', '..', '.env'),
    path.resolve(__dirname, '..', '..', 'conn.txt')
  ];
  for (const archivo of candidatos) {
    let texto;
    try { texto = fs.readFileSync(archivo, 'utf8'); } catch (_) { continue; }
    let leidas = 0;
    for (const linea of texto.split(/\r?\n/)) {
      const l = linea.trim();
      if (!l || l.startsWith('#')) continue;
      const i = l.indexOf('=');
      if (i < 0) continue;
      const bruta = l.slice(0, i).trim();
      const valor = l.slice(i + 1).trim().replace(/^["']|["']$/g, '');
      const clave = ALIAS[bruta.toLowerCase()] || bruta;
      if (process.env[clave] === undefined) { process.env[clave] = valor; leidas++; }
    }
    if (leidas) console.log(`[config] ${leidas} valores desde ${archivo}`);
  }
}
cargarEntorno();

const config = {
  server:   process.env.DB_HOST     || '127.0.0.1',
  port:     parseInt(process.env.DB_PORT || '1433', 10),
  user:     process.env.DB_USER     || 'sa',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'MiniRed_DW',
  options: {
    // el homelab usa certificado autofirmado
    encrypt: String(process.env.DB_ENCRYPT || 'true') === 'true',
    trustServerCertificate: true,
    enableArithAbort: true
  },
  pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
  requestTimeout: 60000,
  connectionTimeout: 20000
};

if (!process.env.DB_PASSWORD) {
  console.warn('[config] Falta DB_PASSWORD. Copiá .env.example a .env y completalo, ' +
               'o dejá tp/conn.txt en su lugar.');
}

let pool = null;

async function getPool() {
  if (pool && pool.connected) return pool;
  pool = await new sql.ConnectionPool(config).connect();
  pool.on('error', (e) => console.error('[db] error del pool:', e.message));
  return pool;
}

const TIPOS = { varchar: sql.NVarChar, int: sql.Int, date: sql.Date, bit: sql.Bit };

/** Ejecuta con parametros. NUNCA concatenar valores del cliente en el texto SQL. */
async function consultar(texto, params = []) {
  const p = await getPool();
  const req = p.request();
  for (const { nombre, tipo, valor } of params) {
    req.input(nombre, TIPOS[tipo] || sql.NVarChar, valor);
  }
  const r = await req.query(texto);
  return r;
}

module.exports = { sql, getPool, consultar, config };
