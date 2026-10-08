# Mapeo tablas QA — Unificación (reales + mock)

**Proyecto:** MT-EXP-005-MAP-RECONOCER · Unificación de Direcciones  
**Entrega vigente:** SPs divididos · rama `feature/unificacion-edf-views`  
**Fecha corrección:** 2026-09-17  

> **Importante:** hay **dos modos**. QA elige **uno** por corrida.  
> - **Reales** → `sp_unificacion_*` + `v_xpm_*` + `edf_views`  
> - **Mock** → `sp_unificacion_mock_*` + `v_mock_*` + `bdm_stage`  
> No mezclar objetos de un modo con el otro.

Detalle SPs / prompts: [`ENTREGA_QA_UNIFICACION.md`](ENTREGA_QA_UNIFICACION.md) · [`MATRIZ_QA_SPS_DIVIDIDOS_DS.md`](MATRIZ_QA_SPS_DIVIDIDOS_DS.md)

---

## 0. Resumen rápido (qué debe usar QA)

| Pieza | Modo A — Datos **reales** | Modo B — Datos **mock** |
|-------|---------------------------|-------------------------|
| **DB** | Consumidor `dba_rncr_batch` | Mismo (o productor con seed) |
| **Fuente cruda** | `ds_dba_rncr_batch.edf_views.xpm*` | Tablas **`bdm_stage.*`** (seed TC) |
| **Vistas que leen los SPs** | `bdm_tempo.v_xpm_*` | `bdm_tempo.v_mock_*` |
| **Catálogos** | `bdm_datos.nomenclatura` · `tipo_ubicacion_dir` · `diccionario_complementos` | `bdm_stage.nomenclatura` · `tipo_ubicacion_dir` · `diccionario_complementos` |
| **Staging** | `bdm_tempo.stg_regla*` | `bdm_tempo.stg_mock_regla*` |
| **Salida** | **`bdm_datos.unificacion_direccion`** | **`bdm_datos.unificacion_direccion_mock`** |
| **SPs (orquestadores)** | `sp_unificacion_regla1/2/3` | `sp_unificacion_mock_regla1/2/3` |
| **Run** | `run_unificacion_ejecucion_secuencial.sql` | `run_unificacion_mock_ejecucion_secuencial.sql` |

---

## 1. Modo A — Datos reales (Data Sharing)

### 1.1 Tablas fuente (Data Sharing)

| Tabla | Rol |
|-------|-----|
| `ds_dba_rncr_batch.edf_views.xpm` | Persona (PIN, CIIU, FK location / counterparties) |
| `ds_dba_rncr_batch.edf_views.xpm_location` | Ubicación por persona |
| `ds_dba_rncr_batch.edf_views.xpm_location_val_contactinformations` | Direcciones tokenizadas / `standardized*` |
| `ds_dba_rncr_batch.edf_views.xpm_counterparties` | Entidades reportantes |

**Filtro direcciones:** `contacttype IN ('1','2','3','7','8')` — RES, LAB, CRR, DIR, (+8).

**Nota:** el path actual **edf_views** no exige `relationalizelastupdate` en los JOINs (eso era del mapeo histórico `ifr_data`).

### 1.2 Vistas BDM (lo que usan los SPs — no consultar XPM crudo en gates)

| Vista | Equivale a |
|-------|------------|
| `bdm_tempo.v_xpm_contacto_direccion` | Base contacto (interna) |
| `bdm_tempo.v_xpm_relacion_persona_ubicacion` | `relacion_persona_ubicacion` |
| `bdm_tempo.v_xpm_ubicacion_estandarizada` | `ubicacion_estandarizada` |
| `bdm_tempo.v_xpm_direccion_fisica` | `direccion_fisica` |
| `bdm_tempo.v_xpm_reporte_relacion_persona_ubica` | `reporte_relacion_persona_ubica` |
| `bdm_tempo.v_xpm_ciiu_persona` | `ciiu_persona` |

Deploy: `_strct` → `02_vistas_insumo_edf_views.sql`

### 1.3 Catálogos y salida (reales)

| Objeto | Rol |
|--------|-----|
| `bdm_datos.tipo_ubicacion_dir` | Catálogo tipos RES/LAB/CRR/… |
| `bdm_datos.nomenclatura` | Niveles complemento (R2) |
| `bdm_datos.diccionario_complementos` | Diccionario R2 Esc4 |
| `bdm_tempo.stg_regla*` / `stg_motor*` | Staging temporal (se dropea al final) |
| **`bdm_datos.unificacion_direccion`** | **Resultado** Unificación |

### 1.4 SPs reales (nombres exactos)

```sql
CALL bdm_datos.sp_unificacion_regla1();
CALL bdm_datos.sp_unificacion_regla2();
CALL bdm_datos.sp_unificacion_regla3();  -- sin lat/long → 0 filas = N/A
```

