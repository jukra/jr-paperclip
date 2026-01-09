module Paperclip
  module Helpers
    def configure
      yield(self) if block_given?
    end

    def interpolates(key, &block)
      Paperclip::Interpolations[key] = block
    end

    # The run method takes the name of a binary to run, the arguments
    # to that binary, the values to interpolate and some local options.
    #
    #  :cmd -> The name of a binary to run.
    #
    #  :arguments -> The command line arguments to that binary.
    #
    #  :interpolation_values -> Values to be interpolated into the arguments.
    #
    #  :local_options -> The options to be used by Cocain::CommandLine.
    #                    These could be: runner
    #                                    logger
    #                                    swallow_stderr
    #                                    expected_outcodes
    #                                    environment
    #                                    runner_options
    #
    def run(cmd, arguments = "", interpolation_values = {}, local_options = {})
      command_path = options[:command_path]
      terrapin_path_array = Terrapin::CommandLine.path.try(:split, Terrapin::OS.path_separator)
      Terrapin::CommandLine.path = [terrapin_path_array, command_path].flatten.compact.uniq
      if logging? && (options[:log_command] || local_options[:log_command])
        local_options = local_options.merge(logger: logger)
      end
      Terrapin::CommandLine.new(cmd, arguments, local_options).run(interpolation_values)
    end

    # Find all instances of the given Active Record model +klass+ with attachment +name+.
    # This method is used by the refresh rake tasks.
    def each_instance_with_attachment(klass, name)
      class_for(klass).unscoped.where("#{name}_file_name IS NOT NULL").find_each do |instance|
        yield(instance)
      end
    end

    def class_for(class_name)
      class_name.split("::").inject(Object) do |klass, partial_class_name|
        if klass.const_defined?(partial_class_name)
          klass.const_get(partial_class_name, false)
        else
          klass.const_missing(partial_class_name)
        end
      end
    end

    def reset_duplicate_clash_check!
      @names_url = nil
    end

    def imagemagick7?
      return @imagemagick7 if instance_variable_defined?(:@imagemagick7)

      @imagemagick7 = !!which("magick")
    end

    # https://github.com/minimagick/minimagick/blob/master/lib/mini_magick/utilities.rb#L9-L24
    def which(cmd)
      exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
      (ENV["PATH"] || "").split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable? exe
        end
      end
      nil
    end
  end
end
