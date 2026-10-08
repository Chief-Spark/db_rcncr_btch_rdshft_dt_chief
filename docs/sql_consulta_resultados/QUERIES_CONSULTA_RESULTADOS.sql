-- ============================================================================
-- QUERIES_CONSULTA_RESULTADOS.sql
-- Consulta de resultados DESPUÉS de ejecutar en Redshift:
--   deploy/redshift/SQL/run_unificacion_ejecucion_secuencial.sql
--   (TRUNCATE + CALL sp_unificacion_regla1/2/3)
--
-- Base      : dba_rncr_batch (datashare ds_dba_rncr_batch -> edf_views)
-- Salida    : bdm_datos.unificacion_direccion
--             (mock: bdm_datos.unificacion_direccion_mock)
-- Insumo    : bdm_tempo.v_xpm_*  (vistas sobre edf_views)
--
-- SEMÁNTICA DE LA TABLA DE SALIDA (confirmada en los SP):
--   cod_dw_persona_ubic         -> RPU HIJA (la absorbida)
--   cod_dw_direccion_unificada  -> RPU PADRE (la que gana).  OJO: es otro
--                                  cod_dw_persona_ubic, NO un
--                                  cod_dw_direccion_fisica.
--   unifica_atributos           -> 1 = Regla 1, 2 = Regla 2, 3 = Regla 3
--   fecha_unificacion           -> CURRENT_DATE (constante)
--   lote = 1, severidad = 1     -> hardcoded en todos los INSERT
--   usuario_bd                  -> CURRENT_USER (LEFT(...,30) en R2/R3)
--
-- LIMITACIONES A TENER PRESENTES AL LEER RESULTADOS:
--   * El escenario (ESC1..ESC6, MOTOR) NO se persiste: sólo la regla.
--     El bloque 6 lo reconstruye por condiciones.
--   * El orquestador hace TRUNCATE: la tabla sólo tiene la ÚLTIMA corrida.
--     lote/severidad/fecha son constantes -> no hay histórico ni trazabilidad
--     de corridas. Si necesitas comparar corridas, snapshot antes (bloque 0).
--   * v_xpm_relacion_persona_ubicacion expone ind_unificacion como NULL fijo,
--     así que R2 y R3 NO ven lo que absorbió R1: las 3 reglas corren sobre el
--     universo completo. Por eso el bloque 3 (hijas duplicadas) es obligatorio.
-- ============================================================================


-- ============================================================================
-- 0) SNAPSHOT PREVIO (opcional, antes de la siguiente corrida)
-- ============================================================================

-- Q0-SNAP: conservar la corrida actual antes de que el TRUNCATE la borre.
-- Redshift no soporta CREATE TABLE IF NOT EXISTS ... AS, por eso el DDL va
-- explicito.
CREATE TABLE IF NOT EXISTS bdm_tempo.unificacion_direccion_hist (
  cod_dw_persona_ubic        BIGINT,
  cod_dw_direccion_unificada BIGINT,
  unifica_atributos          INTEGER,
  fecha_unificacion          DATE,
  lote                       INTEGER,
  severidad                  INTEGER,
  usuario_bd                 VARCHAR(100),
  ts_snapshot                TIMESTAMP,
  etiqueta                   VARCHAR(40)
)
DISTSTYLE KEY
DISTKEY (cod_dw_persona_ubic)
SORTKEY (ts_snapshot, cod_dw_persona_ubic);

INSERT INTO bdm_tempo.unificacion_direccion_hist
SELECT u.*, CURRENT_TIMESTAMP, 'corrida_YYYYMMDD'
FROM bdm_datos.unificacion_direccion u;

-- Comparar dos corridas ya snapshoteadas
SELECT etiqueta, unifica_atributos AS regla, COUNT(*) AS filas,
       COUNT(DISTINCT cod_dw_persona_ubic) AS hijas
FROM bdm_tempo.unificacion_direccion_hist
GROUP BY 1, 2
ORDER BY 1, 2;


-- ============================================================================
-- 1) ¿CORRIÓ? — evidencia de ejecución y estado del objeto
-- ============================================================================

