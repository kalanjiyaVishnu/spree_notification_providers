# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::NotificationDeliveries::PurgeJob do
  let(:store) { @default_store }

  it 'deletes rows older than the retention period and keeps newer ones' do
    old = create(:notification_delivery, store: store, created_at: 91.days.ago)
    recent = create(:notification_delivery, store: store, created_at: 89.days.ago)

    expect(described_class.perform_now).to eq(1)
    expect(Spree::NotificationDelivery.exists?(old.id)).to be(false)
    expect(Spree::NotificationDelivery.exists?(recent.id)).to be(true)
  end

  it 'follows the configured retention' do
    allow(SpreeNotificationProviders.configuration).to receive(:delivery_retention_days).and_return(7)
    create(:notification_delivery, store: store, created_at: 8.days.ago)

    expect(described_class.perform_now).to eq(1)
  end
end
