-- PRUEBAS DE INTEGRIDAD DEL ESQUEMA (PostgreSQL + pgvector)
-- PRERREQUISITO: ejecutar schema.sql en una base vacia.
-- Todos los datos son ficticios. Al final ROLLBACK deja la base sin datos de prueba.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d cadena_custodia -f pruebas_schema.sql

BEGIN;

-- Cada caso debe fallar por la causa esperada; aceptar la operacion es un fallo.
-- La funcion auxiliar desaparece al revertir esta transaccion.
CREATE FUNCTION pg_temp.esperar_error(
    caso TEXT, sentencia TEXT, estado TEXT, detalle TEXT DEFAULT ''
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE sentencia;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE <> estado OR position(detalle IN SQLERRM) = 0 THEN
            RAISE EXCEPTION 'FALLO [%]: error inesperado %: %', caso, SQLSTATE, SQLERRM;
        END IF;
        RAISE NOTICE 'OK: %', caso;
        RETURN;
    END;
    RAISE EXCEPTION 'FALLO [%]: se acepto una operacion invalida', caso;
END;
$$;

DO $$
DECLARE
    tabla TEXT;
BEGIN
    FOREACH tabla IN ARRAY ARRAY[
        'funcionarios', 'expedientes_judiciales', 'evidencias', 'embalajes',
        'transferencias_custodia', 'peritajes', 'evidencias_analizadas',
        'fotografias_evidencia', 'documentos_forenses', 'embeddings_texto',
        'embeddings_imagen', 'consultas', 'resultados_recuperacion', 'evaluaciones'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                       WHERE table_schema = 'public' AND table_name = tabla
                         AND table_type = 'BASE TABLE') THEN
            RAISE EXCEPTION 'FALLO: falta la tabla %', tabla;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_am a ON a.oid = c.relam
        WHERE n.nspname = 'public' AND a.amname = 'hnsw' AND i.indisvalid
          AND c.relname IN ('idx_emb_texto_hnsw', 'idx_emb_imagen_hnsw')
          AND pg_get_indexdef(c.oid) LIKE '%vector_cosine_ops%') <> 2 THEN
        RAISE EXCEPTION 'FALLO: faltan indices HNSW validos para distancia coseno';
    END IF;
    RAISE NOTICE 'OK: existen las 14 tablas y los dos indices HNSW coseno';
END;
$$;

DO $$
DECLARE
    v_fiscal UUID;
    v_investigador UUID;
    v_custodio UUID;
    v_perito UUID;
    v_exp_a UUID;
    v_exp_b UUID;
    v_evid_a UUID;
    v_evid_b UUID;
    v_peritaje_a UUID;
    v_peritaje_b UUID;
    v_documento UUID;
    v_foto UUID;
    v_emb_texto UUID;
    v_emb_imagen UUID;
    v_consulta UUID;
    v_transferencia UUID;
    v_submuestra UUID;
    v_recuperado UUID;
    v_estrategia TEXT;
