# Roadmap a v1.0 estable

Aprobado por Memo el 2026-09-17. Fuente de verdad del alcance; el detalle técnico
de cada versión se agrega a `SPEC.md` cuando le toca.

## Reglas del proyecto

- **Ramas.** `main` = lo que revisa y lista el marketplace. NO se toca hasta
  v1.0 (cada push a `main` invalida la revisión: issue omacom/omarchy-plugin-marketplace#7141).
  Todo el desarrollo va en `dev`. v1.0 = un solo merge a `main` + tag `v1.0.0`
  + issue de *plugin update* en el marketplace.
- **Roles por versión.** Fable escribe la sección de spec, delega y valida.
  Sonnet implementa. Opus prueba con datos reales y arregla lo difícil.
  Fable revisa diff + captura + validate + lint y commitea en `dev`.
- **Seguridad de pruebas.** Nunca simular Enter/clic sobre filas que disparan
  `bar.run` (agente real contra producción). Teclas permitidas en pruebas
  automatizadas: h l ← → 1-9 k Escape. Desde v0.7 existe
  `OMARCHY_APPSIGNAL_DRY_RUN=1` para probar acciones sin ejecutarlas.
- **Nada bajo /usr/share/omarchy se edita.** El token nunca se imprime.
- **Tras editar QML:** `omarchy restart shell` (el symlink no recarga solo).

## Forma del panel (objetivo v1)

```
[hero: AppSignal · usuario · UPDATED X AGO · refresh]
[ SkillsNT · prod ● ][ CloudHealth · prod ● ][ ... ]      ← fila deslizable (v0.3)
SkillsNT  production                          5 errors · 1 down
1.2k req/h · 0.4% errors · 182 ms mean · apdex 0.97        ← línea de salud (v0.4)
OPEN ERRORS        (máx N filas)                           ← v0.1
PERFORMANCE        (máx N filas)                           ← v0.4
SERVERS            (una fila por host)                     ← v0.5
UPTIME             (una fila por monitor)                  ← v0.1
JOBS               (una fila por cola)                     ← v0.6
CHECK-INS          (una fila por check-in)                 ← v0.6
ALERTS             (alertas de triggers abiertas)          ← v0.6
deploy 8a7eda9 · memo · 21d ago · 3 errors since           ← línea al pie (v0.4)
```
Las secciones vacías se ocultan. Setting `sections` apaga las que no se quieran.

## Versiones

### v0.4 — Performance, salud y deploy
- **Performance:** incidentes de performance OPEN/WIP (ya vienen en el
  overview como `perf`). Como AppSignal los cierra solos (SkillsNT y CloudHealth
  tienen >50 CLOSED y 0 OPEN), si no hay abiertos la sección muestra
  "Slowest actions · 24h": top N acciones por duración media, vía
  `POST /api/v2/metrics/list` (`transaction_duration`, field MEAN, group_by
  Tag action + namespace). Fila: acción, media en ms, throughput. Enter =
  agente con prompt de performance; clic derecho/`o` = navegador.
- **Línea de salud** (última hora): throughput, tasa de error, duración media.
  Métricas candidatas ya listadas por la API para estas apps: `site_throughput`,
  `error_rate`, `transaction_duration`, `response_status`. Sonnet verifica
  campos/agregaciones reales contra la API antes de implementar.
- **Línea de deploy** al pie con `lastDeploy` (ya viene en el overview).
- Colector: segunda fase por app fijada (solo apps visibles, para no gastar
  peticiones), en paralelo, con timeout propio; si falla, esa parte queda
  `null` y el resto del overview sigue válido.

### v0.5 — Servers
- Por host (tag `hostname`): CPU % (`cpu`, sumar estados no-idle), memoria
  usada %, load 1m (`load_avg`), disco más lleno (`disk_usage` por
  `mountpoint`), swap si >0. Verificado 2026-09-16: `metrics/list` con
  `group_by:[{"Tag":"hostname"}]`, `field:"GAUGE"`, `aggregation:"AVERAGE"`
  devuelve filas por host (SkillsNT: 178.156.134.200-…, CloudHealth: 87.99.136.94-…).
- Fila: hostname corto, mini barras o porcentajes con color urgent sobre umbral
  (settings `cpuWarn` 80, `memWarn` 85, `diskWarn` 85).
- Enter = agente: "analiza las métricas del host X vía MCP y propón
  optimizaciones"; clic derecho = página Host metrics en AppSignal.
- El punto de alerta de la barra también se enciende por umbral de host.

### v0.6 — Jobs, check-ins y alertas
- **Jobs:** `active_job_queue_job_count` y `active_job_queue_time` por cola.
- **Check-ins:** triggers de check-in con `lastState`; MISSED/LATE/UNEXPECTED
  en urgent (el colector ya los pide).
- **Alerts:** alertas OPEN/WARMUP de triggers de anomalías (`app.alerts`),
  con nombre del trigger, valor y desde cuándo.

### v0.7 — Endurecimiento
- Setting `sections` (lista) y `appOrder` (`attention` | `name` | `pinned`).
- `OMARCHY_APPSIGNAL_DRY_RUN=1`: las acciones solo loguean el comando.
- Tests: `tests/` con fixtures JSON y pruebas bash del transform jq y del
  manejo de errores del colector (patrón `tests/` de dev.git). `shellcheck` limpio.
- CI en GitHub Actions: JSON del manifest, shellcheck, tests del colector.
- Colector: respeta rate limits, backoff ante 429/5xx, nunca deja overview a medias.
- Accesibilidad de teclado completa en todas las secciones; sin TypeErrors en journal.
- CHANGELOG.md, capturas nuevas, README final.

### v1.0 — Estable
- Smoke test manual de Memo con una app "completa" (ver abajo), en panel
  abierto/cerrado, sin token, token inválido, sin red, tema claro/oscuro,
  barra arriba/abajo/lateral.
- Checklist oficial de plugins.omarchy.org/develop completo.
- Merge `dev` → `main`, tag `v1.0.0`, release en GitHub, issue de plugin
  update en el marketplace.

## Smoke test: dejar una app "completa" en AppSignal

Estado al 2026-09-17 de SkillsNT prod y CloudHealth prod: tienen errores,
deploys y 1 host cada una; les falta uptime, check-ins y triggers.

1. **Uptime monitor** por app (URL pública + región). Se crea en AppSignal →
   app → Uptime monitoring, o por GraphQL `createUptimeMonitor`.
2. **Trigger de anomalía** (ej. CPU > 80% 5 min, error rate > 5%) en
   Anomaly detection → Triggers, para poblar ALERTS.
3. **Check-in** tipo cron o heartbeat. Requiere que algo lo reporte: en Rails
   `Appsignal::CheckIn.cron("nightly-backup") { ... }` en un job existente, o
   un heartbeat con `Appsignal::CheckIn.heartbeat("web", continuous: true)`.
4. **Performance:** ya hay datos (incidentes cerrados + métricas); nada que configurar.
5. **Jobs:** ya reporta `active_job_queue_*`; nada que configurar.