-- Q1-EXEC: trazas de los CALL (ajusta la ventana de días)
SELECT query_id, user_id, status, start_time, end_time,
       DATEDIFF(second, start_time, end_time) AS segundos,
       LEFT(query_text, 300) AS sql
FROM sys_query_history
WHERE query_text ILIKE '%sp_unificacion%'
  AND start_time >= DATEADD(day, -7, CURRENT_DATE)
ORDER BY start_time DESC
LIMIT 100;

-- Q1-SP: llamadas a stored procedures (incluye las internas por escenario)
SELECT query, label, starttime, endtime,
       DATEDIFF(second, starttime, endtime) AS segundos, aborted, from_sp_call
FROM svl_stored_proc_call
WHERE starttime >= DATEADD(day, -7, CURRENT_DATE)
ORDER BY starttime DESC
LIMIT 100;

-- Q1-SPMSG: mensajes/errores RAISE dentro de los SP (los orquestadores
--           re-lanzan 'sp_unificacion_reglaN failed: %')
SELECT query, recordtime, loglevel_text, message
FROM svl_stored_proc_messages
WHERE recordtime >= DATEADD(day, -7, CURRENT_DATE)
ORDER BY recordtime DESC
LIMIT 100;

-- Q1-TBL: filas físicas, tamaño y salud de la tabla de salida
SELECT "schema", "table", tbl_rows, size AS bloques_1mb, diststyle, sortkey1,
       unsorted AS pct_no_ordenado, stats_off, vacuum_sort_benefit
FROM svv_table_info
WHERE "schema" = 'bdm_datos'
  AND "table" IN ('unificacion_direccion', 'unificacion_direccion_mock');
-- Nota: los INSERT llegan desordenados sobre SORTKEY(cod_dw_persona_ubic).
--       Si pct_no_ordenado es alto: VACUUM + ANALYZE antes de explotar.

-- Q1-STG: los staging deben haber quedado borrados por los orquestadores.
--         Si aparecen filas aquí, la corrida abortó a mitad.
SELECT "schema", "table", tbl_rows
FROM svv_table_info
WHERE "schema" = 'bdm_tempo'
  AND ("table" LIKE 'stg_regla%' OR "table" LIKE 'stg_motor%')
ORDER BY "table";


-- ============================================================================
-- 2) RESULTADO DE NEGOCIO — los conteos que te van a pedir
-- ============================================================================

-- Q2-RESUMEN: resumen por regla (la query cabecera)
SELECT
  unifica_atributos AS regla,
  CASE unifica_atributos WHEN 1 THEN 'R1 tipo de uso (LAB/CRR/RES)'
                         WHEN 2 THEN 'R2 complemento'
                         WHEN 3 THEN 'R3 geo puerta cercana'
                         ELSE 'DESCONOCIDO' END AS descripcion,
  COUNT(*)                                    AS filas,
  COUNT(DISTINCT cod_dw_persona_ubic)         AS hijas_distintas,
  COUNT(DISTINCT cod_dw_direccion_unificada)  AS padres_distintos,
  MIN(fecha_unificacion)                      AS fecha,
  MIN(lote)                                   AS lote,
  MIN(severidad)                              AS severidad,
  MIN(usuario_bd)                             AS usuario
FROM bdm_datos.unificacion_direccion
GROUP BY 1, 2
ORDER BY 1;

-- Q2-TOTAL: total + personas impactadas + tasa de absorción sobre el universo
WITH unif AS (
  SELECT u.*, r.id_buro_persona
  FROM bdm_datos.unificacion_direccion u
  JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion r
    ON r.cod_dw_persona_ubic = u.cod_dw_persona_ubic
),
universo AS (
  SELECT COUNT(DISTINCT cod_dw_persona_ubic) AS rpus,
         COUNT(DISTINCT id_buro_persona)     AS personas
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion
)
SELECT
  (SELECT rpus     FROM universo)                        AS rpus_universo,
  (SELECT personas FROM universo)                        AS personas_universo,
  COUNT(*)                                               AS filas_unificacion,
  COUNT(DISTINCT cod_dw_persona_ubic)                    AS rpus_absorbidas,
  COUNT(DISTINCT id_buro_persona)                        AS personas_impactadas,
  ROUND(100.0 * COUNT(DISTINCT cod_dw_persona_ubic)
        / NULLIF((SELECT rpus FROM universo), 0), 2)     AS pct_rpus_absorbidas,
  (SELECT rpus FROM universo) - COUNT(DISTINCT cod_dw_persona_ubic) AS rpus_activos_post
