/**************************************
 Korea NHIS-NSC: measurement

 Reuse the typed and indexed GJ_VERTICAL staging built by observation. The
 reviewed health-check mapping seeds are vocabulary-guarded, and numeric plus
 categorical measurements are loaded in one visit-anchored insert.
***************************************/

IF OBJECT_ID('tempdb..#measurement_mapping', 'U') IS NOT NULL
    DROP TABLE #measurement_mapping;

CREATE TABLE #measurement_mapping (
    meas_type VARCHAR(50) NOT NULL,
    id_value INT NOT NULL,
    answer BIGINT NULL,
    is_categorical BIT NOT NULL,
    measurement_concept_id INT NOT NULL,
    measurement_type_concept_id INT NOT NULL,
    measurement_unit_concept_id INT NULL,
    value_as_concept_id INT NULL,
    value_as_number FLOAT NULL
);

INSERT INTO #measurement_mapping (
    meas_type, id_value, answer, is_categorical,
    measurement_concept_id, measurement_type_concept_id,
    measurement_unit_concept_id, value_as_concept_id, value_as_number
)
VALUES
    ('HEIGHT',       1, NULL, 0, 3036277, 44818701, 8582, NULL, NULL),
    ('WEIGHT',       2, NULL, 0, 3025315, 44818701, 9529, NULL, NULL),
    ('WAIST',        3, NULL, 0, 3016258, 44818701, 8582, NULL, NULL),
    ('BP_HIGH',      4, NULL, 0, 3004249, 44818701, 8876, NULL, NULL),
    ('BP_LWST',      5, NULL, 0, 3012888, 44818701, 8876, NULL, NULL),
    ('BLDS',         6, NULL, 0, 3037110, 44818702, 8840, NULL, NULL),
    ('TOT_CHOLE',    7, NULL, 0, 3027114, 44818702, 8840, NULL, NULL),
    ('TRIGLYCERIDE', 8, NULL, 0, 3022192, 44818702, 8840, NULL, NULL),
    ('HDL_CHOLE',    9, NULL, 0, 3007070, 44818702, 8840, NULL, NULL),
    ('LDL_CHOLE',   10, NULL, 0, 3028437, 44818702, 8840, NULL, NULL),
    ('HMG',         11, NULL, 0, 3000963, 44818702, 8713, NULL, NULL),
    ('GLY_CD',      12, 1, 1, 3009261, 44818702, NULL, 9189, NULL),
    ('GLY_CD',      12, 2, 1, 3009261, 44818702, NULL, 4127785, NULL),
    ('GLY_CD',      12, 3, 1, 3009261, 44818702, NULL, 4123508, NULL),
    ('GLY_CD',      12, 4, 1, 3009261, 44818702, NULL, 4126673, NULL),
    ('GLY_CD',      12, 5, 1, 3009261, 44818702, NULL, 4125547, NULL),
    ('GLY_CD',      12, 6, 1, 3009261, 44818702, NULL, 4126674, NULL),
    ('OLIG_OCCU_CD',13, 1, 1, 3011397, 44818702, NULL, 9189, NULL),
    ('OLIG_OCCU_CD',13, 2, 1, 3011397, 44818702, NULL, 4127785, NULL),
    ('OLIG_OCCU_CD',13, 3, 1, 3011397, 44818702, NULL, 4123508, NULL),
    ('OLIG_OCCU_CD',13, 4, 1, 3011397, 44818702, NULL, 4126673, NULL),
    ('OLIG_OCCU_CD',13, 5, 1, 3011397, 44818702, NULL, 4125547, NULL),
    ('OLIG_OCCU_CD',13, 6, 1, 3011397, 44818702, NULL, 4126674, NULL),
    ('OLIG_PH',     14, NULL, 0, 3022621, 44818702, 8482, NULL, NULL),
    ('OLIG_PROTE_CD',15, 1, 1, 3014051, 44818702, NULL, 9189, NULL),
    ('OLIG_PROTE_CD',15, 2, 1, 3014051, 44818702, NULL, 4127785, NULL),
    ('OLIG_PROTE_CD',15, 3, 1, 3014051, 44818702, NULL, 4123508, NULL),
    ('OLIG_PROTE_CD',15, 4, 1, 3014051, 44818702, NULL, 4126673, NULL),
    ('OLIG_PROTE_CD',15, 5, 1, 3014051, 44818702, NULL, 4125547, NULL),
    ('OLIG_PROTE_CD',15, 6, 1, 3014051, 44818702, NULL, 4126674, NULL),
    ('CREATININE',  16, NULL, 0, 3016723, 44818702, 8840, NULL, NULL),
    ('SGOT_AST',    17, NULL, 0, 3013721, 44818702, 8645, NULL, NULL),
    ('SGPT_ALT',    18, NULL, 0, 3006923, 44818702, 8645, NULL, NULL),
    ('GAMMA_GTP',   19, NULL, 0, 3026910, 44818702, 8645, NULL, NULL);