| Regla | Procedimientos subdivididos |
|-------|-----------------------------|
| **R1** | `sp_unificacion_r1_preparar_insumo` · `…_r1_esc1_ciiu10_mismo_texto_padre_lab_crr` · `…_r1_esc2_ciiu81_90_mismo_texto_padre_res_crr` · `…_r1_esc3_otros_ciiu_mayor_entidades_reportan` · `sp_unificacion_regla1` |
| **R2** | `sp_unificacion_r2_preparar_insumo` · `…_r2_esc1_…` · `…_r2_esc3_…` · `…_r2_esc4_…` · `…_r2_esc5_…` · `…_r2_esc6_…` · `…_r2_motor_…` · `sp_unificacion_regla2` |
| **R3** | `sp_unificacion_r3_esc1_geo_misma_via_puerta_cercana` · `sp_unificacion_regla3` |

### 1.5 Gates (reales)

```sql
SELECT unifica_atributos, COUNT(*)
FROM bdm_datos.unificacion_direccion
GROUP BY 1 ORDER BY 1;

SELECT
  SUM(CASE WHEN cod_dw_direccion_unificada IS NULL THEN 1 ELSE 0 END) AS c03,
  SUM(CASE WHEN cod_dw_persona_ubic = cod_dw_direccion_unificada THEN 1 ELSE 0 END) AS c04
FROM bdm_datos.unificacion_direccion;
```

| Gate | Esperado |
|------|----------|
| R2 (`unifica_atributos=2`) | > 0 |
| C03 / C04 | **0** / **0** |
| R3 sin geo | **0 = N/A** (no FAIL) |

**No usar** en modo real: `perf_persona_meta` / `TC-R*-*` con `scenario_code`.

---

## 2. Modo B — Datos mock (SPs `*_mock_*`)

### 2.1 Tablas fuente (seed — `bdm_stage`)

| Tabla `bdm_stage` | Rol |
|-------------------|-----|
| `relacion_persona_ubicacion` | RPU / tipos ubicación / `ind_unificacion` |
| `ubicacion_estandarizada` | Texto ubicación, ciudad, lat/long (R3) |
| `direccion_fisica` | Complemento |
| `reporte_relacion_persona_ubica` | Entidades reportantes |
| `ciiu_persona` | CIIU (R1) |
| `tipo_ubicacion_dir` | Catálogo mock |
| `nomenclatura` | Catálogo mock |
| `diccionario_complementos` | Diccionario R2 mock |
| `perf_persona_meta` | `scenario_code` para suite TC (validación) |

Seed / setup referencia: `sql/01_bdm_stage_mock_setup.sql` · scripts `docs/sql_qa_redshift_mock/` / `sql/qa_redshift/`.

### 2.2 Vistas BDM mock (lo que usan los SPs mock)

| Vista | Lee de |
|-------|--------|
| `bdm_tempo.v_mock_relacion_persona_ubicacion` | `bdm_stage.relacion_persona_ubicacion` |
| `bdm_tempo.v_mock_ubicacion_estandarizada` | `bdm_stage.ubicacion_estandarizada` |
| `bdm_tempo.v_mock_direccion_fisica` | `bdm_stage.direccion_fisica` |
| `bdm_tempo.v_mock_reporte_relacion_persona_ubica` | `bdm_stage.reporte_relacion_persona_ubica` |
| `bdm_tempo.v_mock_ciiu_persona` | `bdm_stage.ciiu_persona` |

Deploy: `_strct` → `02b_vistas_insumo_mock.sql`  
**Estas vistas NO leen `edf_views`.**

### 2.3 Catálogos, staging y salida (mock)

| Objeto | Rol |
|--------|-----|
| `bdm_stage.tipo_ubicacion_dir` · `nomenclatura` · `diccionario_complementos` | Catálogos del seed |
| `bdm_tempo.stg_mock_regla*` / `stg_mock_motor*` | Staging aislado del path real |
| **`bdm_datos.unificacion_direccion_mock`** | **Resultado** Unificación mock |
| DDL | `_strct` → `01b_ddl_unificacion_direccion_mock.sql` |

### 2.4 SPs mock (nombres exactos — llevan `mock`)

```sql
CALL bdm_datos.sp_unificacion_mock_regla1();
CALL bdm_datos.sp_unificacion_mock_regla2();
CALL bdm_datos.sp_unificacion_mock_regla3();
```

| Regla | Procedimientos |
|-------|----------------|
| **R1** | `sp_unificacion_mock_r1_preparar_insumo` · `…_mock_r1_esc1_…` · `…_mock_r1_esc2_…` · `…_mock_r1_esc3_…` · `sp_unificacion_mock_regla1` |
| **R2** | `sp_unificacion_mock_r2_preparar_insumo` · `…_mock_r2_esc1_…` · `…_mock_r2_esc3_…` · `…_mock_r2_esc4_…` · `…_mock_r2_esc5_…` · `…_mock_r2_esc6_…` · `…_mock_r2_motor_…` · `sp_unificacion_mock_regla2` |
| **R3** | `sp_unificacion_mock_r3_esc1_geo_misma_via_puerta_cercana` · `sp_unificacion_mock_regla3` |

### 2.5 Validación mock (suite TC)