FROM unif;

-- Q2-BASELINE: comparación contra la corrida de referencia
--              (docs/drill_down_volumenes.json, generado 2026-09-04)
WITH actual AS (
  SELECT unifica_atributos AS regla, COUNT(*) AS filas
  FROM bdm_datos.unificacion_direccion GROUP BY 1
),
esperado AS (
  SELECT 1 AS regla,     0 AS filas_baseline
  UNION ALL SELECT 2, 72448
  UNION ALL SELECT 3,     0
)
SELECT e.regla,
       e.filas_baseline,
       COALESCE(a.filas, 0) AS filas_actual,
       COALESCE(a.filas, 0) - e.filas_baseline AS delta,
       CASE WHEN COALESCE(a.filas, 0) = e.filas_baseline THEN 'IGUAL' ELSE 'DIFERENTE' END AS estado
FROM esperado e LEFT JOIN actual a USING (regla)
ORDER BY e.regla;

-- Q2-DIST: distribución de hijas por persona (detecta personas atípicas)
WITH x AS (
  SELECT r.id_buro_persona, COUNT(DISTINCT u.cod_dw_persona_ubic) AS hijas
  FROM bdm_datos.unificacion_direccion u
  JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion r
    ON r.cod_dw_persona_ubic = u.cod_dw_persona_ubic
  GROUP BY 1
)
SELECT hijas AS hijas_por_persona, COUNT(*) AS personas
FROM x GROUP BY 1 ORDER BY 1;

-- Q2-TOP: top personas por volumen absorbido (para revisión manual)
SELECT r.id_buro_persona,
       MAX(r.cod_pin_persona)                      AS cod_pin_persona,
       COUNT(*)                                    AS filas,
       COUNT(DISTINCT u.cod_dw_persona_ubic)       AS hijas,
       COUNT(DISTINCT u.cod_dw_direccion_unificada) AS padres,
       LISTAGG(DISTINCT u.unifica_atributos::VARCHAR, ',')
         WITHIN GROUP (ORDER BY u.unifica_atributos::VARCHAR) AS reglas
FROM bdm_datos.unificacion_direccion u
JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion r
  ON r.cod_dw_persona_ubic = u.cod_dw_persona_ubic
GROUP BY 1
ORDER BY hijas DESC, 1
LIMIT 50;


-- ============================================================================
-- 3) INTEGRIDAD — todas deben dar 0. Son los gates de la corrida.
-- ============================================================================

-- Q3-GATES: panel único PASSED/FAILED
WITH u AS (SELECT * FROM bdm_datos.unificacion_direccion),
rpu AS (SELECT cod_dw_persona_ubic, id_buro_persona
        FROM bdm_tempo.v_xpm_relacion_persona_ubicacion),
