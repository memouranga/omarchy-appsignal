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
