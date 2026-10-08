-- ============================================================
-- 00_drill_down_validaciones.sql
-- Queries de validación por escenario — Reconocer DEV / edf_views
-- Ejecutar en dba_rncr_batch tras desplegar vistas + corrida unificación
-- IDs de query referenciados en MAPA_UNIFICACION_EDF_VIEWS_NEGOCIO.xlsx
-- ============================================================

-- Q-UNIV-01: Universo RPUs vs personas
SELECT
  COUNT(*)::BIGINT AS rpus,
  COUNT(DISTINCT id_buro_persona)::BIGINT AS personas,
  COUNT(DISTINCT cod_dw_ubic)::BIGINT AS ubicaciones
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion;

-- Q-UNIV-02: Contacttype crudo
SELECT
  NULLIF(TRIM(ci."location.val.contactinformations.val.contacttype"::VARCHAR), '') AS ct,
  COUNT(*)::BIGINT AS n
FROM ds_dba_rncr_batch.edf_views.xpm xpm
JOIN ds_dba_rncr_batch.edf_views.xpm_location loc ON xpm.location = loc.id
JOIN ds_dba_rncr_batch.edf_views.xpm_location_val_contactinformations ci
  ON loc."location.val.contactinformations" = ci.id
WHERE NULLIF(TRIM(ci."location.val.contactinformations.val.contacttype"::VARCHAR), '') IN ('1','2','3','7','8')
GROUP BY 1 ORDER BY n DESC;

-- Q-R1-00: Salida R1
SELECT COUNT(*)::BIGINT AS unificaciones_r1 FROM bdm_datos.unificacion_direccion WHERE unifica_atributos = 1;

-- Q-R1-CAND: Personas y RPUs entrada R1 (ubi deduplicada, DISTINCT RPU)
WITH ubi1 AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada
  GROUP BY 1, 2, 3
),
grupos AS (
  SELECT rpu.id_buro_persona, ubi.texto_ubicacion, ubi.cod_dw_ciudad
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
  JOIN ubi1 ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
  GROUP BY 1, 2, 3
  HAVING COUNT(DISTINCT rpu.cod_dw_tipo_ubicacion_dir) > 1
)
SELECT
  (SELECT COUNT(*) FROM grupos)::BIGINT AS grupos_multitipo,
  (SELECT COUNT(DISTINCT id_buro_persona) FROM grupos)::BIGINT AS personas,
  (SELECT COUNT(DISTINCT rpu.cod_dw_persona_ubic)::BIGINT
   FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
   JOIN ubi1 ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
   JOIN grupos g ON rpu.id_buro_persona = g.id_buro_persona
     AND ubi.texto_ubicacion = g.texto_ubicacion
     AND ubi.cod_dw_ciudad = g.cod_dw_ciudad
  ) AS rpus_en_grupos;

-- Q-R1-DIR-RESUMEN: Personas que entran a R1 (conteo calles y RPUs)
WITH ubi1 AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada
  GROUP BY 1, 2, 3
),
grupos AS (
  SELECT rpu.id_buro_persona, ubi.texto_ubicacion, ubi.cod_dw_ciudad
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
  JOIN ubi1 ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
  GROUP BY 1, 2, 3
  HAVING COUNT(DISTINCT rpu.cod_dw_tipo_ubicacion_dir) > 1
)
SELECT
  g.id_buro_persona,
  MAX(rpu.cod_pin_persona) AS cod_pin_persona,
  COUNT(DISTINCT g.texto_ubicacion || '|' || g.cod_dw_ciudad::VARCHAR) AS calles_r1,
  COUNT(DISTINCT rpu.cod_dw_persona_ubic) AS rpus_r1
FROM grupos g
JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
  ON rpu.id_buro_persona = g.id_buro_persona
JOIN ubi1 ubi
  ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
 AND ubi.texto_ubicacion = g.texto_ubicacion
 AND ubi.cod_dw_ciudad = g.cod_dw_ciudad
GROUP BY 1
ORDER BY rpus_r1 DESC, g.id_buro_persona;