g AS (
  SELECT 'G1 nulos en claves' AS gate,
         (SELECT COUNT(*) FROM u
          WHERE cod_dw_persona_ubic IS NULL OR cod_dw_direccion_unificada IS NULL
             OR unifica_atributos IS NULL) AS violaciones
  UNION ALL
  SELECT 'G2 auto-unificacion (hija = padre)',
         (SELECT COUNT(*) FROM u WHERE cod_dw_persona_ubic = cod_dw_direccion_unificada)
  UNION ALL
  SELECT 'G3 hija con mas de un padre',
         (SELECT COUNT(*) FROM (
            SELECT cod_dw_persona_ubic FROM u
            GROUP BY 1 HAVING COUNT(DISTINCT cod_dw_direccion_unificada) > 1) t)
  UNION ALL
  SELECT 'G4 hija absorbida por mas de una regla',
         (SELECT COUNT(*) FROM (
            SELECT cod_dw_persona_ubic FROM u
            GROUP BY 1 HAVING COUNT(DISTINCT unifica_atributos) > 1) t)
  UNION ALL
  SELECT 'G5 filas duplicadas exactas',
         (SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM u
            GROUP BY cod_dw_persona_ubic, cod_dw_direccion_unificada, unifica_atributos
            HAVING COUNT(*) > 1) t)
  UNION ALL
  SELECT 'G6 cadenas (un padre es hija de otro)',
         (SELECT COUNT(DISTINCT a.cod_dw_direccion_unificada)
          FROM u a JOIN u b ON a.cod_dw_direccion_unificada = b.cod_dw_persona_ubic)
  UNION ALL
  SELECT 'G7 ciclos a->b y b->a',
         (SELECT COUNT(*) FROM u a JOIN u b
           ON a.cod_dw_persona_ubic = b.cod_dw_direccion_unificada
          AND a.cod_dw_direccion_unificada = b.cod_dw_persona_ubic)
  UNION ALL
  SELECT 'G8 hija inexistente en RPU',
         (SELECT COUNT(*) FROM u LEFT JOIN rpu h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
          WHERE h.cod_dw_persona_ubic IS NULL)
  UNION ALL
  SELECT 'G9 padre inexistente en RPU',
         (SELECT COUNT(*) FROM u LEFT JOIN rpu p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
          WHERE p.cod_dw_persona_ubic IS NULL)
  UNION ALL
  SELECT 'G10 padre e hija de personas distintas',
         (SELECT COUNT(*) FROM u
            JOIN rpu h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
            JOIN rpu p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
          WHERE h.id_buro_persona <> p.id_buro_persona)
  UNION ALL
  SELECT 'G11 regla fuera de {1,2,3}',
         (SELECT COUNT(*) FROM u WHERE unifica_atributos NOT IN (1, 2, 3))
)
SELECT gate, violaciones,
       CASE WHEN violaciones = 0 THEN 'PASSED' ELSE 'FAILED' END AS estado
FROM g ORDER BY gate;

-- Q3-G3-DET: detalle de las hijas con más de un padre (si G3/G4 fallan)
SELECT u.cod_dw_persona_ubic AS hija,
       COUNT(DISTINCT u.cod_dw_direccion_unificada) AS n_padres,
       LISTAGG(DISTINCT u.cod_dw_direccion_unificada::VARCHAR, ' | ')
         WITHIN GROUP (ORDER BY u.cod_dw_direccion_unificada::VARCHAR) AS padres,
       LISTAGG(DISTINCT u.unifica_atributos::VARCHAR, ',')
         WITHIN GROUP (ORDER BY u.unifica_atributos::VARCHAR) AS reglas
FROM bdm_datos.unificacion_direccion u
GROUP BY 1
HAVING COUNT(DISTINCT u.cod_dw_direccion_unificada) > 1
   OR  COUNT(DISTINCT u.unifica_atributos) > 1
ORDER BY n_padres DESC
LIMIT 200;

-- Q3-G6-DET: detalle de cadenas hija -> padre -> abuelo
SELECT b.cod_dw_persona_ubic   AS nieta,
       b.unifica_atributos     AS regla_nieta,
       a.cod_dw_persona_ubic   AS padre_intermedio,
       a.unifica_atributos     AS regla_intermedia,
       a.cod_dw_direccion_unificada AS abuelo
FROM bdm_datos.unificacion_direccion b
JOIN bdm_datos.unificacion_direccion a
  ON b.cod_dw_direccion_unificada = a.cod_dw_persona_ubic
ORDER BY 1
LIMIT 200;


-- ============================================================================
-- 4) VALIDACIÓN POR REGLA — comprobar que la salida respeta su propia lógica
--    (dejan de dar 0 => la regla hizo algo que no debía)
-- ============================================================================

-- Contexto reutilizable. ubi se deduplica a propósito: la vista
-- v_xpm_ubicacion_estandarizada es DISTINCT incluyendo cod_dw_tipo_ubicacion,
-- así que un cod_dw_ubic puede traer varias filas y el join se multiplicaría.

