# Evidencias — Revalidación QA DEV (pre-push)
Fecha: 2026-09-17T16:42:14

**Overall:** `PASS`
**Push permitido:** `True`

## Estático (separación mock vs real)
```json
[
  {
    "id": "STATIC_real_no_mock_sources",
    "ok": true,
    "bad": []
  },
  {
    "id": "STATIC_mock_no_real_ds_body",
    "ok": true,
    "bad": []
  },
  {
    "id": "STATIC_mock_prep_reads_v_mock",
    "ok": true,
    "bad": []
  }
]
```

## Reales (`productor_bdm_datos`) — `PASS`
```json
[
  {
    "id": "B02_por_regla",
    "rows": [
      {
        "unifica_atributos": 2,
        "n": 72448
      }
    ],
    "ok": true,
    "note": "informativo"
  },
  {
    "id": "PARITY_R2_COUNT",
    "expected": 72448,
    "actual": 72448,
    "ok": true
  },
  {
    "id": "C03_hijos_sin_padre",
    "expected": 0,
    "actual": 0,
    "ok": true
  },
  {
    "id": "C04_autoreferencia",
    "expected": 0,
    "actual": 0,
    "ok": true
  },
  {
    "id": "DEPLOY_sp_unificacion_regla1",
    "ok": true,
    "actual": "present"
  },
  {
    "id": "DEPLOY_sp_unificacion_regla2",
    "ok": true,
    "actual": "present"
  },
  {
    "id": "DEPLOY_sp_unificacion_regla3",
    "ok": true,
    "actual": "present"
  },
  {
    "id": "DEPLOY_mock_ops_optional",
    "ok": true,
    "actual": [],
    "note": "informativo"
  }
]
```

## Mock TC (productor DEV / bdm_stage) — `PASS`
Preflight: `[{'unifica_atributos': 1, 'n': 3204}, {'unifica_atributos': 2, 'n': 6002}, {'unifica_atributos': 3, 'n': 13}]`
Casos: 23 · Fallidos: 0 · OK: TC-R1-01, TC-R1-02, TC-R1-03, TC-R1-04, TC-R1-05, TC-R1-06, TC-R1-07, TC-R1-08, TC-R2-01, TC-R2-02, TC-R2-03, TC-R2-04, TC-R2-05, TC-R2-06, TC-R2-07, TC-R2-08, TC-R2-09, TC-R2-10, TC-R2-11, TC-R2-12, TC-R2-13, TC-R2-14, TC-G-07
```json
[
  {
    "id": "TC-R1-01",
    "desc": "CIIU 10 escenario R1_ESC1: padre LAB",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-02",
    "desc": "CIIU 81/82/90: padre RES/CRR",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-03",
    "desc": "Otros CIIU: padre por max entidades",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-04",
    "desc": "Hijas R1 con ind_unificacion = 1",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-05",
    "desc": "Trazabilidad R1 completa",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-06",
    "desc": "Bloqueadas excluidas de R1",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-07",
    "desc": "Segmentación CIIU sin solapamiento",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R1-08",
    "desc": "R1_EMPATE sin unificación",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-01",
    "desc": "Esc1: gana complemento informado",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-02",
    "desc": "Esc2: gana complemento más completo",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-03",
    "desc": "Esc3 sin NIT: no crea dirección nueva",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-04",
    "desc": "Esc3 NIT: crea dirección generada_enriquecida=1",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-05",
    "desc": "Esc4: personas sin unificación R2",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-06",
    "desc": "Esc5 motor: dirección combinada",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-07",
    "desc": "Esc6 motor: dirección combinada",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-08",
    "desc": "Motor R2 con generada_enriquecida=1",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-09",
    "desc": "Sin huérfanas generada_enriquecida=1",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-10",
    "desc": "Padre nunca hijo en R2",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-11",
    "desc": "Cardinalidad 1 padre por hija R2",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-12",
    "desc": "Complementos generados sin dobles espacios",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-13",
    "desc": "R2_ESC4_DIC: personas sin unificación",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-R2-14",
    "desc": "R2_EMPATE: personas con absorción R2",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  },
  {
    "id": "TC-G-07",
    "desc": "Aislamiento intra-persona",
    "violaciones": 0,
    "ok": true,
    "expected": 0
  }
]
```

## Regla
No hacer push a la rama hasta `push_allowed = true` (ambos paths PASS).
