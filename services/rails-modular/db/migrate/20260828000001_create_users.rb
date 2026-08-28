# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # Cognito の sub をそのまま主キーにするため、自動採番の id を使わない。
    create_table :users, id: false do |t|
      t.string :id, null: false, primary_key: true, limit: 64
      t.string :email, null: false
      t.string :display_name, null: false, limit: 50
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