-- Q4-R1: la R1 exige misma persona, mismo texto+ciudad y TIPO DISTINTO
WITH ubi AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada GROUP BY 1, 2, 3
),
ctx AS (
  SELECT r.cod_dw_persona_ubic, r.id_buro_persona, r.cod_dw_tipo_ubicacion_dir,
         ubi.texto_ubicacion, ubi.cod_dw_ciudad
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  JOIN ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic
)
SELECT
  SUM(CASE WHEN h.cod_dw_tipo_ubicacion_dir = p.cod_dw_tipo_ubicacion_dir THEN 1 ELSE 0 END) AS v_mismo_tipo,
  SUM(CASE WHEN h.texto_ubicacion <> p.texto_ubicacion THEN 1 ELSE 0 END)                    AS v_texto_distinto,
  SUM(CASE WHEN h.cod_dw_ciudad <> p.cod_dw_ciudad THEN 1 ELSE 0 END)                        AS v_ciudad_distinta,
  SUM(CASE WHEN h.id_buro_persona <> p.id_buro_persona THEN 1 ELSE 0 END)                    AS v_persona_distinta,
  COUNT(*) AS filas_r1_evaluadas
FROM bdm_datos.unificacion_direccion u
JOIN ctx h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
JOIN ctx p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
WHERE u.unifica_atributos = 1;

-- Q4-R2: la R2 exige misma persona, mismo texto, MISMO tipo, mismo municipio,
--        y que el padre traiga complemento no vacío
WITH ubi AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada GROUP BY 1, 2, 3
),
ctx AS (
  SELECT r.cod_dw_persona_ubic, r.id_buro_persona, r.cod_dw_tipo_ubicacion_dir,
         ubi.texto_ubicacion, ubi.cod_dw_ciudad, df.complemento
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  JOIN ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic
  LEFT JOIN bdm_tempo.v_xpm_direccion_fisica df
    ON r.cod_dw_direccion_fisica = df.cod_dw_direccion_fisica
)
SELECT
  SUM(CASE WHEN h.cod_dw_tipo_ubicacion_dir <> p.cod_dw_tipo_ubicacion_dir THEN 1 ELSE 0 END) AS v_tipo_distinto,
  SUM(CASE WHEN h.texto_ubicacion <> p.texto_ubicacion THEN 1 ELSE 0 END)                     AS v_texto_distinto,
  SUM(CASE WHEN h.cod_dw_ciudad <> p.cod_dw_ciudad THEN 1 ELSE 0 END)                         AS v_municipio_distinto,
  SUM(CASE WHEN h.id_buro_persona <> p.id_buro_persona THEN 1 ELSE 0 END)                     AS v_persona_distinta,
  SUM(CASE WHEN p.complemento IS NULL OR LENGTH(TRIM(p.complemento)) = 0 THEN 1 ELSE 0 END)   AS v_padre_sin_complemento,
  COUNT(*) AS filas_r2_evaluadas
FROM bdm_datos.unificacion_direccion u
JOIN ctx h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
JOIN ctx p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
WHERE u.unifica_atributos = 2;

