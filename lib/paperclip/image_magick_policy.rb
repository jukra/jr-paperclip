# frozen_string_literal: true

module Paperclip
  module ImageMagickPolicy
    POLICY_DIRECTORY = File.expand_path("image_magick", __dir__).freeze
    POLICY_PATH = File.join(POLICY_DIRECTORY, "policy.xml").freeze

    def self.command_environment(environment = {}, *other_paths)
      raise "Paperclip ImageMagick security policy is missing: #{POLICY_PATH}" unless File.file?(POLICY_PATH)

      environment ||= {}
      configured_path = configuration_path(environment["MAGICK_CONFIGURE_PATH"], *other_paths)
      paths = configured_path.to_s.split(File::PATH_SEPARATOR)
      paths.reject! { |path| path.empty? || path == POLICY_DIRECTORY }

      environment.merge("MAGICK_CONFIGURE_PATH" => [POLICY_DIRECTORY, *paths.uniq].join(File::PATH_SEPARATOR))
    end

    def self.configuration_path(*paths)
      [*paths, ENV["MAGICK_CONFIGURE_PATH"]].detect { |path| !path.to_s.empty? }
    end
    private_class_method :configuration_path

    def self.apply_to_mini_magick!
      require "mini_magick"
      unless MiniMagick.respond_to?(:cli_env) && MiniMagick.respond_to?(:cli_env=)
        raise "Paperclip's ImageMagick security policy requires mini_magick 5.1 or later"
      end
      if MiniMagick.graphicsmagick || MiniMagick.cli_prefix
        raise "Paperclip's ImageMagick security policy requires MiniMagick to use ImageMagick without a CLI prefix"
      end

      MiniMagick.cli_env = command_environment(MiniMagick.cli_env || {})
    end
  end
end