-- Q-R1-DIR-DETALLE: Identificador persona + cada dirección/RPU que aplica a R1
-- Descomente el filtro AND para una persona concreta
WITH ubi1 AS (
  SELECT cod_dw_ubic, texto_ubicacion, cod_dw_ciudad
  FROM bdm_tempo.v_xpm_ubicacion_estandarizada
  GROUP BY 1, 2, 3
),
grupos AS (
  SELECT rpu.id_buro_persona, ubi.texto_ubicacion, ubi.cod_dw_ciudad
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
  JOIN ubi1 ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
  GROUP BY 1, 2, 3
  HAVING COUNT(DISTINCT rpu.cod_dw_tipo_ubicacion_dir) > 1
),
grupo_tipos AS (
  SELECT
    g.id_buro_persona,
    g.texto_ubicacion,
    g.cod_dw_ciudad,
    LISTAGG(DISTINCT tud.descripcion_tipo_ubicacion_dir, ' + ')
      WITHIN GROUP (ORDER BY tud.descripcion_tipo_ubicacion_dir) AS tipos_grupo
  FROM grupos g
  JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
    ON rpu.id_buro_persona = g.id_buro_persona
  JOIN ubi1 ubi
    ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
   AND ubi.texto_ubicacion = g.texto_ubicacion
   AND ubi.cod_dw_ciudad = g.cod_dw_ciudad
  LEFT JOIN bdm_datos.tipo_ubicacion_dir tud
    ON rpu.cod_dw_tipo_ubicacion_dir = tud.cod_dw_tipo_ubicacion_dir
  GROUP BY 1, 2, 3
),
grupo_rpus AS (
  SELECT
    g.id_buro_persona,
    g.texto_ubicacion,
    g.cod_dw_ciudad,
    COUNT(DISTINCT rpu.cod_dw_persona_ubic) AS n_rpus_grupo
  FROM grupos g
  JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
    ON rpu.id_buro_persona = g.id_buro_persona
  JOIN ubi1 ubi
    ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
   AND ubi.texto_ubicacion = g.texto_ubicacion
   AND ubi.cod_dw_ciudad = g.cod_dw_ciudad
  GROUP BY 1, 2, 3
)
SELECT
  rpu.id_buro_persona,
  rpu.cod_pin_persona,
  LEFT(g.texto_ubicacion, 100) AS calle,
  g.cod_dw_ciudad,
  gt.tipos_grupo,
  gr.n_rpus_grupo,
  rpu.cod_dw_persona_ubic AS rpu,
  tud.descripcion_tipo_ubicacion_dir AS tipo,
  rpu.cod_dw_ubic,
  rpu.fecha_relacion_persona_ubicaci
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
JOIN ubi1 ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
JOIN grupos g
  ON rpu.id_buro_persona = g.id_buro_persona
 AND ubi.texto_ubicacion = g.texto_ubicacion
 AND ubi.cod_dw_ciudad = g.cod_dw_ciudad
JOIN grupo_tipos gt
  ON g.id_buro_persona = gt.id_buro_persona
 AND g.texto_ubicacion = gt.texto_ubicacion
 AND g.cod_dw_ciudad = gt.cod_dw_ciudad
JOIN grupo_rpus gr
  ON g.id_buro_persona = gr.id_buro_persona
 AND g.texto_ubicacion = gr.texto_ubicacion
 AND g.cod_dw_ciudad = gr.cod_dw_ciudad
LEFT JOIN bdm_datos.tipo_ubicacion_dir tud
  ON rpu.cod_dw_tipo_ubicacion_dir = tud.cod_dw_tipo_ubicacion_dir
WHERE 1 = 1
  -- AND rpu.id_buro_persona = -5233481187049215074
ORDER BY rpu.id_buro_persona, calle, rpu, tipo;