-- Q4-R3: la R3 exige mismo municipio, misma vía (tokens 1 y 2), puerta +-2,
--        lat/long presentes y padre con MÁS entidades reportando
WITH ubi AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad, latitud, longitud
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada GROUP BY 1, 2, 3, 4, 5
),
rep AS (
  SELECT cod_dw_persona_ubic, COUNT(DISTINCT id_buro_suscriptor) AS n_rep
  FROM bdm_tempo.v_xpm_reporte_relacion_persona_ubica GROUP BY 1
),
ctx AS (
  SELECT r.cod_dw_persona_ubic, r.id_buro_persona, ubi.texto_ubicacion,
         ubi.cod_dw_ciudad, ubi.latitud, ubi.longitud, COALESCE(rep.n_rep, 0) AS n_rep,
         SPLIT_PART(ubi.texto_ubicacion, ' ', 1) AS tk1,
         SPLIT_PART(ubi.texto_ubicacion, ' ', 2) AS tk2,
         CASE WHEN SPLIT_PART(ubi.texto_ubicacion, ' ', 3) ~ '^[0-9]+$'
              THEN SPLIT_PART(ubi.texto_ubicacion, ' ', 3)::INTEGER END AS tk3,
         CASE WHEN SPLIT_PART(ubi.texto_ubicacion, ' ', 4) ~ '^[0-9]+$'
              THEN SPLIT_PART(ubi.texto_ubicacion, ' ', 4)::INTEGER END AS tk4
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  JOIN ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic
  LEFT JOIN rep ON rep.cod_dw_persona_ubic = r.cod_dw_persona_ubic
)
SELECT
  SUM(CASE WHEN h.cod_dw_ciudad <> p.cod_dw_ciudad THEN 1 ELSE 0 END)   AS v_municipio_distinto,
  SUM(CASE WHEN h.id_buro_persona <> p.id_buro_persona THEN 1 ELSE 0 END) AS v_persona_distinta,
  SUM(CASE WHEN h.tk1 <> p.tk1 OR h.tk2 <> p.tk2 THEN 1 ELSE 0 END)     AS v_via_distinta,
  SUM(CASE WHEN h.latitud IS NULL OR p.latitud IS NULL THEN 1 ELSE 0 END) AS v_sin_geo,
  SUM(CASE WHEN p.n_rep <= h.n_rep THEN 1 ELSE 0 END)                   AS v_padre_no_mas_reportado,
  SUM(CASE WHEN NOT (ABS(h.tk3 - p.tk3) BETWEEN 1 AND 2
                  OR ABS(h.tk4 - p.tk4) BETWEEN 1 AND 2) THEN 1 ELSE 0 END) AS v_puerta_fuera_rango,
  COUNT(*) AS filas_r3_evaluadas
FROM bdm_datos.unificacion_direccion u
JOIN ctx h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
JOIN ctx p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
WHERE u.unifica_atributos = 3;

-- Q4-R3-GEO: por qué R3 puede dar 0 — cobertura de lat/long en el insumo
SELECT COUNT(*) AS rpus,
       SUM(CASE WHEN ubi.latitud IS NOT NULL THEN 1 ELSE 0 END)  AS con_latitud,
       SUM(CASE WHEN ubi.longitud IS NOT NULL THEN 1 ELSE 0 END) AS con_longitud,
       ROUND(100.0 * SUM(CASE WHEN ubi.latitud IS NOT NULL THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0), 4) AS pct_con_geo
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic;

-- Q4-R1-EMPATE: por qué R1 puede dar 0 — particiones sin ganador único.
--   (versión completa con los 3 escenarios: ver Q-R1-EMPATE en
--    deploy/redshift/SQL/validacion_unificacion_conteos.sql)
WITH ubi AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada GROUP BY 1, 2, 3
),
grupos AS (
  SELECT r.id_buro_persona, ubi.texto_ubicacion, ubi.cod_dw_ciudad
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  JOIN ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic
  GROUP BY 1, 2, 3
  HAVING COUNT(DISTINCT r.cod_dw_tipo_ubicacion_dir) > 1
)
SELECT COUNT(*) AS grupos_candidatos_r1,
       COUNT(DISTINCT id_buro_persona) AS personas_candidatas_r1,
       (SELECT COUNT(*) FROM bdm_datos.unificacion_direccion WHERE unifica_atributos = 1) AS salida_r1
FROM grupos;


-- ============================================================================
-- 5) DRILL-DOWN LEGIBLE PARA NEGOCIO / QA
-- ============================================================================

