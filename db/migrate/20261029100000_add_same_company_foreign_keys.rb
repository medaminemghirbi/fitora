# A gym's row can no longer point at another gym's activity, coach, plan or
# contract, even past the models' same-company validations (update_columns,
# insert_all, a console). Each link gets a second foreign key, on
# (column, company_id) to the parent's (id, company_id) — which takes a unique
# index on the parent. The existing single-column keys stay as they are.
#
# Added NOT VALID, which already checks every row written from then on, then
# validated over the rows already there when none of them breaks it. A link
# that does is left unvalidated and named in the output: such a row already
# exists and wants looking at, and a deploy is no time to find out.
class AddSameCompanyForeignKeys < ActiveRecord::Migration[8.1]
  PARENTS = %i[activities coaches spaces recurring_schedules contract_types packs contracts roles].freeze

  LINKS = [
    [ :contracts, :activity_id, :activities ],
    [ :contracts, :contract_type_id, :contract_types ],
    [ :contracts, :pack_id, :packs ],
    [ :contracts, :renewed_from_id, :contracts ],
    [ :payments, :contract_id, :contracts ],
    [ :visits, :contract_id, :contracts ],
    [ :recurring_schedules, :activity_id, :activities ],
    [ :recurring_schedules, :coach_id, :coaches ],
    [ :recurring_schedules, :space_id, :spaces ],
    [ :sessions, :activity_id, :activities ],
    [ :sessions, :coach_id, :coaches ],
    [ :sessions, :space_id, :spaces ],
    [ :sessions, :recurring_schedule_id, :recurring_schedules ],
    [ :staff_members, :coach_id, :coaches ],
    [ :staff_members, :role_id, :roles ]
  ].freeze

  def up
    PARENTS.each { |table| add_index table, %i[id company_id], unique: true, name: "index_#{table}_on_id_and_company_id" }

    LINKS.each do |table, column, parent|
      name = key_name(table, column)
      add_foreign_key table, parent, column: [ column, :company_id ], primary_key: %i[id company_id], name: name, validate: false

      crossing = select_value(<<~SQL.squish)
        SELECT count(*) FROM #{table} child JOIN #{parent} parent ON parent.id = child.#{column}
        WHERE parent.company_id <> child.company_id
      SQL
      if crossing.to_i.zero?
        validate_foreign_key table, name: name
      else
        say "#{table}.#{column}: #{crossing} row(s) point at another gym's #{parent}. Left NOT VALID: look at them.", true
      end
    end
  end

  def down
    LINKS.each { |table, column, _parent| remove_foreign_key table, name: key_name(table, column) }
    PARENTS.each { |table| remove_index table, name: "index_#{table}_on_id_and_company_id" }
  end

  private

  def key_name(table, column) = "fk_#{table}_#{column}_same_company"
end
