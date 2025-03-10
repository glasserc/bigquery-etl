  -- This UDF is only applicable in the context of this query;
  -- telemetry data accepts countries as two-digit codes, but FxA
  -- data includes long-form country names. The logic here is specific
  -- to the FxA data.
CREATE TEMP FUNCTION
  udf_contains_tier1_country(x ANY TYPE) AS ( --
    EXISTS(
    SELECT
      country
    FROM
      UNNEST(x) AS country
    WHERE
      country IN ( --
        'United States',
        'France',
        'Germany',
        'United Kingdom',
        'Canada')) );
  --
  -- This UDF is also only applicable in the context of this query.
CREATE TEMP FUNCTION
  udf_contains_registration(x ANY TYPE) AS ( --
    EXISTS(
    SELECT
      event_type
    FROM
      UNNEST(x) AS event_type
    WHERE
      event_type IN ( --
        'fxa_reg - complete')) );
  --
WITH
  windowed AS (
  SELECT
    DATE(submission_timestamp) AS submission_date,
    user_id,
    ROW_NUMBER() OVER w1_unframed AS _n,
    udf_mode_last(ARRAY_AGG(country) OVER w1) AS country,
    udf_contains_tier1_country(ARRAY_AGG(country) OVER w1) AS seen_in_tier1_country,
    udf_contains_registration(ARRAY_AGG(event_type) OVER w1) AS registered
  FROM
    fxa_all_events_v1
  WHERE
    user_id IS NOT NULL
    AND event_type NOT IN ( --
      'fxa_email - bounced',
      'fxa_email - click',
      'fxa_email - sent',
      'fxa_reg - password_blocked',
      'fxa_reg - password_common',
      'fxa_reg - password_enrolled',
      'fxa_reg - password_missing',
      'fxa_sms - sent',
      'mktg - email_click',
      'mktg - email_open',
      'mktg - email_sent',
      'sync - repair_success',
      'sync - repair_triggered')
    AND DATE(submission_timestamp) = @submission_date
  WINDOW
    w1 AS (
    PARTITION BY
      user_id,
      DATE(submission_timestamp)
    ORDER BY
      submission_timestamp --
      ROWS BETWEEN UNBOUNDED PRECEDING
      AND UNBOUNDED FOLLOWING),
    -- We must provide a modified window for ROW_NUMBER which cannot accept a frame clause.
    w1_unframed AS (
    PARTITION BY
      user_id,
      DATE(submission_timestamp)
    ORDER BY
      submission_timestamp) )
SELECT
  * EXCEPT (_n)
FROM
  windowed
WHERE
  _n = 1