-- Q5-DETALLE: hija vs padre con dirección, tipo y complemento.
--   Filtra por regla o por persona descomentando el WHERE.
--   OJO: la query Q-R2-ESC1-EJ de validacion_unificacion_conteos.sql une
--   v_xpm_direccion_fisica.cod_dw_direccion_fisica = u.cod_dw_persona_ubic,
--   lo cual es incorrecto: hay que pasar por RPU como se hace aquí.
WITH ubi AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad, departamento, municipio, latitud, longitud
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada GROUP BY 1, 2, 3, 4, 5, 6, 7
),
rep AS (
  SELECT cod_dw_persona_ubic, COUNT(DISTINCT id_buro_suscriptor) AS n_rep
  FROM bdm_tempo.v_xpm_reporte_relacion_persona_ubica GROUP BY 1
),
ctx AS (
  SELECT r.cod_dw_persona_ubic, r.id_buro_persona, r.cod_pin_persona,
         t.descripcion_tipo_ubicacion_dir AS tipo,
         ubi.texto_ubicacion, ubi.municipio, ubi.cod_dw_ciudad,
         df.complemento, ubi.latitud, ubi.longitud,
         COALESCE(rep.n_rep, 0) AS n_rep, r.fecha_relacion_persona_ubicaci
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  JOIN ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic
  LEFT JOIN bdm_tempo.v_xpm_direccion_fisica df
    ON r.cod_dw_direccion_fisica = df.cod_dw_direccion_fisica
  LEFT JOIN bdm_datos.tipo_ubicacion_dir t
    ON r.cod_dw_tipo_ubicacion_dir = t.cod_dw_tipo_ubicacion_dir
  LEFT JOIN rep ON rep.cod_dw_persona_ubic = r.cod_dw_persona_ubic
)
SELECT
  u.unifica_atributos AS regla,
  h.id_buro_persona, h.cod_pin_persona,
  h.cod_dw_persona_ubic AS rpu_hija,
  h.tipo                AS tipo_hija,
  LEFT(h.texto_ubicacion, 80) AS dir_hija,
  h.complemento         AS comp_hija,
  h.n_rep               AS reportan_hija,
  p.cod_dw_persona_ubic AS rpu_padre,
  p.tipo                AS tipo_padre,
  LEFT(p.texto_ubicacion, 80) AS dir_padre,
  p.complemento         AS comp_padre,
  p.n_rep               AS reportan_padre,
  h.municipio, u.fecha_unificacion
FROM bdm_datos.unificacion_direccion u
JOIN ctx h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
JOIN ctx p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
WHERE 1 = 1
  -- AND u.unifica_atributos = 2
  -- AND h.id_buro_persona = -5233481187049215074
ORDER BY u.unifica_atributos, h.id_buro_persona, rpu_hija
LIMIT 200;

-- Q5-ACTIVOS: RPUs que quedan activos tras la corrida (lo que vería consumo)
SELECT COUNT(*) AS rpus_activos
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
LEFT JOIN bdm_datos.unificacion_direccion u
  ON u.cod_dw_persona_ubic = r.cod_dw_persona_ubic
WHERE u.cod_dw_persona_ubic IS NULL;

-- Q5-RPUXP: reportes por persona antes vs después (la métrica rpuxp del json)
WITH antes AS (
  SELECT COUNT(DISTINCT cod_dw_persona_ubic) AS rpus,
         COUNT(DISTINCT id_buro_persona)     AS personas
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion
),
despues AS (
  SELECT COUNT(DISTINCT r.cod_dw_persona_ubic) AS rpus,
         COUNT(DISTINCT r.id_buro_persona)     AS personas
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  LEFT JOIN bdm_datos.unificacion_direccion u
    ON u.cod_dw_persona_ubic = r.cod_dw_persona_ubic
  WHERE u.cod_dw_persona_ubic IS NULL
)
SELECT a.personas AS personas_antes, a.rpus AS rpus_antes,
       ROUND(a.rpus::DECIMAL / NULLIF(a.personas, 0), 2) AS rpuxp_antes,
       d.personas AS personas_despues, d.rpus AS rpus_despues,
       ROUND(d.rpus::DECIMAL / NULLIF(d.personas, 0), 2) AS rpuxp_despues
FROM antes a CROSS JOIN despues d;


-- ============================================================================
-- 6) ¿QUÉ ESCENARIO FUE? — reconstrucción (la tabla no lo guarda)
-- ============================================================================

