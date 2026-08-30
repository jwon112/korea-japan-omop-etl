/*********************************************************************************
# Copyright 2014 Observational Health Data Sciences and Informatics
#
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
********************************************************************************/

/************************
 ####### #     # ####### ######      #####  ######  #     #           ####### 
 #     # ##   ## #     # #     #    #     # #     # ##   ##    #    # #       
 #     # # # # # #     # #     #    #       #     # # # # #    #    # #       
 #     # #  #  # #     # ######     #       #     # #  #  #    #    # ######  
 #     # #     # #     # #          #       #     # #     #    #    #       # 
 #     # #     # #     # #          #     # #     # #     #     #  #  #     # 
 ####### #     # ####### #           #####  ######  #     #      ##    #####  
                                                                              
Script to load the common data model, version 5.0 vocabulary tables for SQL Server database
Notes
1) There is no data file load for the SOURCE_TO_CONCEPT_MAP table because that table is deprecated in CDM version 5.0
2) This script assumes the CDM version 5 vocabulary zip file has been unzipped into the "@vocaFolderulary" directory. 
3) If you unzipped your CDM version 5 vocabulary files into a different directory then replace all file paths below, with your directory path.
4) Run this SQL query script in the database where you created your CDM Version 5 tables
last revised: 26 Nov 2014
author:  Lee Evans
*************************/
USE @Mapping_database;

/* ---------------------------------------------------------------------------
   Unicode safety for OMOP vocabulary
   - Vocabulary files are UTF-8 and include multibyte characters.
   - CDM DDL defines many columns as VARCHAR(n). In SQL Server, VARCHAR(n) limits bytes,
     so some rows can fail to load (e.g., concept_name) even when character length <= n.
   - To make import robust, convert VARCHAR columns in vocabulary tables to NVARCHAR
     (same length). This avoids byte-length conversion failures.
--------------------------------------------------------------------------- */
DECLARE @sql NVARCHAR(MAX) = N'';

;WITH targets AS (
  SELECT t.object_id
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  WHERE s.name = N'dbo'
    AND t.name IN (
      N'CONCEPT', N'CONCEPT_SYNONYM', N'CONCEPT_RELATIONSHIP', N'CONCEPT_ANCESTOR',
      N'DRUG_STRENGTH', N'VOCABULARY', N'DOMAIN', N'CONCEPT_CLASS', N'RELATIONSHIP',
      N'source_to_concept_map'
    )
),
cols AS (
  SELECT
    QUOTENAME(OBJECT_SCHEMA_NAME(c.object_id)) AS sch,
    QUOTENAME(OBJECT_NAME(c.object_id)) AS tbl,
    QUOTENAME(c.name) AS col,
    c.max_length,
    c.is_nullable
  FROM targets t
  JOIN sys.columns c ON c.object_id = t.object_id
  JOIN sys.types ty ON c.user_type_id = ty.user_type_id
  WHERE ty.name = N'varchar'
)
SELECT
  @sql = @sql + N'ALTER TABLE ' + sch + N'.' + tbl
      + N' ALTER COLUMN ' + col + N' NVARCHAR('
      + CASE WHEN max_length = -1 THEN N'MAX' ELSE CONVERT(NVARCHAR(10), max_length) END
      + N') ' + CASE WHEN is_nullable = 1 THEN N'NULL' ELSE N'NOT NULL' END
      + N';' + CHAR(10)
FROM cols;

IF (@sql <> N'')
BEGIN
  EXEC sp_executesql @sql;
END

-- 1. CONCEPT
TRUNCATE TABLE CONCEPT;
BULK INSERT CONCEPT FROM '@vocaFolder\CONCEPT.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 2. CONCEPT_SYNONYM
TRUNCATE TABLE CONCEPT_SYNONYM;
BULK INSERT CONCEPT_SYNONYM FROM '@vocaFolder\CONCEPT_SYNONYM.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 3. CONCEPT_RELATIONSHIP
TRUNCATE TABLE CONCEPT_RELATIONSHIP;
BULK INSERT CONCEPT_RELATIONSHIP FROM '@vocaFolder\CONCEPT_RELATIONSHIP.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 4. CONCEPT_ANCESTOR
TRUNCATE TABLE CONCEPT_ANCESTOR;
BULK INSERT CONCEPT_ANCESTOR FROM '@vocaFolder\CONCEPT_ANCESTOR.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 5. DRUG_STRENGTH
TRUNCATE TABLE DRUG_STRENGTH;
BULK INSERT DRUG_STRENGTH FROM '@vocaFolder\DRUG_STRENGTH.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 6. VOCABULARY
TRUNCATE TABLE VOCABULARY;
BULK INSERT VOCABULARY FROM '@vocaFolder\VOCABULARY.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 7. DOMAIN
TRUNCATE TABLE DOMAIN;
BULK INSERT DOMAIN FROM '@vocaFolder\DOMAIN.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 8. CONCEPT_CLASS
TRUNCATE TABLE CONCEPT_CLASS;
BULK INSERT CONCEPT_CLASS FROM '@vocaFolder\CONCEPT_CLASS.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 9. RELATIONSHIP
TRUNCATE TABLE RELATIONSHIP;
BULK INSERT RELATIONSHIP FROM '@vocaFolder\RELATIONSHIP.csv' 
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

-- 10. SOURCE_TO_CONCEPT_MAP (from CONCEPT_RELATIONSHIP "Maps to" + CONCEPT)
-- Deprecated in CDM v5 but still used by this ETL; populated from vocabulary so ETL can join by source_code + domain_id.
TRUNCATE TABLE source_to_concept_map;
INSERT INTO source_to_concept_map (
  source_code,
  source_concept_id,
  source_vocabulary_id,
  source_code_description,
  target_concept_id,
  target_vocabulary_id,
  valid_start_date,
  valid_end_date,
  invalid_reason,
  domain_id
)
SELECT
  c1.concept_code,
  c1.concept_id,
  c1.vocabulary_id,
  c1.concept_name,
  c2.concept_id,
  c2.vocabulary_id,
  cr.valid_start_date,
  cr.valid_end_date,
  cr.invalid_reason,
  c2.domain_id
FROM CONCEPT c1
JOIN CONCEPT_RELATIONSHIP cr
  ON c1.concept_id = cr.concept_id_1
 AND cr.relationship_id = 'Maps to'
 AND (cr.invalid_reason IS NULL OR cr.invalid_reason = '')
JOIN CONCEPT c2
  ON cr.concept_id_2 = c2.concept_id
 AND (c2.invalid_reason IS NULL OR c2.invalid_reason = '')
 AND c2.domain_id IS NOT NULL
WHERE c1.concept_code IS NOT NULL
  AND c1.vocabulary_id IS NOT NULL;