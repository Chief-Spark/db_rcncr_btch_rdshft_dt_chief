# Matriz QA — SPs divididos + Data Sharing

**Objetivo:** Unificación con **SPs divididos por escenario** siempre sobre **Data Sharing**, en dos modos de dato (mock y real).  
**Despliegue:** pipeline consumidor (SPs **reales**) → ticket Neil (SPs **`_mock_`** + seed).

**Fuera de alcance aquí:** Ordenamiento · path legacy `bdm_stage` sin DS.

---

## 0. Convención de nombres (para no confundir)

| Modo | Prefijo | Ejemplo orquestador |
|------|---------|---------------------|
| **Real + DS** | `sp_unificacion_*` | `bdm_datos.sp_unificacion_regla2()` |
| **Mock + DS** | `sp_unificacion_mock_*` | `bdm_datos.sp_unificacion_mock_regla2()` |

Misma lógica / mismos escenarios; **siempre** el token `mock` en el nombre del SP de laboratorio.

---

## 1. Matriz de pruebas (lo que pide QA)

| # | Escenario de prueba | Data Sharing | SPs | Dónde | Cómo llega el deploy |
|---|---------------------|--------------|-----|-------|----------------------|
| **1** | **SPs divididos + DS** | Sí | `sp_unificacion_r*_esc*` + `sp_unificacion_regla1/2/3` | Consumidor · `dba_rncr_batch` | Pipeline `_strct` → `_pgm` → `_dt` |
| **2** | **Datos mock + DS** | Sí | **`sp_unificacion_mock_*`** (paralelos) | Mismo consumidor | Ticket Neil (deploy mock + seed) |
| **3** | **Datos reales + DS** | Sí | `sp_unificacion_*` (**sin** `mock`) | Mismo consumidor | **Desplegado — Pipeline** |

**Regla de oro:** QA nunca mezcla en la misma corrida `sp_unificacion_*` con `sp_unificacion_mock_*`.  
No usar legacy `bdm_stage.sp_unificacion_regla*`.

---

## 2. Stack técnico

| Pieza | Real + DS | Mock + DS |
|-------|-----------|-----------|
| Cluster / DB | Consumidor · `dba_rncr_batch` | Igual |
| Lectura | `v_xpm_*` ← `edf_views` | Path DS + seed mock acordado |
| Schema SPs | `bdm_datos` | `bdm_datos` |
| Nombres SP | `sp_unificacion_*` | `sp_unificacion_mock_*` |
| Resultado | `bdm_datos.unificacion_direccion` | Tabla/salida mock acordada (o misma con filtro IDs mock) |

### SPs reales (Pipeline)

| Regla | Procedimientos |
|-------|----------------|
| **R1** | `sp_unificacion_r1_preparar_insumo` · `sp_unificacion_r1_esc1_ciiu10_mismo_texto_padre_lab_crr` · `sp_unificacion_r1_esc2_ciiu81_90_mismo_texto_padre_res_crr` · `sp_unificacion_r1_esc3_otros_ciiu_mayor_entidades_reportan` · `sp_unificacion_regla1` |
| **R2** | `sp_unificacion_r2_preparar_insumo` · `…_esc1_…` · `…_esc3_…` · `…_esc4_…` · `…_esc5_…` · `…_esc6_…` · `…_motor_…` · `sp_unificacion_regla2` |
| **R3** | `sp_unificacion_r3_esc1_geo_misma_via_puerta_cercana` · `sp_unificacion_regla3` |

### SPs mock (mismos escenarios, con `mock` en el nombre)

| Regla | Procedimientos |
|-------|----------------|
| **R1** | `sp_unificacion_mock_r1_preparar_insumo` · `sp_unificacion_mock_r1_esc1_ciiu10_mismo_texto_padre_lab_crr` · `sp_unificacion_mock_r1_esc2_ciiu81_90_mismo_texto_padre_res_crr` · `sp_unificacion_mock_r1_esc3_otros_ciiu_mayor_entidades_reportan` · `sp_unificacion_mock_regla1` |
| **R2** | `sp_unificacion_mock_r2_preparar_insumo` · `sp_unificacion_mock_r2_esc1_complemento_vacio_esc2_substring_complemento` · `sp_unificacion_mock_r2_esc3_sin_nit_misma_nomenclatura` · `sp_unificacion_mock_r2_esc4_diccionario_frecuencia_complemento` · `sp_unificacion_mock_r2_esc5_nomenclatura_menor_nivel_pierde` · `sp_unificacion_mock_r2_esc6_frecuencia_complemento_gana` · `sp_unificacion_mock_r2_motor_nit_empates_nuevas_direcciones` · `sp_unificacion_mock_regla2` |
| **R3** | `sp_unificacion_mock_r3_esc1_geo_misma_via_puerta_cercana` · `sp_unificacion_mock_regla3` |

