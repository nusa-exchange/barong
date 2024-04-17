class ChangePhoneLogic < ActiveRecord::Migration[5.2]
  def change
    add_column :phones, :code_id, :integer, unsigned: true, after: :user_id
    remove_column :phones, :code
    remove_column :phones, :country
    remove_column :phones, :validated_at

    add_index :phones, :code_id
    add_index :phones, [:user_id, :code_id], unique: true
  end
end