UPDATE m
SET measurement_concept_id = 0
FROM #measurement_mapping m
LEFT JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = m.measurement_concept_id
WHERE c.concept_id IS NULL
   OR c.domain_id <> 'Measurement'
   OR ISNULL(c.standard_concept, '') <> 'S'
   OR c.invalid_reason IS NOT NULL;

UPDATE m
SET measurement_type_concept_id = 0
FROM #measurement_mapping m
LEFT JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = m.measurement_type_concept_id
WHERE c.concept_id IS NULL
   OR c.domain_id <> 'Type Concept'
   OR c.invalid_reason IS NOT NULL;

UPDATE m
SET measurement_unit_concept_id = NULL
FROM #measurement_mapping m
LEFT JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = m.measurement_unit_concept_id
WHERE m.measurement_unit_concept_id IS NOT NULL
  AND (
      c.concept_id IS NULL
      OR c.domain_id <> 'Unit'
      OR ISNULL(c.standard_concept, '') <> 'S'
      OR c.invalid_reason IS NOT NULL
  );

UPDATE m
SET value_as_concept_id = NULL
FROM #measurement_mapping m
LEFT JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = m.value_as_concept_id
WHERE m.value_as_concept_id IS NOT NULL
  AND (
      c.concept_id IS NULL
      OR ISNULL(c.standard_concept, '') <> 'S'
      OR c.invalid_reason IS NOT NULL
  );

CREATE UNIQUE CLUSTERED INDEX IX_measurement_mapping_type_answer
    ON #measurement_mapping (meas_type, answer);
GO

INSERT INTO @NHISNSC_database.MEASUREMENT (
    measurement_id,
    person_id,
    measurement_concept_id,
    measurement_date,
    measurement_time,
    measurement_type_concept_id,
    operator_concept_id,
    value_as_number,
    value_as_concept_id,
    unit_concept_id,
    range_low,
    range_high,
    provider_id,
    visit_occurrence_id,
    measurement_source_value,
    measurement_source_concept_id,
    unit_source_value,
    value_source_value
)
SELECT
    c.master_seq * CONVERT(BIGINT, 100) + m.id_value,
    a.person_id,
    m.measurement_concept_id,
    TRY_CONVERT(DATE, CONCAT(a.hchk_year, '0101'), 112),
    NULL,
    m.measurement_type_concept_id,
    NULL,
    CASE
        WHEN m.is_categorical = 1 THEN m.value_as_number
        ELSE TRY_CONVERT(FLOAT, a.meas_value)
    END,
    m.value_as_concept_id,
    m.measurement_unit_concept_id,
    NULL,
    NULL,
    NULL,
    c.master_seq,
    a.meas_type,
    NULL,
    NULL,
    a.meas_value
FROM @NHISNSC_database.GJ_VERTICAL a
JOIN #measurement_mapping m
  ON m.meas_type = a.meas_type
 AND (
      (m.is_categorical = 1 AND TRY_CONVERT(BIGINT, a.meas_value) = m.answer)
      OR
      (m.is_categorical = 0 AND TRY_CONVERT(FLOAT, a.meas_value) IS NOT NULL)
 )
JOIN @NHISNSC_database.SEQ_MASTER c
  ON c.source_table = 'GJT'
 AND c.person_id = a.person_id
 AND c.hchk_year = a.hchk_year
JOIN @NHISNSC_database.VISIT_OCCURRENCE v
  ON v.visit_occurrence_id = c.master_seq
 AND v.person_id = c.person_id
WHERE NULLIF(LTRIM(RTRIM(a.meas_value)), '') IS NOT NULL
  AND TRY_CONVERT(DATE, CONCAT(a.hchk_year, '0101'), 112)
      BETWEEN v.visit_start_date AND v.visit_end_date
OPTION (RECOMPILE, MAXDOP 2);
GO

DROP TABLE #measurement_mapping;
GO
