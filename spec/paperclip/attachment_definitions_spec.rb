require "spec_helper"

describe "Attachment Definitions" do
  it "returns all of the attachments on the class" do
    reset_class "Dummy"
    Dummy.has_attached_file :avatar, path: "abc"
    Dummy.has_attached_file :other_attachment, url: "123"
    Dummy.do_not_validate_attachment_file_type :avatar
    expected = { avatar: { path: "abc" }, other_attachment: { url: "123" } }

    expect(Dummy.attachment_definitions).to eq expected
  end

  describe "configuration isolation between models" do
    # Helper method to safely remove a constant and clean up its registry entries
    def cleanup_model(class_name)
      return unless Object.const_defined?(class_name)

      # Remove from Paperclip's AttachmentRegistry to prevent test pollution
      Paperclip::AttachmentRegistry.clear
      # Remove the constant
      Object.send(:remove_const, class_name)
    end

    before do
      # Clean up any existing class definitions before each test
      cleanup_model(:ModelA)
      cleanup_model(:ModelB)

      # Create table for ModelA
      ActiveRecord::Migration.create_table :model_as, force: true do |table|
        table.column :attachment_file_name, :string
        table.column :attachment_content_type, :string
        table.column :attachment_file_size, :bigint
        table.column :attachment_updated_at, :datetime
      end

      # Create table for ModelB
      ActiveRecord::Migration.create_table :model_bs, force: true do |table|
        table.column :attachment_file_name, :string
        table.column :attachment_content_type, :string
        table.column :attachment_file_size, :bigint
        table.column :attachment_updated_at, :datetime
      end
    end

    after do
      # Clean up model classes to prevent test pollution
      cleanup_model(:ModelA)
      cleanup_model(:ModelB)

      # Drop tables
      ActiveRecord::Migration.drop_table :model_as, if_exists: true
      ActiveRecord::Migration.drop_table :model_bs, if_exists: true
    end

    it "does not mutate default_options when configuring multiple models" do
      # Capture original values of mutable options
      original_path = Paperclip::Attachment.default_options[:path].dup
      original_url = Paperclip::Attachment.default_options[:url].dup
      original_default_url = Paperclip::Attachment.default_options[:default_url].dup
      original_styles = Paperclip::Attachment.default_options[:styles].deep_dup
      original_convert_options = Paperclip::Attachment.default_options[:convert_options].deep_dup

      # Define ModelA with specific configuration
      class ::ModelA < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_a/:filename",
                          styles: { thumb: "100x100" }
        do_not_validate_attachment_file_type :attachment
      end

      # Define ModelB with different configuration
      class ::ModelB < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_b/:filename",
                          styles: { large: "500x500" }
        do_not_validate_attachment_file_type :attachment
      end

      # Verify default_options was not mutated
      expect(Paperclip::Attachment.default_options[:path]).to eq original_path
      expect(Paperclip::Attachment.default_options[:url]).to eq original_url
      expect(Paperclip::Attachment.default_options[:default_url]).to eq original_default_url
      expect(Paperclip::Attachment.default_options[:styles]).to eq original_styles
      expect(Paperclip::Attachment.default_options[:convert_options]).to eq original_convert_options
    end

    it "keeps attachment configurations isolated between models" do
      # Define ModelA with specific configuration
      class ::ModelA < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_a/:filename",
                          styles: { thumb: "100x100" },
                          default_url: "/missing_a.png"
        do_not_validate_attachment_file_type :attachment
      end

      # Define ModelB with different configuration
      class ::ModelB < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_b/:filename",
                          styles: { large: "500x500" },
                          default_url: "/missing_b.png"
        do_not_validate_attachment_file_type :attachment
      end

      # Create instances and access attachments
      model_a = ModelA.new
      model_b = ModelB.new

      # Access attachment on ModelA first
      attachment_a = model_a.attachment

      # Access attachment on ModelB
      attachment_b = model_b.attachment

      # Verify configurations are isolated
      expect(attachment_a.options[:path]).to eq "/model_a/:filename"
      expect(attachment_a.options[:styles]).to eq({ thumb: "100x100" })
      expect(attachment_a.options[:default_url]).to eq "/missing_a.png"

      expect(attachment_b.options[:path]).to eq "/model_b/:filename"
      expect(attachment_b.options[:styles]).to eq({ large: "500x500" })
      expect(attachment_b.options[:default_url]).to eq "/missing_b.png"

      # Verify attachment_definitions are also isolated
      expect(ModelA.attachment_definitions[:attachment][:path]).to eq "/model_a/:filename"
      expect(ModelB.attachment_definitions[:attachment][:path]).to eq "/model_b/:filename"
    end

    it "does not leak configuration when accessing attachments in different order" do
      # Define ModelA with specific configuration
      class ::ModelA < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_a/:filename",
                          styles: { thumb: "100x100" }
        do_not_validate_attachment_file_type :attachment
      end

      # Define ModelB with different configuration
      class ::ModelB < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_b/:filename",
                          styles: { large: "500x500" }
        do_not_validate_attachment_file_type :attachment
      end

      # Access ModelB first, then ModelA (reverse order of definition)
      model_b = ModelB.new
      attachment_b = model_b.attachment

      model_a = ModelA.new
      attachment_a = model_a.attachment

      # Verify configurations remain correct
      expect(attachment_a.options[:path]).to eq "/model_a/:filename"
      expect(attachment_a.options[:styles]).to eq({ thumb: "100x100" })

      expect(attachment_b.options[:path]).to eq "/model_b/:filename"
      expect(attachment_b.options[:styles]).to eq({ large: "500x500" })
    end

    it "does not share options between multiple instances of the same model" do
      class ::ModelA < ActiveRecord::Base
        include Paperclip::Glue
        has_attached_file :attachment,
                          path: "/model_a/:filename",
                          styles: { thumb: "100x100" }
        do_not_validate_attachment_file_type :attachment
      end

      instance1 = ModelA.new
      instance2 = ModelA.new

      attachment1 = instance1.attachment
      attachment2 = instance2.attachment

      # Verify they have the same configuration values
      expect(attachment1.options[:path]).to eq attachment2.options[:path]
      expect(attachment1.options[:styles]).to eq attachment2.options[:styles]

      # Verify the values are correct for both instances
      expect(attachment1.options[:path]).to eq "/model_a/:filename"
      expect(attachment2.options[:path]).to eq "/model_a/:filename"
    end

    context "with global default_options configured first" do
      let(:original_default_options) { Paperclip::Attachment.default_options.deep_dup }

      before do
        # Simulate a Rails initializer setting global defaults
        Paperclip::Attachment.default_options[:path] = "/global/:class/:attachment/:id/:style/:filename"
        Paperclip::Attachment.default_options[:url] = "/global/:class/:attachment/:id/:style/:filename"
        Paperclip::Attachment.default_options[:default_url] = "/global/missing.png"
        Paperclip::Attachment.default_options[:styles] = { global_thumb: "50x50" }
      end

      after do
        # Restore original default_options
        Paperclip::Attachment.instance_variable_set(:@default_options, nil)
      end

      it "keeps model configurations isolated when global defaults are set" do
        # Define ModelA that overrides some global defaults
        class ::ModelA < ActiveRecord::Base
          include Paperclip::Glue
          has_attached_file :attachment,
                            path: "/model_a/:filename",
                            styles: { thumb: "100x100" }
          do_not_validate_attachment_file_type :attachment
        end

        # Define ModelB that overrides different global defaults
        class ::ModelB < ActiveRecord::Base
          include Paperclip::Glue
          has_attached_file :attachment,
                            path: "/model_b/:filename",
                            styles: { large: "500x500" }
          do_not_validate_attachment_file_type :attachment
        end

        model_a = ModelA.new
        model_b = ModelB.new

        attachment_a = model_a.attachment
        attachment_b = model_b.attachment

        # Verify ModelA has its own path, and styles are deep_merged with global defaults
        expect(attachment_a.options[:path]).to eq "/model_a/:filename"
        expect(attachment_a.options[:styles]).to include(thumb: "100x100")
        expect(attachment_a.options[:styles]).to include(global_thumb: "50x50") # inherited from global
        expect(attachment_a.options[:url]).to eq "/global/:class/:attachment/:id/:style/:filename"
        expect(attachment_a.options[:default_url]).to eq "/global/missing.png"

        # Verify ModelB has its own path, and styles are deep_merged with global defaults
        expect(attachment_b.options[:path]).to eq "/model_b/:filename"
        expect(attachment_b.options[:styles]).to include(large: "500x500")
        expect(attachment_b.options[:styles]).to include(global_thumb: "50x50") # inherited from global
        expect(attachment_b.options[:url]).to eq "/global/:class/:attachment/:id/:style/:filename"
        expect(attachment_b.options[:default_url]).to eq "/global/missing.png"

        # Verify ModelA's styles do NOT leak to ModelB and vice versa
        expect(attachment_a.options[:styles]).not_to have_key(:large)
        expect(attachment_b.options[:styles]).not_to have_key(:thumb)
      end

      it "does not mutate global defaults when models override them" do
        # Capture global defaults before defining models
        global_path = Paperclip::Attachment.default_options[:path]
        global_styles = Paperclip::Attachment.default_options[:styles].deep_dup

        class ::ModelA < ActiveRecord::Base
          include Paperclip::Glue
          has_attached_file :attachment,
                            path: "/model_a/:filename",
                            styles: { thumb: "100x100" }
          do_not_validate_attachment_file_type :attachment
        end

        # Access the attachment to trigger any potential mutation
        model_a = ModelA.new
        _attachment_a = model_a.attachment

        # Global defaults should remain unchanged
        expect(Paperclip::Attachment.default_options[:path]).to eq global_path
        expect(Paperclip::Attachment.default_options[:styles]).to eq global_styles
      end

      it "does not leak ModelA config to ModelB when both override global defaults" do
        class ::ModelA < ActiveRecord::Base
          include Paperclip::Glue
          has_attached_file :attachment,
                            path: "/model_a/:filename",
                            styles: { thumb: "100x100" },
                            convert_options: { all: "-quality 80" }
          do_not_validate_attachment_file_type :attachment
        end

        class ::ModelB < ActiveRecord::Base
          include Paperclip::Glue
          has_attached_file :attachment,
                            path: "/model_b/:filename",
                            styles: { large: "500x500" },
                            convert_options: { all: "-quality 90" }
          do_not_validate_attachment_file_type :attachment
        end

        # Access ModelA first
        model_a = ModelA.new
        attachment_a = model_a.attachment

        # Then access ModelB
        model_b = ModelB.new
        attachment_b = model_b.attachment

        # Verify convert_options are isolated
        expect(attachment_a.options[:convert_options]).to eq({ all: "-quality 80" })
        expect(attachment_b.options[:convert_options]).to eq({ all: "-quality 90" })

        # Verify other options remain isolated
        expect(attachment_a.options[:path]).to eq "/model_a/:filename"
        expect(attachment_b.options[:path]).to eq "/model_b/:filename"
      end
    end
  end
end
