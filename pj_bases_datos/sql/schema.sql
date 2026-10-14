-- ============================================================================
-- UNIVERSIDAD DE CALDAS - BASES DE DATOS RELACIONALES - ENTREGA 1
-- Sistema hibrido relacional-vectorial para cadena de custodia forense
-- Esquema PostgreSQL 16+ con pgvector disponible en el servidor
-- 14 tablas. Ejecutar en una base de datos vacia con permisos para CREATE EXTENSION.
-- SQL en minusculas con guiones bajos; UUID, TIMESTAMPTZ, JSONB y VECTOR.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS vector;

-- 1. Identificacion de funcionarios (nucleo Usuario).
CREATE TABLE funcionarios (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    documento_identidad    VARCHAR(20) NOT NULL UNIQUE,
    nombre_completo        VARCHAR(120) NOT NULL,
    rol                    VARCHAR(50) NOT NULL
                           CHECK (rol IN ('investigador', 'custodio', 'perito',
                                         'administrador', 'fiscal')),
    institucion            VARCHAR(80) NOT NULL,
    correo_institucional   VARCHAR(100) NOT NULL UNIQUE
);

-- 2. Expedientes simulados.
CREATE TABLE expedientes_judiciales (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fiscal_asignado_id    UUID NOT NULL REFERENCES funcionarios(id),
    delito_investigado    VARCHAR(100) NOT NULL,
    codigo_radicado       VARCHAR(30) NOT NULL UNIQUE,
    fecha_apertura        TIMESTAMPTZ NOT NULL,
    estado                VARCHAR(30) NOT NULL
);

-- 3. Evidencias y jerarquia de submuestras.
-- recolector_id y custodio_inicial_id son roles diferentes (pueden coincidir).
CREATE TABLE evidencias (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expediente_id            UUID NOT NULL REFERENCES expedientes_judiciales(id),
    evidencia_padre_id       UUID REFERENCES evidencias(id),
    recolector_id            UUID NOT NULL REFERENCES funcionarios(id),
    custodio_inicial_id      UUID NOT NULL REFERENCES funcionarios(id),
    codigo_rotulo            VARCHAR(30) NOT NULL UNIQUE,
    tipo_evidencia           VARCHAR(50) NOT NULL,
    descripcion_macroscopica TEXT NOT NULL,
    lugar_fijacion           VARCHAR(200) NOT NULL,
    fecha_hora_hallazgo      TIMESTAMPTZ NOT NULL,
    estado                   VARCHAR(30) NOT NULL,
    CONSTRAINT chk_evidencia_no_autopadre
        CHECK (evidencia_padre_id IS DISTINCT FROM id)
);

-- 4. Embalajes; se conservan varios por evidencia (historial de reembalaje).
CREATE TABLE embalajes (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evidencia_id       UUID NOT NULL REFERENCES evidencias(id),
    tipo_recipiente    VARCHAR(50) NOT NULL,
    numero_precinto    VARCHAR(50) NOT NULL UNIQUE,
    estado_precinto    VARCHAR(50) NOT NULL,
    fecha_sellado      TIMESTAMPTZ NOT NULL
);

-- 5. Historial de transferencias de custodia (solo inserciones).
CREATE TABLE transferencias_custodia (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evidencia_id             UUID NOT NULL REFERENCES evidencias(id),
    funcionario_entrega_id   UUID NOT NULL REFERENCES funcionarios(id),
    funcionario_recibe_id    UUID NOT NULL REFERENCES funcionarios(id),
    fecha_hora               TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    motivo_traslado          VARCHAR(150) NOT NULL,
    condicion_embalaje       VARCHAR(50) NOT NULL,
    observaciones            TEXT,
    CONSTRAINT chk_funcionarios_distintos
        CHECK (funcionario_entrega_id <> funcionario_recibe_id)
);

-- 6. Analisis pericial de un expediente.
CREATE TABLE peritajes (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expediente_id         UUID NOT NULL REFERENCES expedientes_judiciales(id),
    perito_id             UUID NOT NULL REFERENCES funcionarios(id),
    numero_dictamen       VARCHAR(30) NOT NULL UNIQUE,
    disciplina            VARCHAR(50) NOT NULL,
    metodologia_aplicada  TEXT,
    analisis_tecnico      TEXT,
    conclusiones          TEXT,
    fecha_emision         TIMESTAMPTZ
);

-- 7. Asociacion N:M entre evidencias y peritajes.
CREATE TABLE evidencias_analizadas (
    evidencia_id  UUID NOT NULL REFERENCES evidencias(id),
    peritaje_id   UUID NOT NULL REFERENCES peritajes(id),
    CONSTRAINT pk_evidencias_analizadas PRIMARY KEY (evidencia_id, peritaje_id)
);

