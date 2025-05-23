# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::AccountTransactionsReport do
  # Defined in spec/support/contexts/cross_core_context.rb
  include_context "cross core orders"

  let(:item) { create(:setup_item, facility:, name: "Item for testing & checking") }
  subject(:report) { Reports::AccountTransactionsReport.new(order_details, report_options) }
  let(:report_options) { {} }

  describe "#to_csv" do
    context "with no order details" do
      let(:order_details) { OrderDetail.none }

      it "generates a header" do
        expect(report.to_csv.lines.count).to eq(1)
      end
    end

    context "with one order detail" do
      let!(:order_detail) { create(:purchased_reservation).order_detail }
      let(:order_details) { OrderDetail }

      it "generates an order detail line" do
        expect(report.to_csv.lines.count).to eq(11)
      end

      it "generates headers with Cross Core Project Facility" do
        expect(report.to_csv.lines.first).to include("Cross Core Project Facility")
      end

      it "includes the order detail's cross core project facility" do
        expect(report.to_csv.lines.second).to include(cross_core_project.facility.abbreviation)
      end

      it "includes the product's name" do
        expect(report.to_csv.lines.second).to include(item.name)
      end

      describe "with estimated label_key_prefix" do
        let(:report_options) { { label_key_prefix: :estimated } }

        it "generates headers with Estimated" do
          expect(report.to_csv.lines.first).to include("Estimated Price,Estimated Adjustment,Estimated Total")
        end
      end

      describe "with nil label_key_prefix" do
        it "generates headers without Estimated" do
          expect(report.to_csv.lines.first).to include("Price,Adjustment,Total")
        end
      end

      describe "excludes the order's dispute details if feature is OFF", feature_setting: { export_order_disputes: false } do
        it "generates headers without Dispute details" do
          expect(report.to_csv.lines.first).not_to include(
            OrderDetail.human_attribute_name(:dispute_at),
            OrderDetail.human_attribute_name(:dispute_reason),
            OrderDetail.human_attribute_name(:dispute_resolved_at),
            OrderDetail.human_attribute_name(:dispute_resolved_reason)
          )
        end
      end

      describe "includes the order's dispute details if feature is ON", feature_setting: { export_order_disputes: true } do
        it "generates headers with Dispute details" do
          expect(report.to_csv.lines.first).to include(
            OrderDetail.human_attribute_name(:dispute_at),
            OrderDetail.human_attribute_name(:dispute_reason),
            OrderDetail.human_attribute_name(:dispute_resolved_at),
            OrderDetail.human_attribute_name(:dispute_resolved_reason)
          )
        end
      end
    end
  end
end
