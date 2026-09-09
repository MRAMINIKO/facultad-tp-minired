# MiniRed · Control de Capital Humano

TP Unidad 3 — Base de Datos Aplicada (UAI).
Perspectiva **Capital Humano × Expansión Territorial** sobre el caso MiniRed S.A.

## Estructura

```
tp/
├── sql/
│   ├── 01_rrhh.sql        data mart de RRHH (Dim_Empleado, Fact_Asistencia, Fact_Liquidacion)
│   ├── 02_cubo.sql        cubo aplanado, reglas inductivas, control negativo   ← ENTREGABLE
│   ├── 03_payload.sql     export del cubo a JSON
│   ├── 05_reglas.sql      reglas inductivas (igual a la sección 4 de 02_cubo.sql)
│   └── 04_juego_ddl.sql   tablas del juego + minería sobre las propias partidas
├── landing/
│   ├── index.html         landing + juego Data Detective
│   ├── datos.js           snapshot del cubo (respaldo si no hay backend)
│   └── backend/           Express + mssql
├── Dockerfile
└── conn.txt               credenciales (NO versionar)
```

## Puesta en marcha

**1. Base de datos**, en orden, con sqlcmd (el puerto va con coma):

```
sqlcmd -S <ip>,<puerto> -U sa -P "<clave>" -C -t 0 -b -i "..\MiniRed_Crear_Base.sql"
sqlcmd -S <ip>,<puerto> -U sa -P "<clave>" -C -t 0 -b -d MiniRed_DW -i "sql\01_rrhh.sql"
sqlcmd -S <ip>,<puerto> -U sa -P "<clave>" -C -t 0 -b -d MiniRed_DW -i "sql\02_cubo.sql"
sqlcmd -S <ip>,<puerto> -U sa -P "<clave>" -C -t 0 -b -d MiniRed_DW -i "sql\04_juego_ddl.sql"
```

**2. Backend**

```
cd landing\backend
npm install
npm start           (o arrancar.bat, que pide la clave por consola)
```

### Configuración

Node no lee `.env` por su cuenta, así que `db.js` trae un cargador propio, sin
dependencias. Busca en este orden y toma lo que encuentre:

1. `landing/backend/.env`
2. `landing/.env`
3. `tp/.env`
4. `tp/conn.txt` — el mismo archivo que usa `sqlcmd`, con `host` / `port` / `user` / `password`

Las **variables de entorno reales tienen prioridad** sobre los archivos, así que en
Docker o dokploy se configuran ahí y estos archivos se ignoran. Como ya existe
`tp/conn.txt`, con `npm start` alcanza: no hace falta crear ningún `.env`.

Al arrancar, la consola dice de qué archivo salió la configuración (nunca imprime
la contraseña). Si falta `DB_PASSWORD`, avisa antes de intentar conectarse.

**3. Despliegue** (opcional, dokploy/Traefik). Contexto de build = `tp/`:

```
docker build -t minired -f Dockerfile .
```

Variables de entorno: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `PORT`.

## Los dos modos de la landing

Al abrir, la página intenta `GET /api/cubo`.

- **En vivo** — hay backend: los KPIs, **los cinco gráficos del tablero**, la tabla de
  reglas y **cada movimiento del juego** salen de consultas reales a SQL Server. Todos
  traen un desplegable *"Consulta ejecutada"* con el SQL exacto, las filas devueltas y
  los milisegundos. Las partidas y los movimientos se guardan en `Juego_Partida` y
  `Juego_Movimiento`.
- **Snapshot local** — no hay backend: usa `datos.js` y el ranking va a `localStorage`.

El indicador arriba a la derecha dice en cuál de los dos está.

## Endpoints

| Ruta | Qué hace |
|---|---|
| `GET /api/salud` | ping; confirma que SQL Server responde |
| `GET /api/cubo` | ejecuta `03_payload.sql` y devuelve el cubo agregado |
| `GET /api/reglas` | ejecuta `05_reglas.sql`: soporte, confianza y lift |
| `POST /api/olap` | motor del juego: una operación OLAP → SQL real + resultado |
| `POST /api/partida` | abre una partida |
| `POST /api/partida/:id/movimiento` | registra un movimiento |
| `POST /api/partida/:id/acusacion` | cierra la partida con veredicto y XP |
| `GET /api/ranking` | tabla de posiciones |

`/api/olap` recibe **nombres** de dimensiones, nunca SQL. `consultas.js` es el único
lugar donde un nombre se traduce a un fragmento de consulta, y todo valor de filtro
viaja como parámetro. Cualquier nombre fuera del diccionario devuelve 400.