-- Q6-ESC-R2: clasifica cada par de R2 por la condición que lo explica.
--   Es una atribución a posteriori, no la del motor: si un par cumple varias
--   condiciones se le asigna la primera en el orden de ejecución real
--   (ESC1 -> ESC2 -> ESC3..6). Sirve para repartir el volumen por escenario.
WITH ubi AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada GROUP BY 1, 2, 3
),
ctx AS (
  SELECT r.cod_dw_persona_ubic, r.id_buro_persona, r.cod_dw_tipo_ubicacion_dir,
         r.cod_tipo_ident_fte, ubi.texto_ubicacion, ubi.cod_dw_ciudad, df.complemento
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  JOIN ubi ON r.cod_dw_ubic = ubi.cod_dw_ubic
  LEFT JOIN bdm_tempo.v_xpm_direccion_fisica df
    ON r.cod_dw_direccion_fisica = df.cod_dw_direccion_fisica
),
pares AS (
  SELECT u.cod_dw_persona_ubic, u.cod_dw_direccion_unificada,
         TRIM(COALESCE(h.complemento, '')) AS comp_h,
         TRIM(COALESCE(p.complemento, '')) AS comp_p
  FROM bdm_datos.unificacion_direccion u
  JOIN ctx h ON h.cod_dw_persona_ubic = u.cod_dw_persona_ubic
  JOIN ctx p ON p.cod_dw_persona_ubic = u.cod_dw_direccion_unificada
  WHERE u.unifica_atributos = 2
)
SELECT
  CASE
    WHEN LENGTH(comp_h) = 0 AND LENGTH(comp_p) > 0                 THEN 'ESC1 hija sin complemento'
    WHEN LENGTH(comp_h) > 0 AND comp_p LIKE '%' || comp_h || '%'
         AND comp_h <> comp_p                                      THEN 'ESC2 complemento contenido'
    WHEN LEFT(comp_h, 2) = LEFT(comp_p, 2) AND comp_h <> comp_p    THEN 'ESC3-5 misma nomenclatura, nro distinto'
    ELSE 'ESC4-6 / MOTOR u otro desempate'
  END AS escenario_atribuido,
  COUNT(*) AS filas,
  COUNT(DISTINCT cod_dw_persona_ubic) AS hijas
FROM pares
GROUP BY 1
ORDER BY filas DESC;

-- Q6-ESC-R1: reparto de R1 por escenario vía CIIU de la persona
WITH ctx AS (
  SELECT r.cod_dw_persona_ubic,
         COALESCE(c.cod_act_econo_ciiu_fte, '') AS ciiu
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion r
  LEFT JOIN bdm_tempo.v_xpm_ciiu_persona c ON r.id_buro_persona = c.id_buro_persona
)
SELECT CASE WHEN ctx.ciiu = '10' THEN 'ESC1 ciiu 10'
            WHEN ctx.ciiu IN ('81', '82', '90') THEN 'ESC2 ciiu 81/82/90'
            ELSE 'ESC3 resto' END AS escenario_atribuido,
       COUNT(*) AS filas
FROM bdm_datos.unificacion_direccion u
JOIN ctx ON ctx.cod_dw_persona_ubic = u.cod_dw_persona_ubic
WHERE u.unifica_atributos = 1
GROUP BY 1 ORDER BY 1;


-- ============================================================================
-- 7) MOCK — misma batería contra la salida mock
--    Cambia bdm_datos.unificacion_direccion por
--    bdm_datos.unificacion_direccion_mock y las vistas v_xpm_* por v_mock_*.
--    Los gates funcionales de QA mock ya están en
--    docs/sql_qa_redshift_mock/03_validar_gates_mock_qa.sql
-- ============================================================================

-- Q7-MOCK-RESUMEN
SELECT unifica_atributos AS regla, COUNT(*) AS filas,
       COUNT(DISTINCT cod_dw_persona_ubic) AS hijas,
       COUNT(DISTINCT cod_dw_direccion_unificada) AS padres,
       MIN(fecha_unificacion) AS fecha, MIN(usuario_bd) AS usuario
FROM bdm_datos.unificacion_direccion_mock
GROUP BY 1 ORDER BY 1;

-- Q7-REAL-VS-MOCK
SELECT 'real' AS origen, unifica_atributos AS regla, COUNT(*) AS filas
FROM bdm_datos.unificacion_direccion GROUP BY 1, 2
UNION ALL
SELECT 'mock', unifica_atributos, COUNT(*)
FROM bdm_datos.unificacion_direccion_mock GROUP BY 1, 2
ORDER BY regla, origen;
