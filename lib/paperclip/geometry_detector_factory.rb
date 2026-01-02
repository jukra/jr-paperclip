module Paperclip
  class GeometryDetector
    def initialize(file, backend: nil)
      @file = file
      @backend = backend
      raise_if_blank_file
    end

    def make
      geometry = GeometryParser.new(geometry_string.strip).make
      geometry || raise(Errors::NotIdentifiedByBackendError.new("Could not identify image size"))
    end

    private

    def geometry_string
      if resolve_backend == :vips
        vips_geometry_string
      else
        imagemagick_geometry_string
      end
    end

    def resolve_backend
      Paperclip.resolve_backend(@backend || Paperclip.options[:backend])
    end

    def imagemagick_geometry_string
      orientation = if Paperclip.options[:use_exif_orientation]
                      "%[exif:orientation]"
                    else
                      "1"
                    end
      Paperclip.run(
        (Paperclip.options[:is_windows] || Paperclip.imagemagick7?) ? "magick identify" : "identify",
        "-format '%wx%h,#{orientation}' :file", {
          file: "#{path}[0]",
        },
        swallow_stderr: true
      )
    rescue Terrapin::ExitStatusError
      ""
    rescue Terrapin::CommandNotFoundError => e
      raise Errors::CommandNotFoundError.new("Could not run the `identify` command. Please install ImageMagick.")
    end

    def vips_geometry_string
      begin
        require "vips"
      rescue LoadError => e
        raise Errors::CommandNotFoundError.new("Could not load ruby-vips. Please install libvips and the image_processing gem.")
      end

      begin
        # Use ruby-vips gem directly instead of shelling out to vipsheader
        image = Vips::Image.new_from_file(path, access: :sequential)
        width = image.width
        height = image.height

        orientation = "1"
        if Paperclip.options[:use_exif_orientation]
          begin
            orientation = image.get("orientation").to_s
          rescue Vips::Error
            # Field might not exist
          end
        end

        "#{width}x#{height},#{orientation}"
      rescue Vips::Error
        ""
      end
    end

    def path
      @file.respond_to?(:path) ? @file.path : @file
    end

    def raise_if_blank_file
      if path.blank?
        raise Errors::NotIdentifiedByBackendError.new("Cannot find the geometry of a file with a blank name")
      end
    end
  end
end