- Validar sobre **`bdm_datos.unificacion_direccion_mock`** (resultado de SPs mock) **o** la suite histórica sobre `bdm_stage` si aún usan validadores legacy — **no** mezclar con `unificacion_direccion` real.
- Casos: **TC-R1-01…TC-R1-08** · **TC-R2-01…TC-R2-14** (esperado violaciones = **0**).
- Scripts: `sql/qa_redshift/04_validacion_tc_r1_r2_bdm_stage.sql` · `tools/qa_validation_cases.py`.
- **TC-R2-14** (`R2_EMPATE`) = 0 · **R3 mock** con lat/long sembrado = sí se prueba.

---

## 3. Columnas fuente → BDM (modo real / edf_views)

Mismo mapeo lógico que se entregó a QA; destino = columnas de las vistas `v_xpm_*`.

### `edf_views.xpm`

| Columna fuente | Uso BDM |
|----------------|---------|
| `pin` | `cod_pin_persona` |
| `pin` → `FNV_HASH(pin)` | `id_buro_persona` |
| `location` | FK → `xpm_location.id` |
| `counterparties` | FK → `xpm_counterparties.id` |
| `bestpersonalinformation.mainisiccodeforproduct` | `cod_act_econo_ciiu_fte` (R1) |

### `edf_views.xpm_location`

| Columna fuente | Columna BDM | Notas |
|----------------|-------------|-------|
| `id` | `cod_dw_ubic` | |
| `location.val.contactinformations` | FK → contactinformations | |
| `location.val.personidtype` | `cod_tipo_ident_fte` | `3` = NIT |
| `location.val.cutoffdate` | `fecha_reporte` | En vista reporte |

> **No usar** `location.val.counterpartyidtype` para `cod_tipo_ident_fte`.

### `edf_views.xpm_location_val_contactinformations`

| Columna fuente | Columna BDM |
|----------------|-------------|
| `id` | `cod_dw_persona_ubic`, `cod_dw_direccion_fisica` |
| `…contacttype` | `cod_dw_tipo_ubicacion_dir` |
| `…standardizedtextoubicacion` | `texto_ubicacion` |
| `…contactasreportedstandardized` | `texto_ubicacion_normalizado` |
| `…contactasreported` | `texto_ubicacion_original` |
| `…contactasstandardizedscore` | `score_estandarizacion` |
| `…standardizeddanecode` | `cod_dw_ciudad` |
| `…standardizeddepartment` | `departamento` |
| `…standardizedmunicipality` | `municipio` |
| `…standardizedtipo` | `tipo_ubicacion` |
| `…standardizedcomplemento` | `complemento` *(R2)* |
| `…standardizedtipoviaprincipal` | `tipo_via_principal` *(R3)* |
| `…standardizedviaprincipal` | `via_principal` |
| `…standardizedviageneradora` | `via_generadora` *(R3)* |
| `…standardizednumeropuerta` | `numero_puerta` |
| `…contacteventlastupdated` | `fecha_relacion_persona_ubicaci` |
| `…contactfirsteventdate` | `fecha_primera_relacion` |

> `ind_unificacion` / `lote` → NULL en vistas reales. `latitud`/`longitud` suelen NULL en edf → R3 real = N/A.

### `edf_views.xpm_counterparties`

| Columna fuente | Columna BDM |
|----------------|-------------|
| `counterparties.val.counterpartyidnumber` | `id_buro_suscriptor` |

### Modo mock — columnas

Las tablas `bdm_stage.*` ya están en modelo BDM (mismas columnas lógicas: `cod_dw_persona_ubic`, `texto_ubicacion`, `complemento`, etc.). Las vistas `v_mock_*` solo proyectan esas columnas hacia los SPs mock.

---

## 4. JOINs (modo real)

```text
xpm.location                                      = xpm_location.id
xpm_location."location.val.contactinformations"   = xpm_location_val_contactinformations.id
xpm.counterparties                                = xpm_counterparties.id   (LEFT en reporte)
```

Implementación: `02_vistas_insumo_edf_views.sql` (`_strct`).

---

## 5. Prohibiciones (para no romper pruebas)

| No hacer | Por qué |
|----------|---------|
| Llamar `sp_unificacion_regla*` en corrida mock | Pisa / usa path real |
| Llamar `sp_unificacion_mock_*` en corrida real | Resultado en tabla mock; no valida gates reales |
| Validar C03/C04 sobre `unificacion_direccion_mock` como si fuera real | Son salidas distintas |
| Usar `bdm_stage.sp_unificacion_regla*` (legacy) | Fuera de esta entrega |
| Exigir todos los escenarios R1/R2 solo con muestra real pequeña | No aplica; usar mock para cobertura TC |

---

## 6. Histórico `ifr_data` (referencia)

El mapeo original (2026-08-19) usaba esquema QA `ifr_data` + JOIN con `relationalizelastupdate`.  
**Path de entrega actual = `edf_views` vía Data Sharing** (sección 1). Conservar `ifr_data` solo si el ambiente QA aún corre ese catálogo; no es el path de los SPs divididos en Bitbucket hoy.

---

*Corregido para pruebas QA de SPs reales + mock subdivididos · 2026-09-17*