-- 8. Fotografias: vinculo opcional a un peritaje que analiza ESA evidencia.
-- FK compuesta garantiza que la fotografia, si se vincula al peritaje,
-- corresponda a una evidencia incluida en evidencias_analizadas.
CREATE TABLE fotografias_evidencia (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evidencia_id          UUID NOT NULL REFERENCES evidencias(id),
    peritaje_id           UUID,
    codigo_foto           VARCHAR(30) NOT NULL UNIQUE,
    tipo_encuadre         VARCHAR(50) NOT NULL,
    descripcion_tecnica   TEXT,
    url_almacenamiento    VARCHAR(255) NOT NULL,
    fecha_captura         TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_fotografia_evidencia_peritaje
        FOREIGN KEY (evidencia_id, peritaje_id)
        REFERENCES evidencias_analizadas (evidencia_id, peritaje_id)
);

-- 9. Documento: pertenece directamente a expediente O a peritaje (XOR).
-- Si apunta al peritaje, el expediente se obtiene por peritajes.expediente_id.
CREATE TABLE documentos_forenses (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expediente_id     UUID REFERENCES expedientes_judiciales(id),
    peritaje_id       UUID REFERENCES peritajes(id),
    titulo            VARCHAR(200) NOT NULL,
    tipo_documento    VARCHAR(50) NOT NULL,
    idioma            VARCHAR(10) NOT NULL DEFAULT 'es',
    fecha_documento   TIMESTAMPTZ NOT NULL,
    ruta_archivo      VARCHAR(255),
    contenido_texto   TEXT NOT NULL,
    CONSTRAINT chk_documento_origen_xor
        CHECK (num_nonnulls(expediente_id, peritaje_id) = 1)
);

-- 10. Fragmentos y embeddings de texto; un modelo por fragmento en este prototipo.
CREATE TABLE embeddings_texto (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    documento_id         UUID NOT NULL REFERENCES documentos_forenses(id),
    estrategia_chunking  VARCHAR(20) NOT NULL,
    chunk_index          INTEGER NOT NULL,
    chunk_texto          TEXT NOT NULL,
    metadata             JSONB NOT NULL DEFAULT '{}'::jsonb,
    embedding            VECTOR(384) NOT NULL,
    modelo_vectorizador  VARCHAR(100) NOT NULL,
    CONSTRAINT chk_chunking_texto
        CHECK (estrategia_chunking IN ('fixed-size', 'sentence-aware', 'semantic')),
    CONSTRAINT chk_chunk_index
        CHECK (chunk_index >= 0),
    CONSTRAINT chk_metadata_texto_objeto
        CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT uq_fragmento_estrategia
        UNIQUE (documento_id, estrategia_chunking, chunk_index)
);

-- 11. Embeddings de imagen calculados sobre pixeles, NO sobre la ruta del archivo.
CREATE TABLE embeddings_imagen (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fotografia_id        UUID NOT NULL REFERENCES fotografias_evidencia(id),
    modelo_vectorizador  VARCHAR(80) NOT NULL,
    metadata             JSONB NOT NULL DEFAULT '{}'::jsonb,
    embedding            VECTOR(512) NOT NULL,
    CONSTRAINT chk_metadata_imagen_objeto
        CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT uq_fotografia_modelo
        UNIQUE (fotografia_id, modelo_vectorizador)
);

-- 12. Consultas: MiniLM (texto-texto) y CLIP texto (texto-imagen).
CREATE TABLE consultas (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    funcionario_id           UUID NOT NULL REFERENCES funcionarios(id),
    expediente_id            UUID REFERENCES expedientes_judiciales(id),
    texto_pregunta           TEXT NOT NULL,
    fecha_hora               TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    estrategia_chunking      VARCHAR(20),
    embedding_pregunta       VECTOR(384),
    embedding_pregunta_clip  VECTOR(512),
    respuesta_generada       TEXT,
    modelo_llm               VARCHAR(100),
    CONSTRAINT chk_estrategia_consulta
        CHECK (estrategia_chunking IS NULL OR estrategia_chunking
               IN ('fixed-size', 'sentence-aware', 'semantic'))
);

