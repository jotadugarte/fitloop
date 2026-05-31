class CreateUserEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :user_events do |t|
      t.string :event_type, null: false
      t.string :priority, null: false, default: "low"
      t.jsonb :properties, null: false, default: {}
      t.references :user, null: true, foreign_key: true
      t.string :anonymous_session_key
      t.string :tab_id
      t.bigint :project_id
      t.bigint :nesting_run_id
      t.string :ip
      t.string :user_agent
      t.string :country_code
      t.string :locale
      t.string :idempotency_key
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :user_events, :event_type
    add_index :user_events, :occurred_at
    add_index :user_events, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
  end
end
