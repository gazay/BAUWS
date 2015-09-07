class CreateTrackedChangesFunction < ActiveRecord::Migration
  def up
    execute <<-SQL
      CREATE OR REPLACE FUNCTION tracked_changes_function() RETURNS TRIGGER AS $$
      DECLARE

        n   JSON;       -- NEW as JSON
        o   JSON;       -- OLD as JSON
        t   TIMESTAMP;  -- current timestamp
        a   RECORD;     -- attribute
        d   TEXT;       -- model name

      BEGIN

        d := TG_ARGV[0];
        t := current_timestamp;
        n := row_to_json(NEW);

        IF (TG_OP = 'UPDATE') THEN
          o := row_to_json(OLD);
        END IF;

        -- select attributes (without pkeys)

        FOR a IN SELECT
          pga.attname AS name
        FROM pg_attribute pga
        LEFT JOIN pg_index pgi ON pgi.indrelid = pga.attrelid AND pga.attnum = ANY(pgi.indkey)
        WHERE pga.attnum > 0 AND
              pgi.indisprimary IS NOT true AND
              pga.attrelid = TG_TABLE_NAME::regclass AND
              NOT pga.attisdropped
        ORDER BY pga.attnum
        LOOP

          IF (TG_OP = 'UPDATE' AND (n->(a.name))::text IS DISTINCT FROM (o->(a.name))::text) OR (TG_OP = 'INSERT') THEN

            -- UPSERT

            UPDATE tracked_changes
            SET
              value       = n->(a.name),
              changed_at  = t
            WHERE
              diffable_type = d AND
              diffable_id   = NEW.id AND
              column_name   = a.name;

            IF NOT FOUND THEN

              BEGIN

                INSERT INTO tracked_changes
                  (diffable_type, diffable_id, column_name, value, changed_at)
                VALUES
                  (d, NEW.id, a.name, n->(a.name), t);

              EXCEPTION
              WHEN unique_violation THEN

                -- handle unique violation (constraint: diffable_type, diffable_id, column_name)
                -- TODO: notice
                -- CHEKME

                UPDATE tracked_changes
                SET
                  value       = n->(a.name),
                  changed_at  = t
                WHERE
                  diffable_type  = d AND
                  diffable_id    = NEW.id AND
                  column_name    = a.name;

              WHEN OTHERS THEN

                -- TODO: notice

                UPDATE tracked_changes
                SET
                  value       = n->(a.name),
                  changed_at  = t
                WHERE
                  diffable_type = d AND
                  diffable_id   = NEW.id AND
                  column_name   = a.name;

              END;
            END IF;
          END IF;
        END LOOP;

        RETURN NEW;

      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def down
    execute <<-SQL
      DROP FUNCTION IF EXISTS tracked_changes_function();
    SQL
  end
end