-- 13. Cada resultado remite a un embedding textual O visual (XOR).
CREATE TABLE resultados_recuperacion (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consulta_id           UUID NOT NULL REFERENCES consultas(id),
    embedding_texto_id    UUID REFERENCES embeddings_texto(id),
    embedding_imagen_id   UUID REFERENCES embeddings_imagen(id),
    score_similitud       DOUBLE PRECISION NOT NULL,
    posicion              INTEGER NOT NULL,
    CONSTRAINT chk_resultado_tipo_xor
        CHECK (num_nonnulls(embedding_texto_id, embedding_imagen_id) = 1),
    CONSTRAINT chk_posicion_positiva
        CHECK (posicion > 0),
    CONSTRAINT chk_similitud_coseno
        CHECK (score_similitud BETWEEN -1.0 AND 1.0),
    CONSTRAINT uq_resultado_posicion
        UNIQUE (consulta_id, posicion)
);

-- 14. Evaluacion por ejecucion de consulta: 0 o 1 registro (UNIQUE consulta).
CREATE TABLE evaluaciones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consulta_id         UUID NOT NULL UNIQUE REFERENCES consultas(id),
    faithfulness        DOUBLE PRECISION,
    answer_relevancy    DOUBLE PRECISION,
    context_recall      DOUBLE PRECISION,
    modelo_evaluador    VARCHAR(100) NOT NULL,
    fecha_evaluacion    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_faithfulness
        CHECK (faithfulness BETWEEN 0.0 AND 1.0),
    CONSTRAINT chk_answer_relevancy
        CHECK (answer_relevancy BETWEEN 0.0 AND 1.0),
    CONSTRAINT chk_context_recall
        CHECK (context_recall BETWEEN 0.0 AND 1.0)
);

-- ============================================================================
-- REGLAS DE NEGOCIO NO EXPRESABLES SOLO CON CHECK O FOREIGN KEY
-- ============================================================================

-- La jerarquia es aciclica: un padre debe existir ya, ser del mismo expediente,
-- y NO se permite editar parent/expediente de una evidencia ya creada.
CREATE OR REPLACE FUNCTION validar_padre_evidencia()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_expediente_padre UUID;
BEGIN
    IF NEW.evidencia_padre_id IS NOT NULL THEN
        IF NEW.evidencia_padre_id = NEW.id THEN
            RAISE EXCEPTION 'Una evidencia no puede ser su propia evidencia padre';
        END IF;

        SELECT e.expediente_id
          INTO v_expediente_padre
          FROM evidencias AS e
         WHERE e.id = NEW.evidencia_padre_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La evidencia padre % no existe', NEW.evidencia_padre_id;
        END IF;
        IF v_expediente_padre <> NEW.expediente_id THEN
            RAISE EXCEPTION 'La evidencia padre debe pertenecer al mismo expediente';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_padre_evidencia
BEFORE INSERT ON evidencias
FOR EACH ROW EXECUTE FUNCTION validar_padre_evidencia();

-- Conserva inmutables las referencias base de evidencia y evita ciclos futuros.
CREATE OR REPLACE FUNCTION proteger_identidad_evidencia()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.id IS DISTINCT FROM NEW.id
       OR OLD.expediente_id IS DISTINCT FROM NEW.expediente_id
       OR OLD.evidencia_padre_id IS DISTINCT FROM NEW.evidencia_padre_id
       OR OLD.recolector_id IS DISTINCT FROM NEW.recolector_id
       OR OLD.custodio_inicial_id IS DISTINCT FROM NEW.custodio_inicial_id
       OR OLD.codigo_rotulo IS DISTINCT FROM NEW.codigo_rotulo
       OR OLD.fecha_hora_hallazgo IS DISTINCT FROM NEW.fecha_hora_hallazgo
    THEN
        RAISE EXCEPTION 'No se permite modificar identificadores ni custodia inicial de una evidencia';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_identidad_evidencia
BEFORE UPDATE ON evidencias
FOR EACH ROW EXECUTE FUNCTION proteger_identidad_evidencia();

-- Impide transferir una evidencia si quien entrega NO es su custodio vigente.
-- La fila de evidencias se bloquea hasta finalizar la transaccion para evitar
-- transferencias simultaneas incompatibles.
CREATE OR REPLACE FUNCTION validar_transferencia_custodia()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_custodio_actual UUID;
    v_fecha_anterior  TIMESTAMPTZ;
    v_hallazgo        TIMESTAMPTZ;
