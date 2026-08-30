/**************************************
 Korea NHIS-NSC: observation_period

 Annual NHID_JK eligibility rows define coverage. Consecutive annual rows are
 merged, dates are bounded by estimated birth and recorded death, and invalid
 source years are ignored rather than aborting the ETL.
***************************************/

;WITH eligibility_year AS (
	SELECT DISTINCT
		TRY_CONVERT(INT, person_id) AS person_id,
		TRY_CONVERT(INT, stnd_y) AS coverage_year
	FROM @NHISNSC_rawdata.@NHIS_JK
	WHERE TRY_CONVERT(INT, person_id) IS NOT NULL
	  AND TRY_CONVERT(INT, stnd_y) BETWEEN 1900 AND 2099
),
annual_span AS (
	SELECT
		e.person_id,
		CASE
			WHEN p.year_of_birth BETWEEN 1900 AND 2099
			 AND p.year_of_birth > e.coverage_year
				THEN DATEFROMPARTS(p.year_of_birth, 1, 1)
			ELSE DATEFROMPARTS(e.coverage_year, 1, 1)
		END AS start_date,
		CASE
			WHEN d.death_date IS NOT NULL
			 AND d.death_date < DATEFROMPARTS(e.coverage_year, 12, 31)
				THEN d.death_date
			ELSE DATEFROMPARTS(e.coverage_year, 12, 31)
		END AS end_date
	FROM eligibility_year e
	JOIN @NHISNSC_database.PERSON p
	  ON p.person_id = e.person_id
	LEFT JOIN @NHISNSC_database.DEATH d
	  ON d.person_id = e.person_id
),
valid_span AS (
	SELECT person_id, start_date, end_date
	FROM annual_span
	WHERE start_date <= end_date
),
with_previous AS (
	SELECT
		person_id,
		start_date,
		end_date,
		LAG(end_date) OVER (
			PARTITION BY person_id
			ORDER BY start_date, end_date
		) AS previous_end_date
	FROM valid_span
),
islands AS (
	SELECT
		person_id,
		start_date,
		end_date,
		SUM(
			CASE
				WHEN previous_end_date IS NULL
				  OR DATEADD(DAY, 1, previous_end_date) < start_date
					THEN 1
				ELSE 0
			END
		) OVER (
			PARTITION BY person_id
			ORDER BY start_date, end_date
			ROWS UNBOUNDED PRECEDING
		) AS island_id
	FROM with_previous
)
INSERT INTO @NHISNSC_database.OBSERVATION_PERIOD (
	person_id,
	observation_period_start_date,
	observation_period_end_date,
	period_type_concept_id
)
SELECT
	person_id,
	MIN(start_date),
	MAX(end_date),
	44814725
FROM islands
GROUP BY person_id, island_id;
