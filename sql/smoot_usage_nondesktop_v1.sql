
--
CREATE OR REPLACE VIEW
  `moz-fx-data-derived-datasets.telemetry.smoot_usage_nondesktop_v1` AS
WITH
  base AS (
  SELECT
    *
  FROM
    `moz-fx-data-derived-datasets.telemetry.smoot_usage_nondesktop_raw_v1` ),
  --
  daily AS (
  SELECT
    submission_date AS `date`,
    metrics_daily.*,
    * EXCEPT (new_profiles)
  FROM
    base,
    UNNEST(metrics) ),
  --
  new_profile_week1 AS (
  SELECT
    DATE_SUB(submission_date, INTERVAL 6 day) AS `date`,
    metrics_1_week_post_new_profile.*,
    *
  FROM
    base,
    UNNEST(metrics) ),
  --
  new_profile_week2 AS (
  SELECT
    DATE_SUB(submission_date, INTERVAL 13 day) AS `date`,
    metrics_2_week_post_new_profile.*,
    * EXCEPT (new_profiles)
  FROM
    base,
    UNNEST(metrics) ),
  --
  joined AS (
  SELECT
  * EXCEPT (submission_date,
    metrics,
    metrics_daily,
    metrics_1_week_post_new_profile,
    metrics_2_week_post_new_profile)
  FROM
    daily
  FULL JOIN
    new_profile_week1
  USING
    (`date`,
      usage,
      id_bucket,
      app_name,
      app_version,
      country,
      os,
      channel)
  FULL JOIN
    new_profile_week2
  USING
    (`date`,
      usage,
      id_bucket,
      app_name,
      app_version,
      country,
      os,
      channel) )
  --
SELECT
  * EXCEPT(app_name)
FROM
  joined
  --
UNION ALL
  -- Also present each app as its own usage criterion. App names are documented in
  -- https://docs.telemetry.mozilla.org/concepts/choosing_a_dataset_mobile.html#products-overview
SELECT
  * EXCEPT(app_name)
    REPLACE (
    REPLACE(usage,
      'Firefox Non-desktop',
      CASE app_name
        WHEN 'Fennec' THEN CONCAT(app_name, ' ', os)
        WHEN 'Focus' THEN CONCAT(app_name, ' ', os)
        WHEN 'Zerda' THEN 'Firefox Lite'
        ELSE app_name
      END) AS usage)
FROM
  joined
