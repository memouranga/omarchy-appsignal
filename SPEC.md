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
