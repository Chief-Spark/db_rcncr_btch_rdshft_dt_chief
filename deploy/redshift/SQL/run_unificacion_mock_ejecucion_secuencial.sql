-- Orquestador mock — SPs sp_unificacion_mock_* (Data Sharing)
-- NO usar sp_unificacion_* (sin mock) en esta corrida.
TRUNCATE TABLE bdm_datos.unificacion_direccion_mock;

CALL bdm_datos.sp_unificacion_mock_regla1();
CALL bdm_datos.sp_unificacion_mock_regla2();
CALL bdm_datos.sp_unificacion_mock_regla3();