BEGIN
    SELECT e.custodio_inicial_id, e.fecha_hora_hallazgo
      INTO v_custodio_actual, v_hallazgo
      FROM evidencias AS e
     WHERE e.id = NEW.evidencia_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la evidencia %', NEW.evidencia_id;
    END IF;

    SELECT t.funcionario_recibe_id, t.fecha_hora
      INTO v_custodio_actual, v_fecha_anterior
      FROM transferencias_custodia AS t
     WHERE t.evidencia_id = NEW.evidencia_id
     ORDER BY t.fecha_hora DESC, t.id DESC
     LIMIT 1;

    IF NOT FOUND THEN
        SELECT e.custodio_inicial_id
          INTO v_custodio_actual
          FROM evidencias AS e
         WHERE e.id = NEW.evidencia_id;
    END IF;

    IF v_custodio_actual IS DISTINCT FROM NEW.funcionario_entrega_id THEN
        RAISE EXCEPTION 'Transferencia rechazada: el funcionario que entrega no es el custodio vigente';
    END IF;

    IF NEW.fecha_hora < v_hallazgo THEN
        RAISE EXCEPTION 'La transferencia no puede ser anterior al hallazgo registrado';
    END IF;
    IF v_fecha_anterior IS NOT NULL AND NEW.fecha_hora <= v_fecha_anterior THEN
        RAISE EXCEPTION 'La transferencia debe ser posterior a la ultima transferencia';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_transferencia_custodia
BEFORE INSERT ON transferencias_custodia
FOR EACH ROW EXECUTE FUNCTION validar_transferencia_custodia();

-- Modelo append-only: se permiten INSERT, no UPDATE ni DELETE sobre transferencias.
CREATE OR REPLACE FUNCTION bloquear_modificacion_transferencias()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El historial de transferencias es append-only: no se permite %', TG_OP;
END;
$$;

CREATE TRIGGER trg_transferencias_append_only
BEFORE UPDATE OR DELETE ON transferencias_custodia
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_transferencias();

-- Impide asociar al peritaje una evidencia de un expediente diferente.
CREATE OR REPLACE FUNCTION validar_expediente_evidencia_peritaje()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_exp_evidencia UUID;
    v_exp_peritaje  UUID;
BEGIN
    SELECT expediente_id INTO v_exp_evidencia
      FROM evidencias WHERE id = NEW.evidencia_id;
    SELECT expediente_id INTO v_exp_peritaje
      FROM peritajes WHERE id = NEW.peritaje_id;

    IF v_exp_evidencia IS NULL OR v_exp_peritaje IS NULL THEN
        RAISE EXCEPTION 'La evidencia y el peritaje deben existir';
    END IF;
    IF v_exp_evidencia <> v_exp_peritaje THEN
        RAISE EXCEPTION 'Evidencia y peritaje deben pertenecer al mismo expediente';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_verificar_evidencias_analizadas
BEFORE INSERT OR UPDATE ON evidencias_analizadas
FOR EACH ROW EXECUTE FUNCTION validar_expediente_evidencia_peritaje();

-- No se puede cambiar el expediente de un peritaje una vez creado,
-- pues invalidaria asociaciones de evidencias existentes.
CREATE OR REPLACE FUNCTION proteger_expediente_peritaje()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.expediente_id IS DISTINCT FROM NEW.expediente_id THEN
        RAISE EXCEPTION 'No se permite cambiar el expediente de un peritaje existente';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_expediente_peritaje
BEFORE UPDATE ON peritajes
FOR EACH ROW EXECUTE FUNCTION proteger_expediente_peritaje();

-- ============================================================================
-- INDICES RELACIONALES Y VECTORIALES
-- ============================================================================

CREATE INDEX idx_evidencias_expediente ON evidencias(expediente_id);
CREATE INDEX idx_evidencias_padre ON evidencias(evidencia_padre_id);
CREATE INDEX idx_evidencias_custodio_inicial ON evidencias(custodio_inicial_id);
CREATE INDEX idx_transferencias_evidencia_fecha
    ON transferencias_custodia(evidencia_id, fecha_hora DESC);
CREATE INDEX idx_peritajes_expediente ON peritajes(expediente_id);
CREATE INDEX idx_evidencias_analizadas_peritaje ON evidencias_analizadas(peritaje_id);
CREATE INDEX idx_fotografias_evidencia ON fotografias_evidencia(evidencia_id);
CREATE INDEX idx_documentos_expediente ON documentos_forenses(expediente_id);
CREATE INDEX idx_documentos_peritaje ON documentos_forenses(peritaje_id);
CREATE INDEX idx_emb_texto_documento ON embeddings_texto(documento_id);
CREATE INDEX idx_consultas_funcionario_fecha ON consultas(funcionario_id, fecha_hora DESC);
CREATE INDEX idx_resultados_consulta ON resultados_recuperacion(consulta_id);

-- Indices HNSW: permiten ordenar por distancia coseno usando <=>.
CREATE INDEX idx_emb_texto_hnsw
    ON embeddings_texto USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_emb_imagen_hnsw
    ON embeddings_imagen USING hnsw (embedding vector_cosine_ops);

COMMIT;
