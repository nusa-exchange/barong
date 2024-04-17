class AddDataToCodes < ActiveRecord::Migration[5.2]
  def change
    add_column :codes, :code_id, :text, after: :expired_at
  end
end
