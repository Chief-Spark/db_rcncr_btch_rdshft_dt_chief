# Entrega QA — Unificación (datos reales + mock)

**Alcance de esta entrega:** solo **Unificación de direcciones** (R1 → R2 → R3).  
**Fuera de alcance aquí:** Ordenamiento / scoring → ver [`ENTREGA_QA_ORDENAMIENTO.md`](ENTREGA_QA_ORDENAMIENTO.md).

**Fecha:** 2026-09-16  
**Rama Bitbucket (3 repos):** `feature/unificacion-edf-views`  
**Orden deploy:** `_strct` → `_pgm` → `_dt`

> **Matriz QA vigente (SPs divididos + DS):** [`MATRIZ_QA_SPS_DIVIDIDOS_DS.md`](MATRIZ_QA_SPS_DIVIDIDOS_DS.md)  
> **Tablas / columnas (reales + mock):** [`MAPEO_QA_IFR_TABLAS_COLUMNAS.md`](MAPEO_QA_IFR_TABLAS_COLUMNAS.md)  
> **Ticket Neil (real + mock con DS):** [`TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md`](TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md)

---

## 1. Qué deben configurar en el prompt

Hay **dos modos** + **Data Sharing**. Elegir **uno** por corrida. Los SPs de mock llevan **`mock` en el nombre** para no confundirlos con reales.

| | Modo A — Datos reales + DS | Modo B — Datos mock + DS |
|--|----------------------------|---------------------------|
| **Para qué** | Cierre / gates (Pipeline) | Suite TC (empates, R3 geo) |
| **DB** | Consumidor Reconocer · `dba_rncr_batch` | **Mismo** consumidor · `dba_rncr_batch` |
| **Data Sharing** | Sí (`edf_views` → `v_xpm_*`) | Sí (seed mock + DS) |
| **SPs** | `sp_unificacion_*` (**sin** mock) | `sp_unificacion_mock_*` (**con** mock) |
| **R3** | **N/A** sin lat/long | **Sí** con mock geo |

**Legacy (no usar):** `bdm_stage.sp_unificacion_regla*` sin DS.  
**Nunca mezclar** en una corrida: `sp_unificacion_regla2` con `sp_unificacion_mock_regla2`.

---

## 2. Modo A — Datos reales (Unificación)

### 2.1 Tablas / esquemas fuente

| Objeto | Rol |
|--------|-----|
| `ds_dba_rncr_batch.edf_views.xpm` | Persona / pin |
| `ds_dba_rncr_batch.edf_views.xpm_location` | Ubicación |
| `ds_dba_rncr_batch.edf_views.xpm_location_val_contactinformations` | Dirección / `standardized*` |
| `ds_dba_rncr_batch.edf_views.xpm_counterparties` | Entidades reportantes |

### 2.2 Vistas que usan los SPs (usar estas, no XPM crudo)

- `bdm_tempo.v_xpm_relacion_persona_ubicacion`
- `bdm_tempo.v_xpm_ubicacion_estandarizada`
- `bdm_tempo.v_xpm_direccion_fisica`
- `bdm_tempo.v_xpm_reporte_relacion_persona_ubica`
- `bdm_tempo.v_xpm_ciiu_persona`
- `bdm_tempo.v_xpm_contacto_direccion`

### 2.3 Catálogos y salida

| Objeto | Rol |
|--------|-----|
| `bdm_datos.nomenclatura` | Catálogo |
| `bdm_datos.tipo_ubicacion_dir` | Catálogo |
| `bdm_datos.diccionario_complementos` | Catálogo R2 |
| `bdm_tempo.stg_regla*` | Staging temporal |
| **`bdm_datos.unificacion_direccion`** | **Resultado Unificación** |

### 2.4 Stored procedures (nombres exactos)

```sql
CALL bdm_datos.sp_unificacion_regla1();
CALL bdm_datos.sp_unificacion_regla2();
CALL bdm_datos.sp_unificacion_regla3();  -- sin geo → 0 filas; marcar N/A
```

Detalle por escenario (repo `_pgm`):

| Regla | Procedimientos |
|-------|----------------|
| **R1** | `sp_unificacion_r1_preparar_insumo` · `sp_unificacion_r1_esc1_ciiu10_mismo_texto_padre_lab_crr` · `sp_unificacion_r1_esc2_ciiu81_90_mismo_texto_padre_res_crr` · `sp_unificacion_r1_esc3_otros_ciiu_mayor_entidades_reportan` · `sp_unificacion_regla1` |
| **R2** | `sp_unificacion_r2_preparar_insumo` · `sp_unificacion_r2_esc1_complemento_vacio_esc2_substring_complemento` · `sp_unificacion_r2_esc3_sin_nit_misma_nomenclatura` · `sp_unificacion_r2_esc4_diccionario_frecuencia_complemento` · `sp_unificacion_r2_esc5_nomenclatura_menor_nivel_pierde` · `sp_unificacion_r2_esc6_frecuencia_complemento_gana` · `sp_unificacion_r2_motor_nit_empates_nuevas_direcciones` · `sp_unificacion_regla2` |
| **R3** | `sp_unificacion_r3_esc1_geo_misma_via_puerta_cercana` · `sp_unificacion_regla3` |

