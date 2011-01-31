class CreatePayments < ActiveRecord::Migration
  def self.up
    create_table :payments do |t|
      t.decimal :amount, :null => false, :precision => 15, :scale => 2
      t.decimal :paid, :null => false, :precision => 15, :scale => 2
      t.references :payable, :polymorphic => true
      t.integer :lock_version, :default => 0

      t.timestamps
    end

    add_index :payments, [:payable_id, :payable_type]
  end

  def self.down
    remove_index :payments, :column => [:payable_id, :payable_type]

    drop_table :payments
  end
end