-- Q-R1-EMPATE: Particiones con/sin ganador único (multitipo)
WITH insumo AS (
  SELECT rpu.cod_dw_persona_ubic, rpu.id_buro_persona, ubi.texto_ubicacion, ubi.cod_dw_ciudad,
    rpu.cod_dw_tipo_ubicacion_dir,
    COALESCE(ciiu.cod_act_econo_ciiu_fte, '') AS ciiu,
    COALESCE(COUNT(DISTINCT rep.id_buro_suscriptor), 0) AS n_rep,
    tud.descripcion_tipo_ubicacion_dir AS tipo_dir
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
  JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
  JOIN bdm_tempo.v_xpm_reporte_relacion_persona_ubica rep ON rpu.cod_dw_persona_ubic = rep.cod_dw_persona_ubic
  LEFT JOIN bdm_tempo.v_xpm_ciiu_persona ciiu ON rpu.id_buro_persona = ciiu.id_buro_persona
  LEFT JOIN bdm_datos.tipo_ubicacion_dir tud ON rpu.cod_dw_tipo_ubicacion_dir = tud.cod_dw_tipo_ubicacion_dir
  WHERE rpu.ind_unificacion IS NULL
  GROUP BY 1,2,3,4,5,6,8
),
scored AS (
  SELECT *, CASE WHEN ciiu = '10' THEN 'ESC1' WHEN ciiu IN ('81','82','90') THEN 'ESC2' ELSE 'ESC3' END AS esc,
    CASE WHEN ciiu = '10' THEN CASE WHEN tipo_dir IN ('LAB','CRR') THEN 100000 ELSE 0 END + n_rep
         WHEN ciiu IN ('81','82','90') THEN CASE WHEN tipo_dir IN ('RES','CRR') THEN 100000 ELSE 0 END + n_rep
         ELSE n_rep END AS score
  FROM insumo
),
mult AS (
  SELECT id_buro_persona, texto_ubicacion, cod_dw_ciudad FROM scored
  GROUP BY 1,2,3 HAVING COUNT(DISTINCT cod_dw_tipo_ubicacion_dir) > 1
),
win AS (
  SELECT s.id_buro_persona, s.texto_ubicacion, s.cod_dw_ciudad, s.esc, MAX(s.score) AS max_score
  FROM scored s JOIN mult m USING (id_buro_persona, texto_ubicacion, cod_dw_ciudad)
  GROUP BY 1,2,3,4
)
SELECT w.esc AS escenario_r1,
  COUNT(*)::BIGINT AS particiones,
  SUM(CASE WHEN cnt = 1 THEN 1 ELSE 0 END)::BIGINT AS ganador_unico,
  SUM(CASE WHEN cnt > 1 THEN 1 ELSE 0 END)::BIGINT AS empates
FROM win w
JOIN (
  SELECT s.id_buro_persona, s.texto_ubicacion, s.cod_dw_ciudad, s.esc, COUNT(*) AS cnt
  FROM scored s JOIN win w
    ON s.id_buro_persona = w.id_buro_persona AND s.texto_ubicacion = w.texto_ubicacion
   AND s.cod_dw_ciudad = w.cod_dw_ciudad AND s.esc = w.esc AND s.score = w.max_score
  GROUP BY 1,2,3,4
) x USING (id_buro_persona, texto_ubicacion, cod_dw_ciudad, esc)
GROUP BY 1 ORDER BY 1;

-- Q-R2-00: Salida total R2
SELECT COUNT(*)::BIGINT AS unificaciones_r2 FROM bdm_datos.unificacion_direccion WHERE unifica_atributos = 2;

-- Q-R2-ESC1: Candidatos Esc1 (padre comp / hija sin comp) — estimación
SELECT COUNT(DISTINCT b.cod_dw_persona_ubic)::BIGINT AS hijas_candidatas_esc1
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu_a
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi_a ON rpu_a.cod_dw_ubic = ubi_a.cod_dw_ubic
JOIN bdm_tempo.v_xpm_direccion_fisica df_a ON rpu_a.cod_dw_direccion_fisica = df_a.cod_dw_direccion_fisica
JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion rpu_b
  ON rpu_a.id_buro_persona = rpu_b.id_buro_persona
 AND rpu_a.cod_dw_tipo_ubicacion_dir = rpu_b.cod_dw_tipo_ubicacion_dir
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi_b ON rpu_b.cod_dw_ubic = ubi_b.cod_dw_ubic
JOIN bdm_tempo.v_xpm_direccion_fisica df_b ON rpu_b.cod_dw_direccion_fisica = df_b.cod_dw_direccion_fisica
WHERE ubi_a.texto_ubicacion = ubi_b.texto_ubicacion
  AND ubi_a.cod_dw_ciudad = ubi_b.cod_dw_ciudad
  AND rpu_a.cod_dw_persona_ubic <> rpu_b.cod_dw_persona_ubic
  AND df_a.complemento IS NOT NULL AND LENGTH(TRIM(df_a.complemento)) > 0
  AND (df_b.complemento IS NULL OR LENGTH(TRIM(df_b.complemento)) = 0);

-- Q-R2-ESC1-EJ: Muestra real unificada R2
SELECT TOP 10
  u.cod_dw_persona_ubic AS hija,
  u.cod_dw_direccion_unificada AS padre,
  df_h.complemento AS comp_hija,
  df_p.complemento AS comp_padre,
  ubi.texto_ubicacion,
  tud.descripcion_tipo_ubicacion_dir AS tipo
