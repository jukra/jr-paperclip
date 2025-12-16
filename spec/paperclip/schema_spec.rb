require "spec_helper"
require "paperclip/schema"
require "active_support/testing/deprecation"

describe Paperclip::Schema do
  include ActiveSupport::Testing::Deprecation

  before do
    rebuild_class
  end

  after do
    begin
      ActiveRecord::Migration.drop_table :dummies
    rescue StandardError
      nil
    end
  end

  # Helper to check datetime column (Rails 7+ uses datetime(6) precision by default)
  def expect_datetime_column(columns, column_name)
    datetime_column = columns.find { |col| col[0] == column_name }
    expect(datetime_column).to be_present
    expect(datetime_column[1]).to match(/^datetime/)
  end

  # Helper to enable deprecation warnings for testing
  def with_deprecation_warnings_enabled
    if ActiveSupport::Deprecation.respond_to?(:silenced=)
      old_silenced = ActiveSupport::Deprecation.silenced
      ActiveSupport::Deprecation.silenced = false
      yield
      ActiveSupport::Deprecation.silenced = old_silenced
    elsif defined?(ActiveSupport.deprecator)
      old_behavior = ActiveSupport.deprecator.behavior
      ActiveSupport.deprecator.behavior = :stderr
      yield
      ActiveSupport.deprecator.behavior = old_behavior
    else
      yield
    end
  end

  context "within table definition" do
    context "using #has_attached_file" do
      it "creates attachment columns" do
        ActiveRecord::Migration.create_table :dummies, force: true do |t|
          if ActiveSupport::Deprecation.respond_to?(:silence)
            ActiveSupport::Deprecation.silence do
              t.has_attached_file :avatar
            end
          elsif defined?(ActiveSupport.deprecator)
            ActiveSupport.deprecator.silence do
              t.has_attached_file :avatar
            end
          else
            t.has_attached_file :avatar
          end
        end

        columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

        expect(columns).to include(["avatar_file_name", "varchar"])
        expect(columns).to include(["avatar_content_type", "varchar"])
        expect(columns).to include(["avatar_file_size", "bigint"])
        expect_datetime_column(columns, "avatar_updated_at")
      end

      it "displays deprecation warning" do
        with_deprecation_warnings_enabled do
          ActiveRecord::Migration.create_table :dummies, force: true do |t|
            deprecator = defined?(ActiveSupport.deprecator) ? ActiveSupport.deprecator : ActiveSupport::Deprecation
            assert_deprecated(nil, deprecator) do
              t.has_attached_file :avatar
            end
          end
        end
      end
    end

    context "using #attachment" do
      before do
        ActiveRecord::Migration.create_table :dummies, force: true do |t|
          t.attachment :avatar
        end
      end

      it "creates attachment columns" do
        columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

        expect(columns).to include(["avatar_file_name", "varchar"])
        expect(columns).to include(["avatar_content_type", "varchar"])
        expect(columns).to include(["avatar_file_size", "bigint"])
        expect_datetime_column(columns, "avatar_updated_at")
      end
    end

    context "using #attachment with options" do
      before do
        ActiveRecord::Migration.create_table :dummies, force: true do |t|
          t.attachment :avatar, default: 1, file_name: { default: "default" }
        end
      end

      it "sets defaults on columns" do
        defaults_columns = ["avatar_file_name", "avatar_content_type", "avatar_file_size"]
        columns = Dummy.columns.select { |e| defaults_columns.include? e.name }

        expect(columns).to have_column("avatar_file_name").with_default("default")
        expect(columns).to have_column("avatar_content_type").with_default("1")
        expect(columns).to have_column("avatar_file_size").with_default(1)
      end
    end
  end

  context "within schema statement" do
    before do
      ActiveRecord::Migration.create_table :dummies, force: true
    end

    context "migrating up" do
      context "with single attachment" do
        before do
          ActiveRecord::Migration.add_attachment :dummies, :avatar
        end

        it "creates attachment columns" do
          columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

          expect(columns).to include(["avatar_file_name", "varchar"])
          expect(columns).to include(["avatar_content_type", "varchar"])
          expect(columns).to include(["avatar_file_size", "bigint"])
          expect_datetime_column(columns, "avatar_updated_at")
        end
      end

      context "with single attachment and options" do
        before do
          ActiveRecord::Migration.add_attachment :dummies, :avatar, default: "1", file_name: { default: "default" }
        end

        it "sets defaults on columns" do
          defaults_columns = ["avatar_file_name", "avatar_content_type", "avatar_file_size"]
          columns = Dummy.columns.select { |e| defaults_columns.include? e.name }

          expect(columns).to have_column("avatar_file_name").with_default("default")
          expect(columns).to have_column("avatar_content_type").with_default("1")
          expect(columns).to have_column("avatar_file_size").with_default(1)
        end
      end

      context "with multiple attachments" do
        before do
          ActiveRecord::Migration.add_attachment :dummies, :avatar, :photo
        end

        it "creates attachment columns" do
          columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

          expect(columns).to include(["avatar_file_name", "varchar"])
          expect(columns).to include(["avatar_content_type", "varchar"])
          expect(columns).to include(["avatar_file_size", "bigint"])
          expect_datetime_column(columns, "avatar_updated_at")
          expect(columns).to include(["photo_file_name", "varchar"])
          expect(columns).to include(["photo_content_type", "varchar"])
          expect(columns).to include(["photo_file_size", "bigint"])
          expect_datetime_column(columns, "photo_updated_at")
        end
      end

      context "with multiple attachments and options" do
        before do
          ActiveRecord::Migration.add_attachment :dummies, :avatar, :photo, default: "1", file_name: { default: "default" }
        end

        it "sets defaults on columns" do
          defaults_columns = ["avatar_file_name", "avatar_content_type", "avatar_file_size", "photo_file_name", "photo_content_type", "photo_file_size"]
          columns = Dummy.columns.select { |e| defaults_columns.include? e.name }

          expect(columns).to have_column("avatar_file_name").with_default("default")
          expect(columns).to have_column("avatar_content_type").with_default("1")
          expect(columns).to have_column("avatar_file_size").with_default(1)
          expect(columns).to have_column("photo_file_name").with_default("default")
          expect(columns).to have_column("photo_content_type").with_default("1")
          expect(columns).to have_column("photo_file_size").with_default(1)
        end
      end

      context "with no attachment" do
        it "raises an error" do
          assert_raises ArgumentError do
            ActiveRecord::Migration.add_attachment :dummies
          end
        end
      end
    end

    context "migrating down" do
      before do
        ActiveRecord::Migration.change_table :dummies do |t|
          t.column :avatar_file_name, :string
          t.column :avatar_content_type, :string
          t.column :avatar_file_size, :bigint
          t.column :avatar_updated_at, :datetime
        end
      end

      # Helper to check datetime column is NOT present
      def expect_no_datetime_column(columns, column_name)
        datetime_column = columns.find { |col| col[0] == column_name }
        expect(datetime_column).to be_nil
      end

      context "using #drop_attached_file" do
        it "removes the attachment columns" do
          if ActiveSupport::Deprecation.respond_to?(:silence)
            ActiveSupport::Deprecation.silence do
              ActiveRecord::Migration.drop_attached_file :dummies, :avatar
            end
          elsif defined?(ActiveSupport.deprecator)
            ActiveSupport.deprecator.silence do
              ActiveRecord::Migration.drop_attached_file :dummies, :avatar
            end
          else
            ActiveRecord::Migration.drop_attached_file :dummies, :avatar
          end

          columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

          expect(columns).to_not include(["avatar_file_name", "varchar"])
          expect(columns).to_not include(["avatar_content_type", "varchar"])
          expect(columns).to_not include(["avatar_file_size", "bigint"])
          expect_no_datetime_column(columns, "avatar_updated_at")
        end

        it "displays a deprecation warning" do
          with_deprecation_warnings_enabled do
            deprecator = defined?(ActiveSupport.deprecator) ? ActiveSupport.deprecator : ActiveSupport::Deprecation
            assert_deprecated(nil, deprecator) do
              ActiveRecord::Migration.drop_attached_file :dummies, :avatar
            end
          end
        end
      end

      context "using #remove_attachment" do
        context "with single attachment" do
          before do
            ActiveRecord::Migration.remove_attachment :dummies, :avatar
          end

          it "removes the attachment columns" do
            columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

            expect(columns).to_not include(["avatar_file_name", "varchar"])
            expect(columns).to_not include(["avatar_content_type", "varchar"])
            expect(columns).to_not include(["avatar_file_size", "bigint"])
            expect_no_datetime_column(columns, "avatar_updated_at")
          end
        end

        context "with multiple attachments" do
          before do
            ActiveRecord::Migration.change_table :dummies do |t|
              t.column :photo_file_name, :string
              t.column :photo_content_type, :string
              t.column :photo_file_size, :bigint
              t.column :photo_updated_at, :datetime
            end

            ActiveRecord::Migration.remove_attachment :dummies, :avatar, :photo
          end

          it "removes the attachment columns" do
            columns = Dummy.columns.map { |column| [column.name, column.sql_type] }

            expect(columns).to_not include(["avatar_file_name", "varchar"])
            expect(columns).to_not include(["avatar_content_type", "varchar"])
            expect(columns).to_not include(["avatar_file_size", "bigint"])
            expect_no_datetime_column(columns, "avatar_updated_at")
            expect(columns).to_not include(["photo_file_name", "varchar"])
            expect(columns).to_not include(["photo_content_type", "varchar"])
            expect(columns).to_not include(["photo_file_size", "bigint"])
            expect_no_datetime_column(columns, "photo_updated_at")
          end
        end

        context "with no attachment" do
          it "raises an error" do
            assert_raises ArgumentError do
              ActiveRecord::Migration.remove_attachment :dummies
            end
          end
        end
      end
    end
  end
end
