# AppSignal — plugin de barra para Omarchy

id: `memong.appsignal` · nombre visible: **AppSignal** · autor: Memo Uranga · MIT

## Qué hace (v1)

**Barra:** un icono. Punto rojo encima cuando hay algún uptime monitor caído o
errores abiertos. Sin números. Clic izquierdo abre el panel, clic derecho refresca.

**Panel:**
- Cabecera: "AppSignal", usuario (nombre/email del token), "updated X ago",
  botón refrescar (gira mientras carga).
- Una sección por app (todas las orgs/apps que ve el token). Encabezado con
  nombre + ambiente. Las apps con algo caído van primero.
  - **Errores abiertos:** hasta N incidentes (default 5) con nombre de la
    excepción, acción y hace cuánto. Clic abre el incidente en AppSignal.
  - **Uptime monitors:** cada monitor con arriba/abajo y desde cuándo (si está
    caído). Clic abre el monitor en AppSignal.
- Sin token: caja con instrucciones de dónde ponerlo.
- Error de red/API: se conserva la última data y se marca STALE.
- Teclado: j/k mueve, Enter abre, r refresca, Esc cierra.

**Fuera de alcance v1:** performance incidents, host metrics (servers),
check-ins, deploys. Quedan para v2.

## Cómo

Misma forma que `dev.git` (ya instalado en esta máquina, usar como molde):

```
manifest.json            kinds: ["bar-widget"], entry Panel.qml
bin/appsignal-collect    bash + curl + jq. Una consulta GraphQL, escribe
                         ~/.local/state/omarchy/appsignal/overview.json
Main.qml                 Timer + Process + FileView; expone apps normalizadas
Panel.qml                BarIconButton + KeyboardPanel; pinta el overview
```

### Token
Personal API key de https://appsignal.com/users/edit. Se lee de, en orden:
`$APPSIGNAL_API_TOKEN`, `$APPSIGNAL_TOKEN_FILE`, `~/.config/appsignal/api_token`
(chmod 600, una línea). Nunca en shell.json.