Script de corrida en `_dt`: `run_unificacion_ejecucion_secuencial.sql`

### 2.5 Gates de Unificación (modo real)

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
| `unifica_atributos = 2` (R2) | > 0 |
| C03 (hijo sin padre) | **0** |
| C04 (autoreferencia) | **0** |
| R1 | Puede ser 0 (empates / poca variedad) |
| R3 | **0 = N/A** sin lat/long — **no es FAIL** |

**No usar** en modo real: `perf_persona_meta` ni `TC-R1-01…TC-R2-14` con `scenario_code`.

**Nota:** la muestra real es pequeña; es muy probable que no existan filas para **todos** los escenarios R1/R2. Eso no invalida los SPs.

Evidencia DEV (referencia): R2 = 72.448 · C03/C04 = 0 · R1/R3 = 0.

---

## 3. Modo B — Datos mock + DS (SPs con `mock` en el nombre)

### 3.1 Tablas / vistas (usar estas en pruebas mock)

| Tipo | Objetos |
|------|---------|
| **Fuente seed** | `bdm_stage.relacion_persona_ubicacion` · `ubicacion_estandarizada` · `direccion_fisica` · `reporte_relacion_persona_ubica` · `ciiu_persona` · `perf_persona_meta` |
| **Vistas SPs** | `bdm_tempo.v_mock_relacion_persona_ubicacion` · `v_mock_ubicacion_estandarizada` · `v_mock_direccion_fisica` · `v_mock_reporte_relacion_persona_ubica` · `v_mock_ciiu_persona` |
| **Catálogos** | `bdm_stage.tipo_ubicacion_dir` · `nomenclatura` · `diccionario_complementos` |
| **Staging** | `bdm_tempo.stg_mock_regla*` |
| **Salida** | **`bdm_datos.unificacion_direccion_mock`** |

| Pieza | Valor |
|-------|--------|
| Cluster / DB | Consumidor Reconocer · `dba_rncr_batch` (o productor con seed) |
| SPs | **`bdm_datos.sp_unificacion_mock_*`** (nunca los sin `mock`) |
| Orquestadores | `sp_unificacion_mock_regla1` · `…_mock_regla2` · `…_mock_regla3` |
| Run | `run_unificacion_mock_ejecucion_secuencial.sql` |

**Mapeo tablas completo:** [`MAPEO_QA_IFR_TABLAS_COLUMNAS.md`](MAPEO_QA_IFR_TABLAS_COLUMNAS.md)  
**Ticket Neil:** [`TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md`](TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md)

### R2 — TC-R2-14 (`R2_EMPATE`)
1. SP mock Esc4 con `HAVING COUNT(*) = 1`.
2. Seed / patch suite TC en `bdm_stage`.
3. `CALL bdm_datos.sp_unificacion_mock_regla2();`
4. Esperado TC-R2-14: **0**.

### R3 — mock (sí se prueba)
1. Sembrar geo mock (`latitud`/`longitud` en `bdm_stage.ubicacion_estandarizada`).
2. `CALL bdm_datos.sp_unificacion_mock_regla3();`

**No llamar** `sp_unificacion_regla*` (sin mock) en esta corrida.  
**No validar** gates reales sobre `unificacion_direccion` en corrida mock.

---

## 4. Prompts listos (copiar)

### Prompt Unificación — datos reales + DS

```
Proceso: UNIFICACIÓN (R1→R2→R3) datos REALES + Data Sharing. No Ordenamiento.
Ambiente: consumidor / dba_rncr_batch (pipeline).
Fuente: bdm_tempo.v_xpm_* (ds_dba_rncr_batch.edf_views).
SPs SOLO sin mock: CALL bdm_datos.sp_unificacion_regla1(); regla2(); regla3();
PROHIBIDO: sp_unificacion_mock_* y bdm_stage.
Validar: unifica_atributos, C03=0, C04=0. R3 sin geo → N/A.
```

### Prompt Unificación — datos mock + DS

```
Proceso: UNIFICACIÓN suite TC datos MOCK + Data Sharing. No Ordenamiento.
Ambiente: consumidor / dba_rncr_batch.
SPs SOLO con mock: CALL bdm_datos.sp_unificacion_mock_regla1(); mock_regla2(); mock_regla3();
PROHIBIDO: sp_unificacion_regla* (sin mock) y bdm_stage legacy.
TC-R2-14 = 0. R3 mock con geo: sí.
```

---

## 5. Estado en Bitbucket

| Ítem Unificación | Estado |
|------------------|--------|
| Vistas `v_xpm_*` (`_strct`) | En `feature/unificacion-edf-views` |
| 15 SPs reales `sp_unificacion_*` (`_pgm`) | En rama |
| SPs mock `sp_unificacion_mock_*` | **Generados** (15 SPs espejo + staging/salida `_mock`) |
| `run_` + validación (`_dt`) | En rama |
| Deploy Jenkins QA consumidor (real) | Pendiente pipeline |

---

*Matriz:* `MATRIZ_QA_SPS_DIVIDIDOS_DS.md` · *Ticket:* `TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md`
