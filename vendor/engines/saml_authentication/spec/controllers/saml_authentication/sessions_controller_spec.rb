# frozen_string_literal: true

require "rails_helper"

RSpec.describe SamlAuthentication::SessionsController, type: :controller do
  # Utility class to expose some private methods of SamlMessage
  class SamlEncoder < OneLogin::RubySaml::SamlMessage

    def self.decode(saml)
      new.send(:decode_raw_saml, saml)
    end

    def self.encode(saml)
      encoded = new.send(:encode_raw_saml, saml, OpenStruct.new(compress_request: true))
      # encode_raw_saml url-encodes the encoded saml so it's correctly sent over http.
      # Since this is a controller spec we don't have the automatic url-decoding step on params.
      CGI.unescape(encoded)
    end

  end

  describe "#create" do
    # based on a onelogin response
    let(:attribute_map) do
      {
        "PersonImmutableID" => "username",
        "User.email" => "email",
        "User.FirstName" => "first_name",
        "User.LastName" => "last_name",
      }
    end

    let(:saml_response) do
      Base64.encode64(File.read(File.expand_path("../../fixtures/login_response.xml", __dir__)))
    end

    before do
      request.env["devise.mapping"] = Devise.mappings[:user]
      allow_any_instance_of(SamlAuthentication::AttributeMapResolver).to receive(:attribute_map).and_return(attribute_map)
      # Our response fixure is old, so don't worry about it
      allow(Devise).to receive(:allowed_clock_drift_in_seconds).and_return(1000.years)
    end

    around :each do |example|
      original_value = Devise.saml_update_resource_hook
      Devise.saml_update_resource_hook = SamlAuthentication::UserUpdater.new

      example.run

      Devise.saml_update_resource_hook = original_value
    end

    describe "the user does not exist already" do
      around :each do |example|
        original_value = Devise.saml_create_user
        Devise.saml_create_user = true

        example.run

        Devise.saml_create_user = original_value
      end

      it "creates a user" do
        expect { post :create, params: { SAMLResponse: saml_response } }.to change(User, :count).by(1)
      end

      it "logs in the user and sets the first/last names" do
        post :create, params: { SAMLResponse: saml_response }
        expect(controller.current_user.email).to eq("sst123@example.com")
        expect(controller.current_user.username).to eq("sst123")
        expect(controller.current_user.first_name).to eq("Sam")
        expect(controller.current_user.last_name).to eq("Student")
      end

      it "has no password on the new user" do
        post :create, params: { SAMLResponse: saml_response }
        expect(controller.current_user.encrypted_password).to be_nil
      end
    end

    context "when auto-creation of users is disabled and a user does not exist" do
      around :each do |example|
        original_value = Devise.saml_create_user
        Devise.saml_create_user = false
        example.run
        Devise.saml_create_user = original_value
      end

      it "sets a user-friendly error message in the flash" do
        post :create, params: { SAMLResponse: saml_response }
        expect(flash[:alert]).to eq(I18n.t("devise.failure.saml_invalid", username: "sst123", email: "sst123@example.com"))
      end

      it "marks the message in :saml_invalid as html_safe to allow including links" do
        post :create, params: { SAMLResponse: saml_response }
        expect(flash[:alert].html_safe?).to be true
      end
    end

    describe "an email-based user exists" do
      around :each do |example|
        original_value = Devise.saml_create_user
        Devise.saml_create_user = true

        example.run

        Devise.saml_create_user = original_value
      end

      let!(:user) { create(:user, :external, email: "sst123@example.com", username: "sst123@example.com") }

      it "does not create a new user" do
        expect { post :create, params: { SAMLResponse: saml_response } }.not_to change(User, :count)
      end

      it "is case-insensitive when matching on username" do
        user.update(email: "something_else@example.com", username: "Sst123")
        expect { post :create, params: { SAMLResponse: saml_response } }.not_to change(User, :count)
      end

      it "is case-insensitive when matching on email" do
        user.update(username: "something_else", email: "Sst123@example.com")
        expect { post :create, params: { SAMLResponse: saml_response } }.not_to change(User, :count)
      end

      it "logs in the user" do
        post :create, params: { SAMLResponse: saml_response }
        expect(controller.current_user).to eq(user)
      end

      it "updates the user's username" do
        post :create, params: { SAMLResponse: saml_response }
        expect(user.reload.username).to eq("sst123")
      end

      it "updates the user's first and last name" do
        post :create, params: { SAMLResponse: saml_response }
        expect(user.reload.first_name).to eq("Sam")
        expect(user.last_name).to eq("Student")
      end

      it "clears the password" do
        expect { post :create, params: { SAMLResponse: saml_response } }.to change { user.reload.encrypted_password }.to(nil)
      end
    end

    describe "the netid user already exists" do
      let!(:user) { create(:user, :netid, username: "sst123", email: "something@old.com", password: "iEX1STalready!", password_confirmation: "iEX1STalready!") }

      it "does not create a new user" do
        expect { post :create, params: { SAMLResponse: saml_response } }.not_to change(User, :count)
      end

      it "logs in the user" do
        post :create, params: { SAMLResponse: saml_response }
        expect(controller.current_user).to eq(user)
      end

      it "updates the user's email" do
        post :create, params: { SAMLResponse: saml_response }
        expect(user.reload.email).to eq("sst123@example.com")
      end

      it "updates the user's first and last name" do
        post :create, params: { SAMLResponse: saml_response }
        expect(user.reload.first_name).to eq("Sam")
        expect(user.last_name).to eq("Student")
      end

      it "clears the password" do
        expect { post :create, params: { SAMLResponse: saml_response } }.to change { user.reload.encrypted_password }.to(nil)
      end
    end

    describe "the netid user already exists and validation fails" do
      let!(:external_user) { create(:user, :external, email: "sst123@example.com", username: "sst123@example.com") }
      let!(:user) { create(:user, :netid, username: "sst123", email: "something@old.com") }

      it "does not log in the user" do
        post :create, params: { SAMLResponse: saml_response }
        expect(controller.current_user).to be_blank
      end

      it "sets a user-friendly error message in the flash" do
        post :create, params: { SAMLResponse: saml_response }
        expect(flash[:alert]).to eq(I18n.t("devise.failure.saml_update_failed"))
      end

      it "marks the message in :saml_update_failed as html_safe to allow including links" do
        post :create, params: { SAMLResponse: saml_response }
        expect(flash[:alert].html_safe?).to be true
      end
    end
  end

  describe "#destroy" do
    let(:user) { create(:user) }
    before do
      request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in user
    end

    it "logs the user out logout" do
      delete :destroy
      expect(controller.current_user).to be_blank
    end

    it "redirects to the slo path" do
      delete :destroy
      expect(response.location).to start_with(Devise.saml_config.idp_slo_service_url)
    end

    it "includes the username in the logout request" do
      delete :destroy
      uri = URI.parse(response.location)
      xml = SamlEncoder.decode Rack::Utils.parse_query(uri.query)["SAMLRequest"]
      doc = Nokogiri::XML(xml)
      expect(doc.css("saml|NameID").first.text).to eq(user.username)
    end
  end

  describe "#idp_sign_out" do
    let(:user) { create(:user) }
    before do
      request.env["devise.mapping"] = Devise.mappings[:user]
      request.host = "localhost:3000" # without this, we're getting redirected to http://test.host/
    end

    describe "sp_initiated_sign_out" do
      it "redirects to the homepage" do
        # captured from OneLogin requests
        encoded = SamlEncoder.encode File.read(File.expand_path("../../fixtures/sp_initiated_sign_out.xml", __dir__))
        get :idp_sign_out, params: { SAMLResponse: encoded }
        expect(response).to redirect_to(root_path)
      end
    end

    describe "idp_initiated_sign_out" do
      # Captured from OneLogin requests
      let(:payload) { SamlEncoder.encode File.read(File.expand_path("../../fixtures/idp_initiated_sign_out.xml", __dir__)) }
      before do
        request.env["devise.mapping"] = Devise.mappings[:user]
        sign_in user
      end

      it "logs the user out" do
        get :idp_sign_out, params: { SAMLRequest: payload }
        expect(controller.current_user).to be_blank
      end

      it "redirects back to the IdP" do
        get :idp_sign_out, params: { SAMLRequest: payload }
        expect(response.location).to start_with(Devise.saml_config.idp_slo_service_url)
      end
    end
  end
end
