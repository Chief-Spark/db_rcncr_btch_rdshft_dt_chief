-- Orquestador ejecución — unificación por regla (cada regla llama sus escenarios)
-- SLCOPRBA-1284 / SLCOPRBA-1286: promoción a QA Unificación Alpha (edf_views)
TRUNCATE TABLE bdm_datos.unificacion_direccion;

CALL bdm_datos.sp_unificacion_regla1('', '', '', '', '', '');
CALL bdm_datos.sp_unificacion_regla2('', '', '', '', '', '');
CALL bdm_datos.sp_unificacion_regla3('', '', '', '', '', '');