Corrida real: `run_unificacion_ejecucion_secuencial.sql`  
Corrida mock: `run_unificacion_mock_ejecucion_secuencial.sql` (a crear / ticket Neil).

---

## 3. Cómo distinguir mock vs real (mismo DS)

| | **Mock + DS** | **Real + DS (Pipeline)** |
|--|---------------|---------------------------|
| **SPs** | `sp_unificacion_mock_*` | `sp_unificacion_*` |
| **Insumo** | `bdm_tempo.v_mock_*` ← **`bdm_stage`** (seed TC) | `bdm_tempo.v_xpm_*` ← **`edf_views`** (DS) |
| **Catálogos** | `bdm_stage.nomenclatura` / diccionario / tipo_ubic | `bdm_datos.*` |
| **Salida** | `bdm_datos.unificacion_direccion_mock` | `bdm_datos.unificacion_direccion` |
| **CALL** | `sp_unificacion_mock_regla1/2/3` | `sp_unificacion_regla1/2/3` |

---

## 4. Orden operativo

```
1) Pipeline: SPs reales sp_unificacion_* + vistas DS
       ↓
2) QA Modo REAL + DS  → CALL sp_unificacion_regla1/2/3
       ↓
3) Ticket Neil: desplegar sp_unificacion_mock_* + seed mock + DS
       ↓
4) QA Modo MOCK + DS → CALL sp_unificacion_mock_regla1/2/3
```

---

## 5. Prompts QA (copiar uno por corrida)

### A — Datos reales + DS (Pipeline) — SPs **sin** mock

```
Proceso: UNIFICACIÓN — SPs divididos + Data Sharing + datos REALES.
Ambiente: consumidor Reconocer / dba_rncr_batch (pipeline).
Fuente: bdm_tempo.v_xpm_* (ds_dba_rncr_batch.edf_views).
SPs SOLO: bdm_datos.sp_unificacion_regla1/2/3 (y sp_unificacion_r*_esc*).
PROHIBIDO: sp_unificacion_mock_* y bdm_stage legacy.
Validar: unifica_atributos, C03=0, C04=0. R3 sin geo → N/A.
```

### B — Datos mock + DS — SPs **con** mock en el nombre

```
Proceso: UNIFICACIÓN — SPs divididos + Data Sharing + datos MOCK.
Ambiente: consumidor dba_rncr_batch.
SPs SOLO: bdm_datos.sp_unificacion_mock_regla1/2/3 (y sp_unificacion_mock_r*_esc*).
PROHIBIDO: sp_unificacion_regla* (sin mock) y bdm_stage legacy.
TC-R2-14: Esc4 HAVING COUNT(*)=1 → 0. R3 mock con geo: sí.
```

---

## 6. Ticket Neil

Ver: [`TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md`](TICKET_NEIL_DESPLIEGUE_SPS_DIVIDIDOS_DS.md)

---

## 7. Estado actual vs gap

| Ítem | Estado |
|------|--------|
| SPs reales `sp_unificacion_*` | Listo en `_pgm` |
| SPs mock `sp_unificacion_mock_*` (15, subdivididos) | **Generados** — `sql/unificacion_mock_por_escenario/` + `_pgm` deploy |
| DDL `unificacion_direccion_mock` | `01b_ddl_unificacion_direccion_mock.sql` en `_strct` |
| Run mock | `run_unificacion_mock_ejecucion_secuencial.sql` en `_dt` |
| Regenerar | `py -3 tools/gen_unificacion_mock_sps.py` |
| Vistas DS `v_xpm_*` | Listo `_strct` |
| Pipeline real + DS | Confirmar deploy |
| Seed mock + DS + grants | Ticket Neil |

---

*Relacionado:* `ENTREGA_QA_UNIFICACION.md` · `PROMPT_PRUEBAS_QA_REAL_VS_MOCK.md`
