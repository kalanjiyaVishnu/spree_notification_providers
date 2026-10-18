# frozen_string_literal: true

class CreateSpreeNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_notification_deliveries do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores }, index: false
      t.uuid :message_ref, null: false
      t.string :channel, null: false
      t.string :provider_key
      t.string :message_type, null: false
      t.string :recipient, null: false
      t.string :outcome, null: false
      t.string :reason, limit: 255
      t.string :provider_message_id
      t.integer :attempt_number
      t.boolean :bulk, null: false, default: false
      t.string :source_type
      t.bigint :source_id
      t.datetime :created_at, null: false
    end

    add_index :spree_notification_deliveries, %i[store_id created_at], name: 'idx_spree_notif_deliveries_on_store_created'
    add_index :spree_notification_deliveries, %i[store_id channel outcome created_at],
              name: 'idx_spree_notif_deliveries_on_store_channel_outcome'
    add_index :spree_notification_deliveries, :message_ref
    add_index :spree_notification_deliveries, :provider_message_id
    add_index :spree_notification_deliveries, %i[source_type source_id]
  end
end
