module Paperclip
  # Handles thumbnailing images that are uploaded.
  # Now uses the image_processing gem internally, supporting both
  # ImageMagick (via MiniMagick) and libvips backends.
  #
  # @example Basic usage (unchanged from before)
  #   has_attached_file :avatar,
  #     styles: { medium: "300x300>", thumb: "100x100#" }
  #
  # @example Using libvips backend for better performance
  #   has_attached_file :avatar,
  #     styles: { medium: "300x300>", thumb: "100x100#" },
  #     backend: :vips
  #
  # @example Per-style backend selection
  #   has_attached_file :document,
  #     styles: {
  #       preview: { geometry: "800x800>", backend: :vips },
  #       thumb: { geometry: "100x100#", backend: :image_magick }
  #     }
  #
  class Thumbnail < Processor
    # Backward-compatible attributes (same as original Thumbnail)
    attr_accessor :current_geometry, :target_geometry, :format, :whiny,
                  :convert_options, :source_file_options, :animated,
                  :auto_orient, :frame_index

    # New attributes
    attr_accessor :backend

    ANIMATED_FORMATS = %w(gif).freeze
    # Creates a Thumbnail object set to work on the +file+ given. It
    # will attempt to transform the image into one defined by +target_geometry+
    # which is a "WxH"-style string. +format+ will be inferred from the +file+
    # unless specified. Thumbnail creation will raise no errors unless
    # +whiny+ is true (which it is, by default. If +convert_options+ is
    # set, the options will be appended to the convert command upon image conversion
    #
    # Options include:
    #   +backend+ - image_magick or vips, fallbacks to Paperclip.options[:backend]
    #   +geometry+ - the desired width and height of the thumbnail (required)
    #   +file_geometry_parser+ - an object with a method named +from_file+ that takes an image file and produces its geometry and a +transformation_to+. Defaults to Paperclip::Geometry
    #   +string_geometry_parser+ - an object with a method named +parse+ that takes a string and produces an object with +width+, +height+, and +to_s+ accessors. Defaults to Paperclip::Geometry
    #   +source_file_options+ - flags passed to the +convert+ command that influence how the source file is read
    #   +convert_options+ - flags passed to the +convert+ command that influence how the image is processed
    #   +whiny+ - whether to raise an error when processing fails. Defaults to true
    #   +format+ - the desired filename extension
    #   +animated+ - whether to merge all the layers in the image. Defaults to true
    #   +frame_index+ - the frame index of the source file to render as the thumbnail
    MULTI_FRAME_FORMATS = %w(.mkv .avi .mp4 .mov .mpg .mpeg .gif .pdf).freeze

    # Like ActiveStorage we want to be careful on what options are allowed for ImageMagick
    # 2 additional options added to Active Storage default list: set and profile
    # https://github.com/advisories/GHSA-r4mg-4433-c7g3
    ALLOWED_IMAGEMAGICK_OPTIONS = %w(
      adaptive_blur adaptive_resize adaptive_sharpen adjoin affine alpha annotate antialias append
      attenuate authenticate auto_gamma auto_level auto_orient auto_threshold backdrop background
      bench bias bilateral_blur black_point_compensation black_threshold blend blue_primary
      blue_shift blur border bordercolor borderwidth brightness_contrast cache canny caption
      channel channel_fx charcoal chop clahe clamp clip clip_path clone clut coalesce colorize
      colormap color_matrix colors colorspace colourspace color_threshold combine combine_options
      comment compare complex compose composite compress connected_components contrast
      contrast_stretch convert convolve copy crop cycle deconstruct define delay delete density
      depth descend deskew despeckle direction displace dispose dissimilarity_threshold dissolve
      distort dither draw duplicate edge emboss encoding endian enhance equalize evaluate
      evaluate_sequence extent extract family features fft fill filter flatten flip floodfill
      flop font foreground format frame function fuzz fx gamma gaussian_blur geometry gravity
      grayscale green_primary hald_clut highlight_color hough_lines iconGeometry iconic identify
      ift illuminant immutable implode insert intensity intent interlace interline_spacing
      interpolate interpolative_resize interword_spacing kerning kmeans kuwahara label lat layers
      level level_colors limit limits linear_stretch linewidth liquid_rescale list log loop
      lowlight_color magnify map mattecolor median mean_shift metric mode modulate moments
      monitor monochrome morph morphology mosaic motion_blur name negate noise normalize opaque
      ordered_dither orient page paint pause perceptible ping pointsize polaroid poly posterize
      precision preview process profile quality quantize quiet radial_blur raise random_threshold
      range_threshold red_primary regard_warnings region remote render repage resample resize
      resize_to_fill resize_to_fit resize_to_limit resize_and_pad respect_parentheses reverse
      roll rotate sample sampling_factor scale scene screen seed segment selective_blur separate
      sepia_tone set shade shadow shared_memory sharpen shave shear sigmoidal_contrast silent
      similarity_threshold size sketch smush snaps solarize sort_pixels sparse_color splice
      spread statistic stegano stereo storage_type stretch strip stroke strokewidth style
      subimage_search swap swirl synchronize taint text_font threshold thumbnail tile_offset tint
      title transform transparent transparent_color transpose transverse treedepth trim type
      undercolor unique_colors units unsharp update valid_image view vignette virtual_pixel
      visual watermark wave wavelet_denoise weight white_balance white_point white_threshold
      window window_group
    ).freeze

    def initialize(file, options = {}, attachment = nil)
      super

      geometry = options[:geometry].to_s
      @crop = geometry[-1, 1] == "#"
      @target_geometry = options.fetch(:string_geometry_parser, Geometry).parse(geometry)
      @whiny = options.fetch(:whiny, true)
      @format = options[:format]
      @animated = options.fetch(:animated, true)
      @auto_orient = options.fetch(:auto_orient, true)

      # Backward-compatible options
      @convert_options = options[:convert_options]
      @source_file_options = options[:source_file_options]

      # New options
      @backend = resolve_backend(options)

      @current_geometry = options.fetch(:file_geometry_parser, Geometry).from_file(@file, @backend)
      @current_geometry.auto_orient if @auto_orient && @current_geometry.respond_to?(:auto_orient)

      @current_format = File.extname(@file.path)
      @basename = File.basename(@file.path, @current_format)
      @frame_index = multi_frame_format? ? options.fetch(:frame_index, 0) : 0
    end

    # Returns true if the +target_geometry+ is meant to crop.
    def crop?
      @crop
    end

    # Returns true if the image is meant to make use of additional convert options.
    # Backwards-compatible method from original Thumbnail.
    def convert_options?
      @convert_options.present?
    end

    def make
      source_path = File.expand_path(@file.path)
      extension = @format ? ".#{@format}" : @current_format
      filename = [@basename, extension].join
      destination = nil

      begin
        destination = TempfileFactory.new.generate(filename)
        pipeline = build_pipeline(source_path)
        pipeline.call(destination: destination.path)
        destination
      rescue LoadError => e
        destination&.close! if destination.respond_to?(:close!)
        raise Paperclip::Errors::CommandNotFoundError.new("Could not run the command for #{backend}. Please install dependencies.")
      rescue StandardError => e
        destination&.close! if destination.respond_to?(:close!)
        if defined?(::Vips::Error) && e.is_a?(::Vips::Error)
          handle_error(e, "libvips")
        elsif defined?(::MiniMagick::Error) && (e.is_a?(::MiniMagick::Error) || e.is_a?(::MiniMagick::Invalid))
          handle_error(e, "ImageMagick")
        elsif defined?(::ImageProcessing::Error) && e.is_a?(::ImageProcessing::Error)
          handle_error(e, "ImageProcessing")
        else
          raise e
        end
      end
    end

    # Returns the command ImageMagick's +convert+ needs to transform the image
    # into the thumbnail. Provided for backwards compatibility.
    # @deprecated This method is deprecated and does not reflect actual processing.
    def transformation_command
      if backend == :vips
        Paperclip.log("Warning: transformation_command called but using vips backend")
      end

      scale, crop = @current_geometry.transformation_to(@target_geometry, crop?)
      trans = []
      trans << "-coalesce" if animated?
      trans << "-auto-orient" if auto_orient
      trans << "-resize" << %["#{scale}"] unless scale.nil? || scale.empty?
      trans << "-crop" << %["#{crop}"] << "+repage" if crop
      trans << '-layers "optimize"' if animated?
      trans
    end

    private

    def resolve_backend(options)
      candidate = options[:backend] ||
        attachment&.options&.dig(:backend) ||
        Paperclip.options[:backend]
      Paperclip.resolve_backend(candidate)
    end

    def build_pipeline(source_path)
      pipeline = image_processing_module.source(source_path)

      # Handle source file options
      if @source_file_options
        loader_options = parse_loader_options(@source_file_options)
        pipeline = pipeline.loader(**loader_options) unless loader_options.empty?
      end

      # Handle multi-layer formats (like PDF or animated GIF)
      # If we are not processing animation, we usually want the first frame.
      # image_processing defaults to processing all layers for some formats.
      if !animated? && multi_frame_format?
        if backend == :image_magick
          # For PDFs or multi-frame images where we want a static thumbnail:
          pipeline = pipeline.loader(page: @frame_index)
        elsif backend == :vips
          # Vips: load only the specified frame
          pipeline = pipeline.loader(page: @frame_index, n: 1)
        end
      elsif animated?
        if backend == :image_magick
          # Explicitly load all pages for animation
          pipeline = pipeline.loader(page: nil)
        elsif backend == :vips
          # Vips: load all pages
          pipeline = pipeline.loader(n: -1)
        end
      end

      # Auto-orient based on EXIF data
      if auto_orient
        pipeline = if backend == :vips
                     pipeline.autorot
                   else
                     pipeline.auto_orient
                   end
      end

      # Apply resize operation
      if target_geometry
        pipeline = apply_resize(pipeline)
      end

      # Handle animated images (GIF, WebP)
      if animated && animated_source?
        if backend == :image_magick
          pipeline = pipeline.coalesce.layers("optimize")
        elsif backend == :vips
          # There isn't optimize available the same way as for ImageMagick
          pipeline = pipeline.saver(keep_duplicate_frames: false)
        end
      end

      # Format conversion
      if format
        pipeline = pipeline.convert(format.to_s)
      end

      # Apply any additional custom convert options
      # Some options work on both backends, others are ImageMagick-only
      if convert_options?
        pipeline = apply_convert_options(pipeline)
      end

      pipeline
    end

    def image_processing_module
      case backend
      when :vips
        require "image_processing/vips"
        ImageProcessing::Vips
      else
        # :image_magick or any other value defaults to ImageMagick
        require "image_processing/mini_magick"
        ImageProcessing::MiniMagick
      end
    end

    def apply_resize(pipeline)
      width = target_geometry.width&.to_i
      height = target_geometry.height&.to_i
      modifier = target_geometry.modifier

      # Handle special geometry cases
      case modifier
      when "#" # Crop to fill
        if width && width > 0 && height && height > 0
          pipeline.resize_to_fill(width, height)
        elsif width && width > 0
          pipeline.resize_to_fill(width, width)
        elsif height && height > 0
          pipeline.resize_to_fill(height, height)
        else
          pipeline
        end

      when ">" # Only shrink larger images
        if width && width > 0 && height && height > 0
          pipeline.resize_to_limit(width, height)
        elsif width && width > 0
          pipeline.resize_to_limit(width, nil)
        elsif height && height > 0
          pipeline.resize_to_limit(nil, height)
        else
          pipeline
        end

      when "<" # Only enlarge smaller images
        # image_processing doesn't have direct support for this
        # We need to check current dimensions first
        if current_geometry && should_enlarge?
          pipeline.resize_to_fit(width, height)
        else
          pipeline
        end

      when "!" # Exact dimensions (ignore aspect ratio)
        if width && width > 0 && height && height > 0
          if backend == :vips
            if current_geometry
              scale_x = width.to_f / current_geometry.width
              scale_y = height.to_f / current_geometry.height
              pipeline.custom { |img| img.resize(scale_x, vscale: scale_y) }
            else
              pipeline.resize_to_fill(width, height)
            end
          else
            # MiniMagick: use resize with ! modifier
            pipeline.resize("#{width}x#{height}!")
          end
        else
          pipeline
        end

      when "^" # Minimum dimensions (fill the box, may overflow)
        apply_minimum_dimensions(pipeline, width, height)

      when "%" # Percentage resize
        apply_percentage_resize(pipeline, width)

      when "@" # Area-based resize (limit total pixels)
        apply_area_resize(pipeline, width, false)

      when "@>", ">@" # Area-based resize, only shrink
        apply_area_resize(pipeline, width, true)

      else
        # Default: resize to fit (can enlarge, maintains aspect ratio)
        if width && width > 0 && height && height > 0
          pipeline.resize_to_fit(width, height)
        elsif width && width > 0
          pipeline.resize_to_fit(width, nil)
        elsif height && height > 0
          pipeline.resize_to_fit(nil, height)
        else
          pipeline
        end
      end
    end

    def apply_minimum_dimensions(pipeline, width, height)
      if backend == :vips && width && width > 0 && height && height > 0 && current_geometry
        scale = [width.to_f / current_geometry.width, height.to_f / current_geometry.height].max
        new_width = (current_geometry.width * scale).round
        new_height = (current_geometry.height * scale).round
        pipeline.resize_to_fit(new_width, new_height)
      elsif width && width > 0 && height && height > 0
        # MiniMagick: use resize with ^ modifier
        if backend == :image_magick
          pipeline.resize("#{width}x#{height}^")
        else
          pipeline.resize_to_fill(width, height, crop: :centre)
        end
      else
        pipeline.resize_to_fit(width, height)
      end
    end

    def apply_percentage_resize(pipeline, percentage)
      scale = (percentage || 100) / 100.0
      if current_geometry
        new_width = (current_geometry.width * scale).round
        new_height = (current_geometry.height * scale).round
        pipeline.resize_to_fit(new_width, new_height)
      else
        pipeline
      end
    end

    def apply_area_resize(pipeline, max_area, only_shrink)
      return pipeline unless current_geometry && max_area && max_area > 0

      current_area = current_geometry.width * current_geometry.height

      # If only_shrink and current image is smaller, return unchanged
      if only_shrink && current_area <= max_area
        return pipeline
      end

      # Calculate new dimensions maintaining aspect ratio
      if !only_shrink || current_area > max_area
        scale = Math.sqrt(max_area.to_f / current_area)
        new_width = (current_geometry.width * scale).round
        new_height = (current_geometry.height * scale).round
        pipeline.resize_to_fit(new_width, new_height)
      else
        pipeline
      end
    end

    def apply_convert_options(pipeline)
      # Parse convert_options into individual tokens
      # Handle both string format "-strip -quality 80" and array format ["-strip", "-quality", "80"]
      tokens = @convert_options.respond_to?(:split) ? @convert_options.split(/\s+/) : Array(@convert_options)

      i = 0
      while i < tokens.size
        token = tokens[i]

        unless token.start_with?("-") || token.start_with?("+")
          # Handle raw argument (e.g. part of a multi-arg sequence like -set k v)
          if backend == :image_magick
            pipeline = pipeline.append(token)
          end
          # Skip non-option tokens (shouldn't happen normally)
          i += 1
          next
        end

        # Remove leading dash(es) or plus(es) and convert to method-friendly format
        opt_name = token.sub(/^[-+]+/, "")
        prefix = token.start_with?("+") ? "+" : "-"

        # Check if next token is a value
        # Allow negative/positive numbers as values
        next_token = i + 1 < tokens.size ? tokens[i + 1] : nil
        has_value = next_token && (
          (!next_token.start_with?("-") && !next_token.start_with?("+")) ||
            next_token.match?(/^[-+]\d/)
        )
        value = has_value ? next_token : nil

        # Apply the option - works for both backends where supported
        pipeline = apply_single_option(pipeline, opt_name, value, prefix)

        # Advance past this option (and its value if present)
        i += has_value ? 2 : 1
      end

      pipeline
    end

    def apply_single_option(pipeline, opt_name, value, prefix = "-")
      if backend == :vips
        # Vips doesn't support +options generally
        if prefix == "+"
          Paperclip.log("Warning: +#{opt_name} is not supported with vips backend, skipping")
          return pipeline
        end
        # Normalize option name (handle hyphenated versions) to underscores for Vips methods
        opt_name = opt_name.tr("-", "_")
        apply_vips_option(pipeline, opt_name, value)
      else
        # ImageMagick expects hyphens (e.g. -auto-orient, -sampling-factor)
        opt_name = opt_name.tr("_", "-")
        apply_imagemagick_option(pipeline, opt_name, value, prefix)
      end
    end

    def apply_vips_option(pipeline, opt_name, value)
      # Cross-platform options with vips-specific implementations
      case opt_name
      when "strip"
        pipeline.saver(strip: true)
      when "quality"
        value ? pipeline.saver(quality: value.to_i) : pipeline
      when "rotate"
        # Vips rotate via similarity for arbitrary angles
        if value
          angle = value.to_f
          pipeline.custom { |img| img.similarity(angle: angle) }
        else
          pipeline
        end
      when "flip"
        # Vips uses flip with direction
        pipeline.custom(&:flipver)
      when "flop"
        pipeline.custom(&:fliphor)
      when "blur"
        # Vips uses gaussblur with sigma parameter
        # ImageMagick blur is "radiusxsigma", extract sigma
        sigma = extract_blur_sigma(value)
        sigma ? pipeline.custom { |img| img.gaussblur(sigma) } : pipeline
      when "gaussian_blur"
        sigma = extract_blur_sigma(value)
        sigma ? pipeline.custom { |img| img.gaussblur(sigma) } : pipeline
      when "sharpen"
        # Vips sharpen has different parameters than ImageMagick
        # Use sensible defaults for unsharp masking
        pipeline.custom(&:sharpen)
      when "colorspace"
        # Vips uses British spelling "colourspace"
        value ? pipeline.custom { |img| img.colourspace(vips_colorspace(value)) } : pipeline
      when "flatten"
        pipeline.custom { |img| img.flatten(background: [255, 255, 255]) }
      when "negate", "invert"
        pipeline.custom(&:invert)
      when "auto_orient"
        pipeline.autorot
      when "interlace"
        # Vips handles interlacing via saver options
        pipeline.saver(interlace: true)
      else
        # Unknown option - log warning for vips
        Paperclip.log("Warning: -#{opt_name} is not supported with vips backend, skipping")
        pipeline
      end
    end

    def apply_imagemagick_option(pipeline, opt_name, value, prefix = "-")
      # Check against allowed options (using underscore version for checking)
      normalized_opt_name = opt_name.tr("-", "_")
      unless ALLOWED_IMAGEMAGICK_OPTIONS.include?(normalized_opt_name)
        Paperclip.log("Warning: Option #{opt_name} is not allowed.")
        return pipeline
      end

      # ImageMagick options are just CLI arguments, so we can simply append them.
      # This handles standard options (-strip), plus options (+profile), and unknown options uniformly.
      pipeline = pipeline.append("#{prefix}#{opt_name}")
      pipeline = pipeline.append(value) if value
      pipeline
    end

    # Extract sigma value from ImageMagick blur format "radiusxsigma" or just "sigma"
    def extract_blur_sigma(value)
      return nil unless value

      if value.include?("x")
        value.split("x").last.to_f
      else
        value.to_f
      end
    end

    # Map ImageMagick colorspace names to Vips interpretation
    def vips_colorspace(im_colorspace)
      case im_colorspace.to_s.downcase
      when "gray", "grey", "grayscale"
        :grey16 # or :b_w for 1-bit
      when "srgb", "rgb"
        :srgb
      when "cmyk"
        :cmyk
      when "lab"
        :lab
      when "xyz"
        :xyz
      else
        :srgb # Default fallback
      end
    end

    # Parses command-line style options into a hash for loader options.
    # Example: "-density 300" becomes { density: "300" }
    def parse_loader_options(options)
      return options if options.is_a?(Hash)

      result = {}
      parts = options.respond_to?(:split) ? options.split(/\s+/) : Array(options)
      i = 0
      while i < parts.size
        part = parts[i]
        if part.start_with?("-")
          key = part[1..].to_sym

          next_part = parts[i + 1]
          if i + 1 < parts.size && (!next_part.start_with?("-") || next_part.match?(/^-\d/))
            result[key] = next_part
            i += 2
          else
            result[key] = true
            i += 1
          end
        else
          i += 1
        end
      end
      result
    end

    def should_enlarge?
      return false unless current_geometry && target_geometry

      target_width = target_geometry.width.to_i
      target_height = target_geometry.height.to_i

      (target_width == 0 || current_geometry.width < target_width) &&
        (target_height == 0 || current_geometry.height < target_height)
    end

    def multi_frame_format?
      MULTI_FRAME_FORMATS.include?(@current_format.downcase)
    end

    def animated?
      @animated && (ANIMATED_FORMATS.include?(@format.to_s.downcase) || @format.blank?) && animated_source?
    end

    def animated_source?
      @animated_source ||= begin
        case backend
        when :vips
          vips_image(File.expand_path(@file.path)).get("n-pages").to_i > 1
        when :image_magick
          identify("-format %n :file", file: File.expand_path(@file.path)).to_i > 1
        else
          extension_indicates_animation?
        end
      rescue StandardError
        extension_indicates_animation?
      end
    end

    def extension_indicates_animation?
      ANIMATED_FORMATS.include?(@current_format.downcase.delete("."))
    end

    # Handle processing errors - matches original Thumbnail's pattern
    def handle_error(error, backend_name)
      if @whiny
        # Sanitize basename to avoid leaking full paths
        safe_name = File.basename(@basename.to_s)
        message = "There was an error processing the thumbnail for #{safe_name} using #{backend_name}:\n#{error.message}"
        raise Paperclip::Error, message
      else
        Paperclip.log("Processing failed: #{error.message}")
        @file
      end
    end
  end
end
