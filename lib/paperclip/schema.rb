require "active_support/deprecation"

module Paperclip
  # Provides helper methods that can be used in migrations.
  module Schema
    COLUMNS = { file_name: :string,
                content_type: :string,
                file_size: :bigint,
                updated_at: :datetime }

    def self.included(_base)
      ActiveRecord::ConnectionAdapters::Table.include TableDefinition
      ActiveRecord::ConnectionAdapters::TableDefinition.include TableDefinition
      ActiveRecord::Migration.include Statements
      ActiveRecord::Migration::CommandRecorder.include CommandRecorder
    end

    # Extract column-specific options and merge with general options
    def self.column_options(options, column_name)
      column_specific = options[column_name.to_sym] || {}
      general_options = options.except(*COLUMNS.keys)
      general_options.merge(column_specific)
    end

    module DeprecationHelper
      private

      def deprecation_warn(message)
        if defined?(ActiveSupport.deprecator)
          ActiveSupport.deprecator.warn(message)
        elsif ActiveSupport::Deprecation.respond_to?(:warn)
          ActiveSupport::Deprecation.warn(message)
        end
      end
    end

    module Statements
      include DeprecationHelper

      def add_attachment(table_name, *attachment_names)
        if attachment_names.empty?
          raise ArgumentError, "Please specify attachment name in your add_attachment call in your migration."
        end

        options = attachment_names.extract_options!

        attachment_names.each do |attachment_name|
          COLUMNS.each_pair do |column_name, column_type|
            column_options = Schema.column_options(options, column_name)
            add_column(table_name, "#{attachment_name}_#{column_name}", column_type, **column_options)
          end
        end
      end

      def remove_attachment(table_name, *attachment_names)
        if attachment_names.empty?
          raise ArgumentError, "Please specify attachment name in your remove_attachment call in your migration."
        end

        attachment_names.each do |attachment_name|
          COLUMNS.keys.each do |column_name|
            remove_column(table_name, "#{attachment_name}_#{column_name}")
          end
        end
      end

      def drop_attached_file(*args)
        deprecation_warn "Method `drop_attached_file` in the migration has been deprecated and will be replaced by `remove_attachment`."
        remove_attachment(*args)
      end
    end

    module TableDefinition
      include DeprecationHelper

      def attachment(*attachment_names)
        options = attachment_names.extract_options!
        attachment_names.each do |attachment_name|
          COLUMNS.each_pair do |column_name, column_type|
            column_options = Schema.column_options(options, column_name)
            column("#{attachment_name}_#{column_name}", column_type, **column_options)
          end
        end
      end

      def has_attached_file(*attachment_names)
        deprecation_warn "Method `t.has_attached_file` in the migration has been deprecated and will be replaced by `t.attachment`."
        attachment(*attachment_names)
      end
    end

    module CommandRecorder
      def add_attachment(*args)
        record(:add_attachment, args)
      end

      private

      def invert_add_attachment(args)
        [:remove_attachment, args]
      end
    end
  end
end
