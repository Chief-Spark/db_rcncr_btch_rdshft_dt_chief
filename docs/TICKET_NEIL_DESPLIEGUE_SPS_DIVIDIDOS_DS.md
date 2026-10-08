# Ticket Neil — Despliegue SPs divididos (Data Sharing: real + mock)

**Para:** Neil  
**Tipo:** Ticket / solicitud de despliegue y habilitación QA  
**Tema:** Unificación — SPs divididos con Data Sharing (reales + **mock con nombre distinto**)  
**Fecha:** 2026-09-16

---

Hola Neil,

Necesitamos en **consumidor Reconocer** Unificación con **SPs divididos** + **Data Sharing**, en **dos familias de SPs** para que QA no las confunda:

| Modo | Nombres | Deploy |
|------|---------|--------|
| **Real + DS** | `bdm_datos.sp_unificacion_*` (**sin** `mock`) | **Pipeline** `_strct` → `_pgm` → `_dt` |
| **Mock + DS** | `bdm_datos.sp_unificacion_mock_*` (**con** `mock`) | Este ticket |

### Ambiente
| Pieza | Valor |
|-------|--------|
| Cluster / DB | Consumidor · **`dba_rncr_batch`** |
| Data Sharing | `ds_dba_rncr_batch.edf_views` → `bdm_tempo.v_xpm_*` |
| **No usar** | `bdm_stage.sp_unificacion_regla*` (legacy sin DS) |

### Repos / rama (código base real)
| Orden | Repo | Rama |
|-------|------|------|
| 1 | `db_rcncr_btch_rdshft_strct` | `feature/unificacion-edf-views` |
| 2 | `db_rcncr_btch_rdshft_pgm` | `feature/unificacion-edf-views` |
| 3 | `db_rcncr_btch_rdshft_dt` | `feature/unificacion-edf-views` |

---

### A) Datos reales + DS (Pipeline)
- Confirmar deploy de SPs **`sp_unificacion_*`**.
- Corrida: `run_unificacion_ejecucion_secuencial.sql`.
- Gates: **C03=0**, **C04=0**. R3 sin geo → N/A.

### B) Datos mock + DS — SPs con `mock` en el nombre
Los **15 SPs mock ya están en** `feature/unificacion-edf-views` (`_pgm`), espejo subdividido de los reales:

**R1:**  
`sp_unificacion_mock_r1_preparar_insumo`  
`sp_unificacion_mock_r1_esc1_ciiu10_mismo_texto_padre_lab_crr`  
`sp_unificacion_mock_r1_esc2_ciiu81_90_mismo_texto_padre_res_crr`  
`sp_unificacion_mock_r1_esc3_otros_ciiu_mayor_entidades_reportan`  
`sp_unificacion_mock_regla1`

**R2:**  
`sp_unificacion_mock_r2_preparar_insumo`  
`sp_unificacion_mock_r2_esc1_complemento_vacio_esc2_substring_complemento`  
`sp_unificacion_mock_r2_esc3_sin_nit_misma_nomenclatura`  
`sp_unificacion_mock_r2_esc4_diccionario_frecuencia_complemento`  
`sp_unificacion_mock_r2_esc5_nomenclatura_menor_nivel_pierde`  
`sp_unificacion_mock_r2_esc6_frecuencia_complemento_gana`  
`sp_unificacion_mock_r2_motor_nit_empates_nuevas_direcciones`  
`sp_unificacion_mock_regla2`

**R3:**  
`sp_unificacion_mock_r3_esc1_geo_misma_via_puerta_cercana`  
`sp_unificacion_mock_regla3`

Además en rama:
- DDL: `01b_ddl_unificacion_direccion_mock.sql` (`_strct`)
- Run: `run_unificacion_mock_ejecucion_secuencial.sql` (`_dt`)

Pedir:
- Deploy pipeline / Jenkins de los 3 repos (incluye mock).
- Seed mock visible al path DS + grants EXECUTE `sp_unificacion_mock_*`.
- Suite: **TC-R2-14** = 0 · **R3 mock** con geo.
- Corrida: `CALL bdm_datos.sp_unificacion_mock_regla1/2/3();` (nunca mezclar con los sin `mock`).

### Done
| Modo | Criterio |
|------|----------|
| Real | Pipeline OK + C03/C04 |
| Mock | Existen `sp_unificacion_mock_*` + TC-R2-14 = 0 + R3 mock OK |

Detalle: `Documentacion/MATRIZ_QA_SPS_DIVIDIDOS_DS.md`.

Gracias,  
Andrés
