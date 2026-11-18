BEGIN;

-- Each soul tracks the number of absorbed essences for each of the five
-- reincarnation attributes. The next reward requires twice as many additional
-- matching absorptions as the previous reward: cumulative thresholds
-- 3, 9, 21, 45, 93, 189, 381, 765, 1533, 3069.
CREATE TABLE soul_absorption_attribute_progress (
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    attribute VARCHAR(24) NOT NULL CHECK (attribute IN
        ('strength','constitution','agility','spirit','vitality')),
    absorbed_count BIGINT NOT NULL DEFAULT 0 CHECK (absorbed_count >= 0),
    awarded_points SMALLINT NOT NULL DEFAULT 0 CHECK (awarded_points BETWEEN 0 AND 10),
    applied_points SMALLINT NOT NULL DEFAULT 0 CHECK (applied_points BETWEEN 0 AND 10),
    max_points SMALLINT NOT NULL DEFAULT 10 CHECK (max_points = 10),
    next_threshold BIGINT NOT NULL DEFAULT 3 CHECK (next_threshold >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (soul_id, attribute),
    CHECK (applied_points <= awarded_points)
);

ALTER TABLE soul_absorption_records
    ADD COLUMN attribute_points_awarded SMALLINT NOT NULL DEFAULT 0
    CHECK (attribute_points_awarded BETWEEN 0 AND 1);

-- The hard cap applies to all permanent reincarnation-attribute sources,
-- including absorption milestones, mutations, rare essence choices and fusions.
UPDATE soul_inheritance_attributes
SET strength = LEAST(strength, 20),
    constitution = LEAST(constitution, 20),
    agility = LEAST(agility, 20),
    spirit = LEAST(spirit, 20),
    vitality = LEAST(vitality, 20);

ALTER TABLE soul_inheritance_attributes
    ADD CONSTRAINT chk_soul_inheritance_attribute_caps
    CHECK (
        strength <= 20 AND constitution <= 20 AND agility <= 20 AND
        spirit <= 20 AND vitality <= 20
    );

WITH attributes(attribute) AS (
    VALUES ('strength'),('constitution'),('agility'),('spirit'),('vitality')
),
counts AS (
    SELECT soul.id AS soul_id,
           attributes.attribute,
           COUNT(records.id)::BIGINT AS absorbed_count
    FROM souls soul
    CROSS JOIN attributes
    LEFT JOIN soul_absorption_records records
      ON records.soul_id = soul.id
    LEFT JOIN soul_absorption_kinds kinds
      ON kinds.id = records.absorption_kind_id
    WHERE COALESCE(kinds.inheritance_attribute, records.selected_attribute) = attributes.attribute
    GROUP BY soul.id, attributes.attribute
),
earned AS (
    SELECT counts.*,
           (SELECT COUNT(*)::SMALLINT
            FROM generate_series(1,10) AS milestone(level)
            WHERE counts.absorbed_count >=
                3 * ((1::BIGINT << milestone.level) - 1)) AS awarded_points
    FROM counts
),
applied AS (
    SELECT earned.*,
           LEAST(earned.awarded_points,
             GREATEST(0, 20 - CASE earned.attribute
               WHEN 'strength' THEN inheritance.strength
               WHEN 'constitution' THEN inheritance.constitution
               WHEN 'agility' THEN inheritance.agility
               WHEN 'spirit' THEN inheritance.spirit
               WHEN 'vitality' THEN inheritance.vitality
             END))::SMALLINT AS applied_points
    FROM earned
    JOIN soul_inheritance_attributes inheritance ON inheritance.soul_id = earned.soul_id
)
INSERT INTO soul_absorption_attribute_progress
    (soul_id,attribute,absorbed_count,awarded_points,applied_points,next_threshold)
SELECT soul_id,attribute,absorbed_count,awarded_points,applied_points,
       CASE WHEN awarded_points >= 10 THEN 0
            ELSE 3 * ((1::BIGINT << (awarded_points + 1)) - 1) END
FROM applied
ON CONFLICT (soul_id,attribute) DO NOTHING;

-- Preserve fair progress for players who absorbed matching souls before this
-- progression system was introduced.
UPDATE soul_inheritance_attributes inheritance
SET strength = LEAST(20, inheritance.strength + progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'strength';

UPDATE soul_inheritance_attributes inheritance
SET constitution = LEAST(20, inheritance.constitution + progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'constitution';

UPDATE soul_inheritance_attributes inheritance
SET agility = LEAST(20, inheritance.agility + progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'agility';

UPDATE soul_inheritance_attributes inheritance
SET spirit = LEAST(20, inheritance.spirit + progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'spirit';

UPDATE soul_inheritance_attributes inheritance
SET vitality = LEAST(20, inheritance.vitality + progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'vitality';

-- Mark historical absorption records that crossed a milestone for auditability.
WITH ranked AS (
    SELECT records.id,
           ROW_NUMBER() OVER (
             PARTITION BY records.soul_id, COALESCE(kinds.inheritance_attribute, records.selected_attribute)
             ORDER BY records.created_at, records.id
           ) AS ordinal,
           COALESCE(kinds.inheritance_attribute, records.selected_attribute) AS attribute
    FROM soul_absorption_records records
    JOIN soul_absorption_kinds kinds ON kinds.id = records.absorption_kind_id
    WHERE COALESCE(kinds.inheritance_attribute, records.selected_attribute) IS NOT NULL
),
milestones AS (
    SELECT 3 * ((1::BIGINT << level) - 1) AS threshold
    FROM generate_series(1,10) AS level
)
UPDATE soul_absorption_records records
SET attribute_points_awarded = 1
FROM ranked
JOIN milestones ON milestones.threshold = ranked.ordinal
WHERE records.id = ranked.id;

COMMIT;