FROM bdm_datos.unificacion_direccion u
JOIN bdm_tempo.v_xpm_direccion_fisica df_h ON df_h.cod_dw_direccion_fisica = u.cod_dw_persona_ubic
JOIN bdm_tempo.v_xpm_direccion_fisica df_p ON df_p.cod_dw_direccion_fisica = u.cod_dw_direccion_unificada
JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion rpu ON rpu.cod_dw_persona_ubic = u.cod_dw_persona_ubic
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
LEFT JOIN bdm_datos.tipo_ubicacion_dir tud ON rpu.cod_dw_tipo_ubicacion_dir = tud.cod_dw_tipo_ubicacion_dir
WHERE u.unifica_atributos = 2
ORDER BY u.cod_dw_persona_ubic;

-- Q-R2-ESC2: Candidatos complemento contenido (sin unificar aún — remanente post-R2)
-- Nota: en corrida completa ESC1 ya unificó; esta query aplica sobre RPUs no en unificacion_direccion
SELECT COUNT(DISTINCT b.cod_dw_persona_ubic)::BIGINT AS candidatos_esc2_remanente
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu_a
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi_a ON rpu_a.cod_dw_ubic = ubi_a.cod_dw_ubic
JOIN bdm_tempo.v_xpm_direccion_fisica df_a ON rpu_a.cod_dw_direccion_fisica = df_a.cod_dw_direccion_fisica
JOIN bdm_tempo.v_xpm_relacion_persona_ubicacion rpu_b
  ON rpu_a.id_buro_persona = rpu_b.id_buro_persona
 AND rpu_a.cod_dw_tipo_ubicacion_dir = rpu_b.cod_dw_tipo_ubicacion_dir
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi_b ON rpu_b.cod_dw_ubic = ubi_b.cod_dw_ubic
JOIN bdm_tempo.v_xpm_direccion_fisica df_b ON rpu_b.cod_dw_direccion_fisica = df_b.cod_dw_direccion_fisica
LEFT JOIN bdm_datos.unificacion_direccion u ON u.cod_dw_persona_ubic = rpu_b.cod_dw_persona_ubic AND u.unifica_atributos = 2
WHERE u.cod_dw_persona_ubic IS NULL
  AND ubi_a.texto_ubicacion = ubi_b.texto_ubicacion
  AND ubi_a.cod_dw_ciudad = ubi_b.cod_dw_ciudad
  AND rpu_a.cod_dw_persona_ubic <> rpu_b.cod_dw_persona_ubic
  AND df_a.complemento <> df_b.complemento
  AND df_a.complemento LIKE '%' || df_b.complemento || '%'
  AND LENGTH(TRIM(df_b.complemento)) > 0;

-- Q-R3-GEO: Cobertura latitud
SELECT
  SUM(CASE WHEN ubi.latitud IS NOT NULL THEN 1 ELSE 0 END)::BIGINT AS con_lat,
  COUNT(*)::BIGINT AS total
FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic;

-- Q-R3-00: Salida R3
SELECT COUNT(*)::BIGINT AS unificaciones_r3 FROM bdm_datos.unificacion_direccion WHERE unifica_atributos = 3;

-- Q-R3-POT: Pares potenciales SIN filtro geo (solo diagnóstico)
WITH ins AS (
  SELECT rpu.cod_dw_persona_ubic, rpu.id_buro_persona, ubi.texto_ubicacion,
    ubi.cod_dw_ciudad AS mun, ubi.latitud,
    COALESCE(cnt.n, 0) AS n_rep
  FROM bdm_tempo.v_xpm_relacion_persona_ubicacion rpu
  JOIN bdm_tempo.v_xpm_ubicacion_estandarizada ubi ON rpu.cod_dw_ubic = ubi.cod_dw_ubic
  LEFT JOIN (
    SELECT cod_dw_persona_ubic, COUNT(DISTINCT id_buro_suscriptor) AS n
    FROM bdm_tempo.v_xpm_reporte_relacion_persona_ubica GROUP BY 1
  ) cnt ON cnt.cod_dw_persona_ubic = rpu.cod_dw_persona_ubic
)
SELECT COUNT(*)::BIGINT AS pares_potenciales_sin_geo
FROM ins a JOIN ins b
  ON a.id_buro_persona = b.id_buro_persona AND a.mun = b.mun
 AND a.cod_dw_persona_ubic <> b.cod_dw_persona_ubic
 AND SPLIT_PART(a.texto_ubicacion,' ',1) = SPLIT_PART(b.texto_ubicacion,' ',1)
 AND SPLIT_PART(a.texto_ubicacion,' ',2) = SPLIT_PART(b.texto_ubicacion,' ',2)
 AND a.n_rep > b.n_rep;
