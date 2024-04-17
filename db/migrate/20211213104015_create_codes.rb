class CreateCodes < ActiveRecord::Migration[5.2]
  def change
    create_table :codes do |t|
      t.integer :user_id, unsigned: true
      t.string :code, limit: 6, null: false
      t.string :code_type, limit: 10, null: false
      t.string :category, limit: 20, null: false
      t.string :email_encrypted
      t.bigint :email_index
      t.string :phone_number_encrypted
      t.bigint :phone_number_index
      t.integer :attempt_count, default: 0, null: false
      t.datetime :validated_at
      t.datetime :expired_at, null: false

      t.timestamps
      t.index :user_id
      t.index :email_index
      t.index :phone_number_index
    end
  end
end