BEGIN
    INSERT INTO funcionarios (documento_identidad, nombre_completo, rol, institucion, correo_institucional)
    VALUES ('F100', 'Fiscal de prueba', 'fiscal', 'Institucion de prueba', 'fiscal@test.local')
    RETURNING id INTO v_fiscal;

    INSERT INTO funcionarios (documento_identidad, nombre_completo, rol, institucion, correo_institucional)
    VALUES ('F101', 'Investigador de prueba', 'investigador', 'Institucion de prueba', 'inv@test.local')
    RETURNING id INTO v_investigador;

    INSERT INTO funcionarios (documento_identidad, nombre_completo, rol, institucion, correo_institucional)
    VALUES ('F102', 'Custodio de prueba', 'custodio', 'Institucion de prueba', 'cust@test.local')
    RETURNING id INTO v_custodio;

    INSERT INTO funcionarios (documento_identidad, nombre_completo, rol, institucion, correo_institucional)
    VALUES ('F103', 'Perito de prueba', 'perito', 'Institucion de prueba', 'perito@test.local')
    RETURNING id INTO v_perito;

    INSERT INTO expedientes_judiciales (fiscal_asignado_id, delito_investigado, codigo_radicado, fecha_apertura, estado)
    VALUES (v_fiscal, 'Caso academico A', 'RAD-PRUEBA-001', now() - interval '5 days', 'abierto')
    RETURNING id INTO v_exp_a;
    INSERT INTO expedientes_judiciales (fiscal_asignado_id, delito_investigado, codigo_radicado, fecha_apertura, estado)
    VALUES (v_fiscal, 'Caso academico B', 'RAD-PRUEBA-002', now() - interval '5 days', 'abierto')
    RETURNING id INTO v_exp_b;

    INSERT INTO evidencias (
        expediente_id, recolector_id, custodio_inicial_id, codigo_rotulo,
        tipo_evidencia, descripcion_macroscopica, lugar_fijacion, fecha_hora_hallazgo, estado
    ) VALUES (
        v_exp_a, v_investigador, v_investigador, 'EV-PRUEBA-001',
        'digital', 'Dispositivo de prueba', 'Escena simulada', now() - interval '4 days', 'registrada'
    ) RETURNING id INTO v_evid_a;

    INSERT INTO evidencias (
        expediente_id, recolector_id, custodio_inicial_id, codigo_rotulo,
        tipo_evidencia, descripcion_macroscopica, lugar_fijacion, fecha_hora_hallazgo, estado
    ) VALUES (
        v_exp_b, v_investigador, v_investigador, 'EV-PRUEBA-002',
        'fisica', 'Objeto de prueba', 'Escena simulada', now() - interval '4 days', 'registrada'
    ) RETURNING id INTO v_evid_b;

    INSERT INTO embalajes (evidencia_id, tipo_recipiente, numero_precinto,
                          estado_precinto, fecha_sellado)
    VALUES (v_evid_a, 'bolsa', 'PRECINTO-PRUEBA-001', 'integro', now());

    INSERT INTO evidencias (
        expediente_id, evidencia_padre_id, recolector_id, custodio_inicial_id,
        codigo_rotulo, tipo_evidencia, descripcion_macroscopica, lugar_fijacion,
        fecha_hora_hallazgo, estado
    ) VALUES (
        v_exp_a, v_evid_a, v_investigador, v_custodio, 'SUB-PRUEBA-001',
        'digital', 'Submuestra ficticia', 'Laboratorio simulado', now(), 'registrada'
    ) RETURNING id INTO v_submuestra;

    -- Custodia valida A -> B.
    INSERT INTO transferencias_custodia (
        evidencia_id, funcionario_entrega_id, funcionario_recibe_id, fecha_hora,
        motivo_traslado, condicion_embalaje
    ) VALUES (
        v_evid_a, v_investigador, v_custodio, now() - interval '3 days',
        'Traslado simulado', 'integro'
    ) RETURNING id INTO v_transferencia;

    -- Custodia invalida: el investigador ya no puede entregar.
    BEGIN
        INSERT INTO transferencias_custodia (
            evidencia_id, funcionario_entrega_id, funcionario_recibe_id, fecha_hora,
            motivo_traslado, condicion_embalaje
        ) VALUES (
            v_evid_a, v_investigador, v_perito, now() - interval '2 days',
            'Intento invalido', 'integro'
        );
        RAISE EXCEPTION 'FALLO PRUEBA: se acepto custodio incorrecto';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'Transferencia rechazada:%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: se rechaza transferencia por custodio no vigente';
    END;

    -- Historial inmutable.
    BEGIN
        DELETE FROM transferencias_custodia WHERE id = v_transferencia;
        RAISE EXCEPTION 'FALLO PRUEBA: se permitio borrar transferencia';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'El historial de transferencias es append-only:%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: el historial de transferencias no puede borrarse';
    END;

    INSERT INTO peritajes (expediente_id, perito_id, numero_dictamen, disciplina)
    VALUES (v_exp_a, v_perito, 'PER-PRUEBA-001', 'informatica forense')
    RETURNING id INTO v_peritaje_a;
    INSERT INTO peritajes (expediente_id, perito_id, numero_dictamen, disciplina)
    VALUES (v_exp_b, v_perito, 'PER-PRUEBA-002', 'laboratorio')
    RETURNING id INTO v_peritaje_b;

    INSERT INTO evidencias_analizadas(evidencia_id, peritaje_id)
    VALUES (v_evid_a, v_peritaje_a);

    BEGIN
        INSERT INTO evidencias_analizadas(evidencia_id, peritaje_id)
        VALUES (v_evid_a, v_peritaje_b);
        RAISE EXCEPTION 'FALLO PRUEBA: asociacion de expediente distinto';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'Evidencia y peritaje deben pertenecer%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: no se permite asociar evidencia y peritaje de expedientes distintos';
    END;

    INSERT INTO fotografias_evidencia (
        evidencia_id, peritaje_id, codigo_foto, tipo_encuadre,
        url_almacenamiento, fecha_captura
    ) VALUES (
        v_evid_a, v_peritaje_a, 'FOTO-PRUEBA-001', 'general',
        '/archivos/foto_prueba.jpg', now() - interval '2 days'
    ) RETURNING id INTO v_foto;

    -- Documento de peritaje: expediente_id debe permanecer NULL (XOR).
    INSERT INTO documentos_forenses (
        peritaje_id, titulo, tipo_documento, fecha_documento, contenido_texto
    ) VALUES (
        v_peritaje_a, 'Informe de prueba', 'dictamen', now() - interval '1 day',
        'El laboratorio examino el dispositivo simulado sin hallazgos concluyentes.'
    ) RETURNING id INTO v_documento;

    BEGIN
        INSERT INTO documentos_forenses (
            expediente_id, peritaje_id, titulo, tipo_documento, fecha_documento, contenido_texto
        ) VALUES (
            v_exp_a, v_peritaje_a, 'Documento invalido', 'acta', now(), 'Texto de prueba'
        );
        RAISE EXCEPTION 'FALLO PRUEBA: documento con doble asociacion';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: CHECK XOR de documentos';
    END;

    INSERT INTO embeddings_texto (
        documento_id, estrategia_chunking, chunk_index, chunk_texto,
        embedding, modelo_vectorizador
    ) VALUES (
        v_documento, 'fixed-size', 0, 'El laboratorio examino el dispositivo simulado.',
        array_fill(0.1::real, ARRAY[384])::vector(384), 'all-MiniLM-L6-v2'
    ) RETURNING id INTO v_emb_texto;

    INSERT INTO embeddings_imagen (fotografia_id, modelo_vectorizador, embedding)
    VALUES (v_foto, 'CLIP ViT-B/32', array_fill(0.1::real, ARRAY[512])::vector(512))
    RETURNING id INTO v_emb_imagen;

    INSERT INTO consultas (
        funcionario_id, expediente_id, texto_pregunta, estrategia_chunking,
        embedding_pregunta, embedding_pregunta_clip, respuesta_generada, modelo_llm
    ) VALUES (
        v_investigador, v_exp_a, 'Que indica el informe?', 'fixed-size',
        array_fill(0.1::real, ARRAY[384])::vector(384),
        array_fill(0.1::real, ARRAY[512])::vector(512),
        'Informe de prueba consultado.', 'llm-academico'
    ) RETURNING id INTO v_consulta;

    INSERT INTO resultados_recuperacion (
        consulta_id, embedding_texto_id, score_similitud, posicion
    ) VALUES (v_consulta, v_emb_texto, 0.92, 1);
    INSERT INTO resultados_recuperacion (
        consulta_id, embedding_imagen_id, score_similitud, posicion
    ) VALUES (v_consulta, v_emb_imagen, 0.85, 2);

    BEGIN
        INSERT INTO resultados_recuperacion (
            consulta_id, embedding_texto_id, embedding_imagen_id, score_similitud, posicion
        ) VALUES (v_consulta, v_emb_texto, v_emb_imagen, 0.8, 3);
        RAISE EXCEPTION 'FALLO PRUEBA: resultado con dos tipos';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: CHECK XOR de resultados';
    END;

    INSERT INTO evaluaciones (
        consulta_id, faithfulness, answer_relevancy, context_recall, modelo_evaluador
    ) VALUES (v_consulta, 0.91, 0.88, 0.79, 'modelo-prueba');

    PERFORM pg_temp.esperar_error('PK de asociacion duplicada', format(
        'INSERT INTO evidencias_analizadas VALUES (%L, %L)', v_evid_a, v_peritaje_a
    ), '23505', 'pk_evidencias_analizadas');
    PERFORM pg_temp.esperar_error('FK de embalaje sin evidencia', format(
        'UPDATE embalajes SET evidencia_id = %L WHERE numero_precinto = %L',
        gen_random_uuid(), 'PRECINTO-PRUEBA-001'
    ), '23503');
    PERFORM pg_temp.esperar_error('NOT NULL de funcionario', format(
        'UPDATE funcionarios SET nombre_completo = NULL WHERE id = %L', v_fiscal
    ), '23502');
    PERFORM pg_temp.esperar_error('UNIQUE de correo', format(
        'UPDATE funcionarios SET correo_institucional = %L WHERE id = %L',
        'fiscal@test.local', v_perito
    ), '23505');
    PERFORM pg_temp.esperar_error('Rol fuera del dominio', format(
        'UPDATE funcionarios SET rol = %L WHERE id = %L', 'invalido', v_perito
    ), '23514', 'rol');

    PERFORM pg_temp.esperar_error('UPDATE de transferencia bloqueado', format(
        'UPDATE transferencias_custodia SET observaciones = %L WHERE id = %L',
        'Cambio no permitido', v_transferencia
    ), 'P0001', 'append-only');
    PERFORM pg_temp.esperar_error('Transferencia anterior al hallazgo', format(
        'INSERT INTO transferencias_custodia (evidencia_id, funcionario_entrega_id,
         funcionario_recibe_id, fecha_hora, motivo_traslado, condicion_embalaje)
         VALUES (%L, %L, %L, now() - interval ''6 days'', ''Prueba'', ''integro'')',
        v_evid_a, v_custodio, v_perito
    ), 'P0001', 'anterior al hallazgo');
    PERFORM pg_temp.esperar_error('Transferencia fuera del orden temporal', format(
        'INSERT INTO transferencias_custodia (evidencia_id, funcionario_entrega_id,
         funcionario_recibe_id, fecha_hora, motivo_traslado, condicion_embalaje)
         VALUES (%L, %L, %L, now() - interval ''3 days'', ''Prueba'', ''integro'')',
        v_evid_a, v_custodio, v_perito
    ), 'P0001', 'posterior a la ultima');
    PERFORM pg_temp.esperar_error('Entrega y recepcion por la misma persona', format(
        'INSERT INTO transferencias_custodia (evidencia_id, funcionario_entrega_id,
         funcionario_recibe_id, fecha_hora, motivo_traslado, condicion_embalaje)
         VALUES (%L, %L, %L, now(), ''Prueba'', ''integro'')',
        v_evid_a, v_custodio, v_custodio
    ), '23514', 'chk_funcionarios_distintos');
    INSERT INTO transferencias_custodia (
        evidencia_id, funcionario_entrega_id, funcionario_recibe_id,
        fecha_hora, motivo_traslado, condicion_embalaje
    ) VALUES (v_evid_a, v_custodio, v_perito, now(), 'Segunda entrega valida', 'integro');

    PERFORM pg_temp.esperar_error('Parentesco de evidencia inmutable', format(
        'UPDATE evidencias SET evidencia_padre_id = %L WHERE id = %L',
        v_submuestra, v_evid_a
    ), 'P0001', 'No se permite modificar');
    PERFORM pg_temp.esperar_error('Submuestra de otro expediente', format(
        'INSERT INTO evidencias (expediente_id, evidencia_padre_id, recolector_id,
         custodio_inicial_id, codigo_rotulo, tipo_evidencia, descripcion_macroscopica,
         lugar_fijacion, fecha_hora_hallazgo, estado)
         VALUES (%L, %L, %L, %L, ''SUB-INVALIDA'', ''digital'', ''Prueba'',
         ''Laboratorio'', now(), ''registrada'')',
        v_exp_b, v_evid_a, v_investigador, v_custodio
    ), 'P0001', 'mismo expediente');
    PERFORM pg_temp.esperar_error('Expediente de peritaje inmutable', format(
        'UPDATE peritajes SET expediente_id = %L WHERE id = %L', v_exp_b, v_peritaje_a
    ), 'P0001', 'No se permite cambiar');
    PERFORM pg_temp.esperar_error('Fotografia sin pareja evidencia-peritaje', format(
        'UPDATE fotografias_evidencia SET peritaje_id = %L WHERE id = %L',
        v_peritaje_b, v_foto
    ), '23503', 'fk_fotografia_evidencia_peritaje');

    PERFORM pg_temp.esperar_error('Documento sin origen', format(
        'UPDATE documentos_forenses SET peritaje_id = NULL WHERE id = %L', v_documento
    ), '23514', 'chk_documento_origen_xor');
    INSERT INTO documentos_forenses (
        expediente_id, titulo, tipo_documento, fecha_documento, contenido_texto
    ) VALUES (v_exp_a, 'Acta ficticia', 'acta', now(), 'Documento directo del expediente.');
    PERFORM pg_temp.esperar_error('Resultado sin embedding', format(
        'INSERT INTO resultados_recuperacion (consulta_id, score_similitud, posicion)
         VALUES (%L, 0.5, 3)', v_consulta
    ), '23514', 'chk_resultado_tipo_xor');

    PERFORM pg_temp.esperar_error('Fragmento duplicado', format(
        'INSERT INTO embeddings_texto (documento_id, estrategia_chunking, chunk_index,
         chunk_texto, embedding, modelo_vectorizador)
         SELECT documento_id, estrategia_chunking, chunk_index, chunk_texto, embedding,
         modelo_vectorizador FROM embeddings_texto WHERE id = %L', v_emb_texto
    ), '23505', 'uq_fragmento_estrategia');
    PERFORM pg_temp.esperar_error('Estrategia no admitida', format(
        'UPDATE embeddings_texto SET estrategia_chunking = ''otra'' WHERE id = %L',
        v_emb_texto
    ), '23514', 'chk_chunking_texto');
    PERFORM pg_temp.esperar_error('Indice de fragmento negativo', format(
        'UPDATE embeddings_texto SET chunk_index = -1 WHERE id = %L', v_emb_texto
    ), '23514', 'chk_chunk_index');
    PERFORM pg_temp.esperar_error('Metadata debe ser un objeto', format(
        'UPDATE embeddings_texto SET metadata = ''[]''::jsonb WHERE id = %L', v_emb_texto
    ), '23514', 'chk_metadata_texto_objeto');
    PERFORM pg_temp.esperar_error('Texto rechaza 512 dimensiones', format(
        'UPDATE embeddings_texto SET embedding = array_fill(0.1::real, ARRAY[512])::vector
         WHERE id = %L', v_emb_texto
    ), '22000', '384');
    PERFORM pg_temp.esperar_error('Imagen rechaza 384 dimensiones', format(
        'UPDATE embeddings_imagen SET embedding = array_fill(0.1::real, ARRAY[384])::vector
         WHERE id = %L', v_emb_imagen
    ), '22000', '512');

    -- Las tres estrategias pueden coexistir para un mismo documento e indice.
    FOREACH v_estrategia IN ARRAY ARRAY['sentence-aware', 'semantic'] LOOP
        INSERT INTO embeddings_texto (documento_id, estrategia_chunking, chunk_index,
                                      chunk_texto, embedding, modelo_vectorizador)
        VALUES (v_documento, v_estrategia, 0, 'Fragmento sintetico.',
                array_fill(0.1::real, ARRAY[384])::vector, 'modelo-prueba');
    END LOOP;

    PERFORM pg_temp.esperar_error('Una evaluacion como maximo', format(
        'INSERT INTO evaluaciones (consulta_id, modelo_evaluador) VALUES (%L, ''prueba'')',
        v_consulta
    ), '23505');
    PERFORM pg_temp.esperar_error('Faithfulness superior a uno', format(
        'UPDATE evaluaciones SET faithfulness = 1.1 WHERE consulta_id = %L', v_consulta
    ), '23514', 'chk_faithfulness');
    PERFORM pg_temp.esperar_error('Answer relevancy negativa', format(
        'UPDATE evaluaciones SET answer_relevancy = -0.1 WHERE consulta_id = %L', v_consulta
    ), '23514', 'chk_answer_relevancy');
    PERFORM pg_temp.esperar_error('Context recall superior a uno', format(
        'UPDATE evaluaciones SET context_recall = 1.1 WHERE consulta_id = %L', v_consulta
    ), '23514', 'chk_context_recall');
    UPDATE evaluaciones SET faithfulness = 0, answer_relevancy = 1, context_recall = 0
    WHERE consulta_id = v_consulta;

    -- Dos candidatos distintos por modalidad: el vector identico debe ser primero.
    INSERT INTO embeddings_texto (documento_id, estrategia_chunking, chunk_index,
                                  chunk_texto, embedding, modelo_vectorizador)
    VALUES (v_documento, 'fixed-size', 1, 'Vector opuesto sintetico.',
            array_fill(-0.1::real, ARRAY[384])::vector, 'modelo-prueba');
    SELECT id INTO v_recuperado FROM embeddings_texto
    WHERE documento_id = v_documento AND estrategia_chunking = 'fixed-size'
    ORDER BY embedding <=> array_fill(0.1::real, ARRAY[384])::vector LIMIT 1;
    IF v_recuperado IS DISTINCT FROM v_emb_texto THEN
        RAISE EXCEPTION 'FALLO: orden de recuperacion textual';
    END IF;
    INSERT INTO embeddings_imagen (fotografia_id, modelo_vectorizador, embedding)
    VALUES (v_foto, 'modelo-sintetico-alternativo', array_fill(-0.1::real, ARRAY[512])::vector);
    SELECT id INTO v_recuperado FROM embeddings_imagen WHERE fotografia_id = v_foto
    ORDER BY embedding <=> array_fill(0.1::real, ARRAY[512])::vector LIMIT 1;
    IF v_recuperado IS DISTINCT FROM v_emb_imagen THEN
        RAISE EXCEPTION 'FALLO: orden de recuperacion visual';
    END IF;
    RAISE NOTICE 'OK: recuperacion por coseno en texto e imagen con vectores sinteticos';

    RAISE NOTICE 'OK: inserciones basicas, referencias, embeddings y evaluacion de las 14 tablas';
END;
$$;

-- No deja registros de prueba persistentes.
ROLLBACK;

-- Comprobaciones de catalogo, ejecutables incluso sin datos.
SELECT count(*) AS tablas_publicas
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname = 'public' AND indexname IN ('idx_emb_texto_hnsw', 'idx_emb_imagen_hnsw')
ORDER BY indexname;