### API
`POST https://appsignal.com/graphql?token=TOKEN`, body `{query, variables}`.
Campos verificados en el esquema (https://appsignal.com/graphql/docs):
`viewer { name email organizations { id name slug apps { id name environment
status lastPushProcessedAt exceptionIncidents(state: OPEN, limit, order: LAST)
{ number exceptionName exceptionMessage actionNames namespace count severity
lastOccurredAt } uptimeMonitors { id name url regions alerts { id state
openedAt lastValue message } } } } }`.
Monitor caído = tiene alerts con state OPEN o WARMUP.
URLs: `https://appsignal.com/<orgSlug>/sites/<appId>/exceptions/incidents/<n>`
y `.../uptime-monitoring/<monitorId>`.

### Settings (manifest schema)
- `refreshIntervalSec` (default 120, min 30)
- `incidentsPerApp` (default 5)

## Desarrollo
- Proyecto: `~/work/omarchy-appsignal` (este repo).
- Para probar: `ln -s ~/work/omarchy-appsignal ~/.config/omarchy/plugins/memong.appsignal`
  y `omarchy plugin enable memong.appsignal right`. OJO: con el symlink el shell
  NO recarga solo al guardar; tras editar QML correr `omarchy restart shell`.
- Validar: `omarchy plugin validate ~/work/omarchy-appsignal` y
  `/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Panel.qml Main.qml` (solo avisos de estilo, sin errores).
- Errores QML en vivo: `qs log -p "$OMARCHY_PATH/shell" --tail 100`.
- Checklist de la guía oficial (plugins.omarchy.org/develop): clic, Esc,
  `omarchy-shell shell summon memong.appsignal '{}'`, `shell hide`, disable,
  re-enable, restart shell, remove. Publicar: issue en
  github.com/omacom/omarchy-plugin-marketplace (template submit-plugin.yml).
- Flujo: spec → shape → plan → ejecutar. Sonnet desarrolla, Opus prueba y
  arregla lo difícil, Fable valida y orquesta.

---

# v0.2 — Investigar incidentes con el agente

Aprobado por Memo el 2026-09-15.

## Qué cambia
Al activar una fila de incidente de error en el panel:
- **Enter o clic izquierdo → agente.** Ejecuta
  `omarchy agent prompt "<prompt>"` (abre una terminal con el agente por
  default de Omarchy, igual que `omarchy agent crash`). Cierra el panel.
- **Clic derecho o tecla `o` → navegador.** Comportamiento actual
  (`omarchy launch browser <url>`).
- Setting nuevo `incidentAction` en el manifest: `"agent"` (default) o
  `"browser"`. Con `"browser"`, Enter/clic izquierdo abren el navegador como en v0.1.
- Filas de uptime monitors: sin cambio (siempre navegador).

## Prompt que recibe el agente
Una sola línea, con los datos que ya trae el overview (app, environment, org,
número, exceptionName, exceptionMessage, action, namespace, count,
lastOccurredAt, url). Redacción:

  Investigate AppSignal incident #<n> "<exceptionName>" in app <app> (<env>),
  namespace <ns>, action <action>, <count> occurrences, last at <lastOccurredAt>.
  Message: <exceptionMessage>. URL: <url>. Use the AppSignal MCP to read the
  incident, its stack trace and recent samples; explain the probable root cause
  and propose a fix. Do not change the incident state or severity unless I ask.

Escapar con `Util.shellQuote` cada valor interpolado; el prompt completo va
como UN argumento a `omarchy agent prompt`. Ejecutar vía `root.bar.run(...)`
como ya se hace con `omarchy launch browser`.

## Prerequisito (documentar en README, no lo hace el plugin)
Conectar el MCP de AppSignal al agente. Para Claude Code:
`claude mcp add --transport http appsignal https://appsignal.com/api/mcp --header "Authorization: Bearer <MCP token>"`
(token MCP de AppSignal, permisos read). Verificar la sintaxis exacta en
https://docs.appsignal.com/mcp-server antes de escribirla en el README.

## Fuera de alcance
Que el plugin mute estado/severidad de incidentes. Eso lo hace el agente en
sesión si el usuario lo pide.

## Manifest
- version → 0.2.0
- schema: `{"key":"incidentAction","type":"select"|"string","label":"Enter / left click on an incident","options":["agent","browser"],"defaultValue":"agent"}`
  (ver qué tipo de campo soporta el schema: leer manifests de fábrica en
  /usr/share/omarchy/shell/plugins/**/manifest.json y el validador).

## Nota de desarrollo (aprendida el 2026-09-16)
NUNCA probar la acción de agente simulando teclas (wtype) o clics sobre el
panel con datos reales: `bar.run(...)` ejecuta el comando de verdad y abre una
sesión de Claude en modo auto sobre un incidente de producción. Para probar el
comando armado, envolver la ejecución en un dry-run (por ejemplo, si existe la
variable de entorno `OMARCHY_APPSIGNAL_DRY_RUN=1`, solo `console.log(cmd)` y no
ejecutar) o revisar el string a ojo. La prueba real la hace Memo, a mano.

---

# v0.3 — Fila de apps y solo favoritas

Aprobado por Memo el 2026-09-16.

## Fila de apps (tabs deslizables)
- Arriba del panel (debajo del hero), una fila de `Button` (qs.Ui) con una
  entrada por app visible: texto "Nombre · env" con env abreviado
  (production→prod, development→dev, staging→stg; otros tal cual).
- La fila va dentro de un `Flickable` con `flickableDirection:
  Flickable.HorizontalFlick`, `clip: true`, ancho = ancho del panel; el
  `Row` interior usa anchos naturales (NO cellWidth igual como agents). Rueda
  del mouse sobre la fila desplaza horizontalmente (WheelHandler o
  MouseArea.onWheel). Al seleccionar una app, asegurar que su botón quede
  visible (ajustar contentX).
- Botón seleccionado: `selected: true`; `hasCursor` cuando la zona de foco es
  la fila. Punto de alerta (Rectangle pequeño, color urgent) en la esquina
  del botón si esa app tiene errores abiertos o monitores caídos.
- Debajo de la fila, SOLO la app seleccionada: encabezado (nombre, env,
  resumen "N errors · M down"), sección OPEN ERRORS, sección UPTIME. Misma
  presentación que hoy, pero de una app.
- Si solo hay una app visible, la fila se oculta (`visible: apps.length > 1`).

## Navegación
- Zonas de foco: "apps" (la fila) y "rows" (las filas de la app). Up/Down
  (k/j) cambia de zona como en dev.git; h/l o ←/→ cambian de app cuando el
  foco está en la fila. `1`-`9` saltan a la app N. Enter en la fila = abrir la
  app en el navegador.
- Clic medio en el icono de la barra rota a la siguiente app (y si el panel
  está cerrado, solo cambia la selección).
- La app seleccionada se persiste en `~/.local/state/omarchy/appsignal/panel.json`
  (`{"selectedAppId": "..."}`), patrón prefsFile de dev.git. Si la app ya no
  existe, seleccionar la primera.
- Al abrir el panel, la selección persistida se respeta (no se salta a la app
  con más problemas). El orden de la fila sigue siendo "con problemas primero".

## Solo favoritas
- El colector pide `viewerPinned` en cada app y lo escribe como `pinned: bool`.
- Main.qml expone `apps` ya filtradas: si el setting `onlyPinned` (default
  true) está activo y hay ≥1 app con `pinned`, solo esas. Si no hay ninguna
  fijada, se muestran todas y `Main.pinnedFallback = true`.
- Panel: cuando `pinnedFallback`, mostrar una línea dim debajo del hero:
  "Pin apps in AppSignal to show only those here".
- Los totales de la barra (punto de alerta, tooltip) se calculan sobre las
  apps visibles, no sobre todas.

## Manifest
- version → 0.3.0
- schema: `{"key":"onlyPinned","type":"boolean","label":"Show only apps pinned in AppSignal","defaultValue":true}`
  (verificar que exista el tipo boolean en manifests de fábrica; si no,
  usar enum ["pinned","all"]). Agregar a `barWidget.defaults`.

## README
- Actualizar "What you get" (fila de apps, solo favoritas), tabla de teclas
  (h/l, 1-9, clic medio), settings (`onlyPinned`) y cómo fijar apps en
  AppSignal (el icono de pin/estrella en la lista de apps).

---

# v0.4 — Performance, salud y deploy

Aprobado por Memo el 2026-09-17.

## API de métricas — consultas verificadas (2026-09-17)

Verificado con curl contra SkillsNT prod (`site_id 69447d2f1caf1b2e8cb38c68`) y
CloudHealth prod (`site_id 69798e1fc073d8fe2f86155d`), organización `grupo-9t-1`.
Endpoint `POST https://appsignal.com/api/v2/metrics/list`, header
`Authorization: Bearer <token>`.

### Línea de salud (última hora)

Un solo POST con los tres selectores juntos (misma ventana, mismo `group_by`):

```json
{
  "site_id": "<app id>",
  "from": "<now - 1h, ISO8601>",
  "to": "<now, ISO8601>",
  "resolution": "MINUTELY",
  "select": [
    {"id": "throughput", "name": "site_throughput", "tags": {}, "field": "COUNTER", "aggregation": "SUM"},
    {"id": "errorRate", "name": "error_rate", "tags": {"namespace": "web"}, "field": "GAUGE", "aggregation": "AVERAGE"},
    {"id": "meanMs", "name": "transaction_duration", "tags": {"namespace": "web"}, "field": "MEAN", "aggregation": "AVERAGE"}
  ],
  "group_by": ["Name"],
  "limit": 10
}
```

Respuesta: una fila por métrica (porque `group_by` es `["Name"]`), cada una con
su propio selector en `data`; se combinan con `[.rows[].data] | add`.
Ejemplo real (SkillsNT prod, 17:01–18:00 UTC): `throughput: 2693` (requests en
la hora — `SUM` sobre `MINUTELY` ya da el total de la ventana, no hace falta
dividir), `errorRate: 0.0`, `meanMs: 4.55` (ms). CloudHealth prod:
`throughput: 2473`, `errorRate: 0.0`, `meanMs: 537.86`.

**`error_rate` ya viene en por ciento (0–100), no como fracción 0–1.**
Corregido el 2026-09-17 contra la API: con `group_by` por `namespace` y
`aggregation: MAX` sobre 30 días, los namespaces que fallan en todas sus
transacciones (`unhandled`, `rake`, `runner`) devuelven exactamente `100.0`,
y hay valores intermedios como `16.08` y `5.02` — imposibles en una fracción.
Contraste independiente: SkillsNT prod 24h da `error_rate 0.07` con 44
respuestas HTTP 500 sobre ~78k requests (0.06%), no 7%. El panel imprime el
valor tal cual (nunca `× 100`), con decimales suficientes para que un 0.07%
real no se vea como "0.0%".

Notas de la API aprendidas a la fuerza:
- `site_throughput` no tiene tags (`available_tags: []`); pedirlo con un tag
  cualquiera lo rechaza. Tipo `COUNTER` → `field: "COUNTER"`.
- `error_rate` es tipo `GAUGE`, tags disponibles incluyen `namespace` y
  `namespace+action`; para la línea de salud basta `namespace: "web"` sin
  comodín (es el propio valor, no hace falta `group_by` extra).
- `transaction_duration` es tipo `MEASUREMENT` (no GAUGE/COUNTER): sus campos
  válidos son `MEAN`/`COUNT`/`MIN`/`MAX`/`P99`... — nunca `GAUGE`. Pedirlo con
  `tags: {}` (sin namespace) da `rows: []` vacío; hace falta al menos un tag
  fijo (`namespace: "web"`) o, si se usa comodín `"*"` en un tag, ese tag
  **debe** entrar también en `group_by` o la API responde
  `{"error":"ungrouped_wildcard", "message":"Wildcard for tag 'namespace' requires a matching group_by entry..."}`.
- Cuando la app no tuvo tráfico en la ventana, `transaction_duration` devuelve
  `rows: []` (visto con BahBah prod, 1 sola request en la hora) — tratar como
  `meanMs: null`, no como error.
- El namespace usado para salud es `web` (deja fuera `background`): mezclar
  namespaces da medias sin sentido (en SkillsNT, `background` promedia ~95 ms
  por unos pocos jobs largos, muy distinto a los ~4.5 ms del tráfico web real).

### Slowest actions (24h)

```json
{
  "site_id": "<app id>",
  "from": "<now - 24h, ISO8601>",
  "to": "<now, ISO8601>",
  "resolution": "HOURLY",
  "select": [
    {"id": "meanMs", "name": "transaction_duration", "tags": {"namespace": "*", "action": "*"}, "field": "MEAN", "aggregation": "AVERAGE"},
    {"id": "count", "name": "transaction_duration", "tags": {"namespace": "*", "action": "*"}, "field": "COUNT", "aggregation": "SUM"}
  ],
  "group_by": [{"Tag": "action"}, {"Tag": "namespace"}],
  "limit": 100
}
```

Sí acepta **dos** entradas de `group_by` a la vez (una por tag) — cada fila
trae `group: {action, namespace}` y `data: {meanMs, count}`. Se ordena por
`meanMs` descendente en el cliente (`jq 'sort_by(-.data.meanMs)'`) y se recorta
a N = `incidentsPerApp`. Con comodín `"*"` en `action`/`namespace` **ambos**
tags deben estar en `group_by` (mismo error `ungrouped_wildcard` si falta
alguno). Devuelve tanto acciones `web` como jobs `background` — se dejan
mezcladas (el roadmap solo pide "top acciones por duración media", sin excluir
background; de hecho ahí aparecen los jobs realmente lentos).
Ejemplo real, SkillsNT prod 24h: 147 filas; top por media,
`SubscriberStatsRefreshJob#perform` (background) 59000 ms / 1×,
`GarminTokenRefreshJob#perform` (background) 26636 ms / 1×,
`DailyWodDeliveryJob#perform` (background) 4379.5 ms / 24×. CloudHealth prod
24h, top web: `HospitalizacionsController#index` 5518 ms / 2×,
`GruposSaludDashboardController#index` 4111.4 ms / 12×,
`RecetaController#finalizar_receta` 3071.6 ms / 15×.

### Tiempos observados
Cada POST (salud o slow actions) tarda ~0.7–0.8 s contra la API real. Con 2
apps fijadas en paralelo, la fase 2 completa añade bien menos de 2 s al
colector.

## Colector — segunda fase (solo lectura de métricas)

- Apps candidatas: las que traen `viewerPinned: true` en la respuesta GraphQL
  de la fase 1 (sin importar el setting `onlyPinned`, que es de presentación,
  no de recolección); si ninguna está fijada, las primeras 6 de la lista
  completa (todas las orgs, en el orden que ya trae la API).
- Por cada app candidata, en paralelo (subshell `&` + `wait` al final), dos
  POST a `metrics/list` (salud 1h, slow actions 24h) con su propio
  `--max-time` (opción nueva `-metrics-timeout`, default 20s).
- Si cualquiera de los dos POST de una app falla (HTTP≠200, timeout, JSON
  inválido, o "ungrouped_wildcard" u otro error de la API): esa app se queda
  con `health: null` / `slowActions: []`, nunca aborta el resto del colector
  ni pone `ready:false` en el overview completo.
- Apps que no fueron candidatas (no pineadas y fuera del tope de 6 del
  fallback) también quedan con `health: null` / `slowActions: []`.
- La fase 1 (GraphQL) y la transformación a JSON no cambian de forma; la fase
  2 solo añade `health` y `slowActions` a cada objeto de app ya construido,
  después, por un merge jq con los ids de app como llave.

### Forma de los campos nuevos por app
```json
"health": { "throughput": 2693, "errorRate": 0.0, "meanMs": 4.55, "window": "1h" } | null,
"slowActions": [ { "action": "WelcomeController#home", "namespace": "web", "meanMs": 4.78, "count": 12 } ]
```

---

# v0.4.1 — Ranking de acciones lentas por impacto

Decisión de Fable el 2026-09-17, basada en la evaluación de Opus con datos reales
(SkillsNT: 4 de las 5 "más lentas" corrían 1×/día; CloudHealth:
`PatientDashboardController#index` 2099 ms × 1042 = 2188 s/día no aparecía).

- El colector calcula por acción `totalMs = meanMs × count` y entrega DOS listas
  por app: `slowWeb` (namespace `web`) y `slowBackground` (todo lo demás), cada
  una ordenada por `totalMs` desc, top N = `ceil(incidentsPerApp / 2)` + 1 (con
  el default 5 → 3 filas por grupo). Pedir a la API `limit` suficiente (≥200)
  para que el orden por impacto sea real y no sobre un top-100 por media.
- `slowActions` se conserva como concatenación (compatibilidad) pero el panel
  usa las dos listas.
- Panel: bajo PERFORMANCE, dos subgrupos con subtítulo dim: "WEB · 24H" y
  "BACKGROUND · 24H" (se oculta el vacío). Fila: acción, y a la derecha
  "2099 ms · 1042× · 36 min/day" (total humanizado: s, min, h por día).
- Prompt del agente: corregir plural ("over 1 request" / "over N requests") y
  añadir el total diario.

# v0.5 — Servers

## API de métricas — servers, investigación real (2026-09-17)

Verificado con curl contra los mismos dos hosts: `178.156.134.200-94c077fa010a`
(SkillsNT) y `87.99.136.94-c511a0f51603` (CloudHealth). `type_and_tags`
confirma: `cpu` → tags `[state, hostname, role, platform, region]`, tipo
GAUGE; `memory` → mismos tags, GAUGE; `swap` → mismos tags, GAUGE;
`disk_usage` → `[mountpoint, hostname, role, platform, region]`, GAUGE;
`load_avg` → `[hostname, role, platform, region]` (sin `state`), GAUGE.

**Valores de `state` encontrados** (`group_by:[{Tag:"hostname"},{Tag:"state"}]`,
15 min, `AVERAGE`):
- `cpu`: `user`, `system`, `nice`, `iowait`, `steal`, `idle`, `total_usage`.
  **`idle` siempre reporta 0.0 en ambos hosts** (el agente no la publica en
  estos hosts); `total_usage` sí viene poblada y coincide, dentro del margen
  de redondeo, con `user+system+nice+iowait+steal` (SkillsNT: 2.644+0.753 =
  3.397 ≈ `total_usage` 3.401; CloudHealth: 10.28+1.125 = 11.405 ≈
  `total_usage` 11.41). Unidad: **porcentaje** (0–100), no fracción.
  → **`cpuPct` = el valor de `total_usage` directo**, no hace falta sumar a
  mano (y sumar sería idéntico salvo que `idle` faltara).
- `memory`: `used`, `total`, `free`, `usage`, `shmem`. **`total`, `free`,
  `usage` y `shmem` reportan 0.0 siempre** en los dos hosts — comprobado con
  `AVERAGE` en ventanas de 15 min, 1h y `MAX` sobre 7 días: `total` nunca deja
  de ser 0.0. Solo `used` trae dato real (SkillsNT ~1089–1097 MB, CloudHealth
  ~2160–2164 MB). Unidad de `used`: **megabytes** (valores de esa magnitud
  son coherentes con RAM real de un contenedor pequeño; un `%` de 1089 no
  tendría sentido). **No se puede derivar `memPct` (usada/total) en estos dos
  hosts porque AppSignal nunca publica `total` para ellos** (limitación del
  agente en despliegues por contenedor, sin `/proc/meminfo` del host físico) —
  no es un bug del colector. `memPct` queda `null` cuando `total <= 0`;
  el mecanismo queda listo para cuando un host sí reporte `total`.
- `swap`: `used`, `total`, `usage`. Mismo patrón: `total` y `usage` en 0.0
  siempre (MAX sobre 7 días también 0.0) en ambos hosts. `used` sí trae dato:
  SkillsNT ~512–518 MB, CloudHealth 0.0 MB (esta app no usa swap). Como el
  roadmap ya contempla `swapPct` nulo, se usa esa vía: `swapPct = null`
  cuando `total <= 0` (los dos hosts actuales), calculable el día que
  `total` exista.
- `disk_usage`: tag es `mountpoint`, no `state`. El valor **ya viene en
  porcentaje** (SkillsNT: `/` y `/rails/storage` ambos 37.0 — mismo disco
  montado dos veces; CloudHealth: `/` 35.0). `diskPct` = el mayor entre los
  mountpoints; `diskMount` = su nombre.
- `load_avg`: sin tag `state`; un valor por host. SkillsNT 0.017–0.019,
  CloudHealth 0.107–0.116. Sin unidad (load average estándar de Unix).

**Contraste de sentido común** (motivo de esta investigación): con
`total_usage` como fuente, SkillsNT sale con CPU ~3.4% y load ~0.02 — un host
casi ocioso, coherente. CloudHealth CPU ~11.4% y load ~0.11 — también
coherente (más ocupado que SkillsNT, pero lejos de saturado). Si en vez de
`total_usage` se hubiera sumado solo `user` mal etiquetado o usado `usage` de
`memory`/`swap` (que siempre da 0), los números habrían sido absurdos o
siempre en cero — de ahí la advertencia del roadmap.

**Dos POSTs por app** (no uno): un `group_by` compartido no puede mezclar la
dimensión `state` (cpu/memory/swap) con `mountpoint` (disk_usage) sin generar
un producto cruzado confuso (se probó: cada fila queda con un `mountpoint`
sintético igual al `state`, ej. `mountpoint: "total_usage"`, inofensivo pero
frágil de parsear). Se separan en dos peticiones, ambas dentro de la misma
subshell paralela por app:

```json
// POST 1: cpu + memory (used/total) + swap (used/total/usage) + load_avg
{
  "site_id": "<app id>", "from": "<now-15m>", "to": "<now>", "resolution": "MINUTELY",
  "select": [
    {"id":"cpu","name":"cpu","tags":{"state":"*","hostname":"*"},"field":"GAUGE","aggregation":"AVERAGE"},
    {"id":"memUsed","name":"memory","tags":{"state":"used","hostname":"*"},"field":"GAUGE","aggregation":"AVERAGE"},
    {"id":"memTotal","name":"memory","tags":{"state":"total","hostname":"*"},"field":"GAUGE","aggregation":"AVERAGE"},
    {"id":"swap","name":"swap","tags":{"state":"*","hostname":"*"},"field":"GAUGE","aggregation":"AVERAGE"},
    {"id":"load1","name":"load_avg","tags":{"hostname":"*"},"field":"GAUGE","aggregation":"AVERAGE"}
  ],
  "group_by": [{"Tag":"hostname"},{"Tag":"state"}], "limit": 100
}
// POST 2: disk_usage
{
  "site_id": "<app id>", "from": "<now-15m>", "to": "<now>", "resolution": "MINUTELY",
  "select": [{"id":"disk","name":"disk_usage","tags":{"mountpoint":"*","hostname":"*"},"field":"GAUGE","aggregation":"AVERAGE"}],
  "group_by": [{"Tag":"hostname"},{"Tag":"mountpoint"}], "limit": 100
}
```

Tiempos observados: ~0.7–0.8 s cada POST, ~1.07 s los dos en secuencia por
app; con 2 apps en paralelo (como health/slowActions), bien dentro de
`metrics_timeout` (20s).

Ruta del botón "navegador": `host-metrics` y `hosts` bajo `/sites/<id>/`
devuelven 301 sin sesión autenticada (indistinguible de una ruta inexistente
sin login real en el navegador), no se pudo confirmar con certeza sin iniciar
sesión interactiva en appsignal.com — fuera del alcance de esta verificación
por curl. Por la regla del roadmap ("si no se puede confirmar, usar
app.url"), clic derecho/`o` en una fila de host abre `app.url`.

## Implementación

- Colector, fase 2, por app candidata, los dos POSTs de arriba (mismo patrón
  que health/slowActions: timeout propio `metrics_timeout`, fallo de
  cualquiera de los dos → `hosts: []` para esa app, el resto del overview
  sigue `ready`).
- Por host: `cpuPct` = `total_usage`; `memPct` = `memUsed/memTotal*100`
  redondeado si `memTotal > 0`, si no `null`; `load1` = `load_avg` tal cual;
  `diskPct`/`diskMount` = el mountpoint con mayor `disk_usage`; `swapPct` =
  `swapUsed/swapTotal*100` si `swapTotal > 0`, si no `null`.
- **Memoria absoluta** (corrección tras probar con datos reales): como ningún
  host real publica `memory state=total`, `memPct`/`swapPct` salían siempre
  `null` y la fila se quedaba sin memoria. El colector entrega además
  `memUsedMb` y `swapUsedMb` (el `used` de la API, en MB, número o `null`), que
  es el único dato de memoria real que hay en estos hosts. El panel prefiere el
  porcentaje y cae al absoluto: `MEM 41%` si hay `memPct`, si no
  `MEM 1.1 GB` (`<1024 MB` → `"512 MB"`; si no, GB con un decimal); `n/a` solo
  si faltan los dos. `SWAP` solo aparece cuando el host está usando swap
  (`swapUsedMb > 0` o `swapPct > 0`) y **nunca** enciende `warn` por sí solo:
  `memWarn` sigue aplicando únicamente a `memPct` (un absoluto sin total no es
  comparable contra un umbral porcentual).
- Shape por app: `hosts: [{hostname, shortName, cpuPct, memPct, memUsedMb,
  load1, diskPct, diskMount, swapPct, swapUsedMb, warn: bool}]`. `shortName` = hostname sin el sufijo
  `-<container id>` cuando el prefijo antes del último `-` parece una IP o un
  nombre legible (con los dos hosts reales: `178.156.134.200-94c077fa010a` →
  `178.156.134.200`; `87.99.136.94-c511a0f51603` → `87.99.136.94`). `warn` =
  `cpuPct >= cpuWarn || diskPct >= diskWarn || (memPct != null && memPct >=
  memWarn)`. Fallo de la consulta → `hosts: []`, overview sigue ready.
- Settings nuevos (integer): `cpuWarn` 80, `memWarn` 85, `diskWarn` 85.
- Temporales del colector: el shell lo lanza como hijo y lo mata con SIGKILL al
  reiniciar (`omarchy restart shell`), así que el `trap ... EXIT` no alcanza a
  correr y quedaba un `/tmp/tmp.XXXX` con la respuesta de la API dentro
  (encontrados dos en la prueba del 2026-09-17). El scratch pasa a
  `$XDG_RUNTIME_DIR/appsignal-collect.XXXXXX` (tmpfs, se borra al cerrar
  sesión), con nombre propio, y cada corrida barre los `appsignal-collect.*` de
  más de 60 min antes de empezar; el trap cubre además INT/TERM/HUP.
- `totals.hostsWarn` por app y global (cuenta de hosts con `warn: true`);
  `attentionNeeded` también se enciende si `hostsWarn > 0` en apps visibles.
  El punto del tab de la app también.
- Panel: sección SERVERS (entre PERFORMANCE y UPTIME). Una fila por host en
  **dos líneas apiladas** (probado el 2026-09-17: con la línea de métricas a la
  derecha, el hostname quedaba elidido a "178.1…" — las métricas no caben al
  lado del nombre en el ancho del panel):
  1. glyph de servidor (mdi-server U+F048B; verificar con od que no quede
     vacío) + hostname completo, con el `shortName` en color normal y la cola
     `-<container id>` en dim (así el nombre completo se ve una sola vez).
  2. métricas, alineadas bajo el nombre: "CPU 4%  ·  MEM 1.1 GB  ·  LOAD 0.02
     ·  DISK 37%  ·  SWAP 512 MB". Cada valor sobre umbral en color urgent;
     LOAD y SWAP siempre dim; "n/a" cuando no hay dato, nunca "NaN%".
  Entra al cursor (`kind: "host"`).
- Acción: Enter/clic izq = agente (respeta `incidentAction`) con prompt:
  "Analyze host <hostname> of app <app> (<env>) in AppSignal: CPU <x>%, memory
  <y>%, load <z>, disk <w>% on <mount>. Use the AppSignal MCP to read host
  metrics over the last 24h and 7d, correlate with throughput, slow actions and
  background jobs, and propose concrete optimizations (right-sizing, memory,
  swap, disk cleanup, process counts). Do not change anything unless I ask."
  Cuando no hay porcentaje de memoria se manda el absoluto ("memory 1.1 GB
  used") y, si el host está usando swap, "swap 512 MB in use"; una cláusula sin
  ningún dato se omite en vez de decir "null%". Clic derecho/`o` = navegador a `app.url` (ver arriba).
- manifest version 0.5.0. README actualizado.

---

# v0.6 — Jobs, check-ins y alertas

Spec de Fable, 2026-09-17. Sonnet investiga primero la API (solo lectura) y
documenta aquí las consultas exactas antes de implementar.

## Jobs (colas de background)
- Métricas ya listadas para estas apps: `active_job_queue_job_count`,
  `active_job_queue_priority_job_count`, `active_job_queue_time`,
  `transaction_queue_duration`. Investigar con `type_and_tags` sus tags
  (¿`queue`? ¿`status`/`state`? ¿adapter?) y unidades. Ventana: última hora.
- Shape por app: `queues: [{name, processed, failed, queueTimeMs, warn}]`
  (adaptar a lo que la API dé de verdad; si `failed` no existe, omitir).
  Orden: por `queueTimeMs` desc. Top N = incidentsPerApp.
- Setting `queueTimeWarn` (integer, ms, default 30000): `warn` si
  `queueTimeMs` lo supera. `totals.queuesWarn` por app y global.
- Panel: sección JOBS (después de UPTIME). Fila: glyph (mdi-tray-full o
  similar, verificar con od), nombre de la cola, a la derecha
  "1.2k jobs/h · 340 ms wait" (y "· 3 failed" en urgent si aplica).
  Acción: Enter = agente ("Analyze background queue <name> of app … using the
  AppSignal MCP: throughput, queue time and the slowest jobs; propose fixes"),
  clic derecho/`o` = navegador a app.url.

## Check-ins
- El overview ya trae `checkIns[]` {identifier, kind, lastState, failing,
  lastErrorAt, lastSuccessAt, url}. Panel: sección CHECK-INS. Fila: glyph
  (mdi-timer-check o similar), identifier, kind en dim, a la derecha estado:
  "OK · 2h ago" en accent o "MISSED · 5h ago" en urgent. Clic/Enter = navegador
  (no agente). Oculta si vacío.
- `totals.checkInsFailing` ya existe: sumarlo a `attentionNeeded` y al punto del tab.

## Alerts (triggers de anomalías)
- Añadir a la consulta GraphQL por app: alertas abiertas. Investigar en
  https://appsignal.com/graphql/docs (HTML estático, descargable con curl) los
  argumentos reales de `App.alerts` y los campos de `Trigger` (nombre/
  descripción, metricName, condición, umbral). Pedir solo lo necesario y, si
  hay argumento de estado/límite, usarlo para no traer el histórico.
- Shape: `alerts: [{id, state, triggerName, metric, message, lastValue,
  peakValue, openedAt, url}]` solo OPEN y WARMUP. `totals.alertsOpen`.
- Panel: sección ALERTS arriba de OPEN ERRORS (es lo más urgente). Fila: glyph
  de campana, triggerName, meta "<metric> · last <v> · peak <v>", a la derecha
  "OPEN · 12m". Enter = agente ("Investigate the open AppSignal alert …"),
  clic derecho/`o` = navegador.
- Suma a `attentionNeeded`, punto del tab y tooltip del icono.

## General
- Orden final de secciones: ALERTS, OPEN ERRORS, PERFORMANCE, SERVERS, UPTIME,
  JOBS, CHECK-INS, línea de deploy. Todas entran al cursor con su `kind`.
- Tooltip del icono: resume solo lo que esté mal ("3 errors · 1 alert · 1 host hot").
- manifest 0.6.0, README actualizado. Tiempo total del colector: objetivo < 7 s
  con 2 apps fijadas (todo lo de fase 2 en paralelo).
