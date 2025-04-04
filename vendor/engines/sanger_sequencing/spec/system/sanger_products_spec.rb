# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sanger Products", :disable_requests_local, feature_setting: { sanger_enabled_service: true } do
  let(:facility) { create(:setup_facility, sanger_sequencing_enabled: true) }
  let(:service) { create(:setup_service, facility:, sanger_sequencing_enabled: true) }
  let(:admin) { create(:user, :facility_administrator, facility:) }
  let(:user) { create(:user) }
  let(:show_path) do
    facility_service_sanger_sequencing_sanger_product_path(facility, service)
  end

  describe "admin tab" do
    context "when not logged in" do
      it "redirects to login" do
        visit show_path

        expect(page).to have_content("Login")
        expect(page).to_not have_content("Sanger")
        expect(page).to_not have_content(service.name)
      end
    end

    context "when logged in as normal user" do
      before { login_as user }

      it "renders permission denied" do
        visit show_path

        expect(page).to have_content("Permission Denied")
      end
    end

    context "when logged in as facility admin" do
      before { login_as admin }

      it "requires the facility to be sanger enabled" do
        facility.update(sanger_sequencing_enabled: false)

        visit show_path

        expect(page).to have_content("Not Found")
      end

      it "does not show the tab if service is sanger disabled" do
        service.update(sanger_sequencing_enabled: false)

        visit show_path

        within(".nav-tabs") do
          expect(page).to_not have_content("Sanger")
        end
      end

      it "shows the tab if service is sanger enabled" do
        visit show_path

        within(".nav-tabs") do
          expect(page).to have_content("Sanger")
        end
      end
    end
  end

  describe "sanger product show" do
    before { login_as admin }

    it "can navigate by clicking the tab" do
      visit manage_facility_service_path(facility, service)

      within(".nav-tabs") do
        click_link("Sanger")
      end

      expect(page).to have_content("Sanger Configuration")
    end

    it "shows sanger product information" do
      visit show_path

      expect(page).to have_content("Sanger Configuration")
      expect(page).to have_content("Needs a Primer")
      expect(page).to have_content("Plated Service Type")
      expect(page).to have_link("Edit")
    end

    it "allows to edit sanger product" do
      visit show_path

      click_link("Edit")

      check("sanger_sequencing_sanger_product[needs_primer]")

      select("Fragment Analysis", from: "sanger_sequencing_sanger_product[group]")

      click_button("Save")

      expect(page).to have_content("Sanger Configuration updated successfully")
    end

    describe "primers change" do
      let(:sanger_product) { service.create_sanger_product }
      let(:primers) do
        facility.sanger_sequencing_primers.insert_all([{ name: "Watermelon" }, { name: "Tomato" }])
        facility.sanger_sequencing_primers.all
      end

      before do
        sanger_product.update(primers:)
      end

      it "show primers section when it's enabled" do
        sanger_product.update(needs_primer: true)

        visit show_path

        expect(page).to have_content("Watermelon")
        expect(page).to have_content("Tomato")
      end

      it "does not show section when it's disabled" do
        sanger_product.update(needs_primer: false)

        visit show_path

        expect(page).to_not have_content("Watermelon")
        expect(page).to_not have_content("Tomato")
      end

      it "can deselect primers" do
        sanger_product.update(needs_primer: true)

        visit show_path

        click_link("Edit")

        unselect("Tomato", from: "sanger_sequencing_sanger_product[primer_ids][]")

        click_button("Save")

        expect(page).to have_content("Watermelon")
        expect(page).to_not have_content("Tomato")
      end
    end
  end
end
