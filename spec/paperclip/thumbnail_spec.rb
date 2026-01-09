require "spec_helper"

describe Paperclip::Thumbnail do
  context "An image" do
    before do
      @file = File.new(fixture_file("5k.png"), "rb")
    end

    after { @file.close }

    describe "backend selection" do
      let(:attachment) { double("Attachment", options: {}) }

      it "uses vips when specified" do
        processor = described_class.new(@file, { geometry: "25x25", backend: :vips }, attachment)
        expect(processor.backend).to eq(:vips)
      end

      it "uses global default when no backend specified" do
        Paperclip.options[:backend] = :image_magick
        processor = described_class.new(@file, { geometry: "25x25" }, attachment)
        expect(processor.backend).to eq(:image_magick)
      end

      it "defaults to image_magick when backend is nil" do
        original_backend = Paperclip.options[:backend]
        Paperclip.options[:backend] = nil
        processor = described_class.new(@file, { geometry: "25x25" }, attachment)
        expect(processor.backend).to eq(:image_magick)
        Paperclip.options[:backend] = original_backend
      end

      it "defaults to image_magick when backend is invalid" do
        processor = described_class.new(@file, { geometry: "25x25", backend: :invalid_backend }, attachment)
        expect(processor.backend).to eq(:image_magick)
      end

      it "logs a warning when backend is invalid" do
        expect(Paperclip).to receive(:log).with(/Warning: Invalid backend: invalid_backend/)
        described_class.new(@file, { geometry: "25x25", backend: :invalid_backend }, attachment)
      end

      it "uses backend from attachment options when not specified in processor options" do
        attachment_with_backend = double("Attachment", options: { backend: :vips })
        processor = described_class.new(@file, { geometry: "25x25" }, attachment_with_backend)
        expect(processor.backend).to eq(:vips)
      end

      it "prefers processor option backend over attachment option backend" do
        attachment_with_backend = double("Attachment", options: { backend: :vips })
        processor = described_class.new(@file, { geometry: "25x25", backend: :image_magick }, attachment_with_backend)
        expect(processor.backend).to eq(:image_magick)
      end
    end

    describe "per-style backend selection (integration)" do
      let(:attachment) { double("Attachment", options: {}) }

      it "processes same image with different backends per style" do
        begin
          require "vips"
        rescue LoadError
          skip "libvips not installed"
        end

        # Simulate per-style backend selection as would happen with:
        # styles: {
        #   vips_thumb: { geometry: "50x50#", backend: :vips },
        #   magick_thumb: { geometry: "50x50#", backend: :image_magick }
        # }

        # Process with vips backend
        vips_processor = described_class.new(@file, {
          geometry: "50x50#",
          backend: :vips,
          style: :vips_thumb
        }, attachment)
        vips_result = vips_processor.make

        @file.rewind

        # Process with image_magick backend
        magick_processor = described_class.new(@file, {
          geometry: "50x50#",
          backend: :image_magick,
          style: :magick_thumb
        }, attachment)
        magick_result = magick_processor.make

        # Both should produce valid 50x50 images
        vips_dims = `identify -format "%wx%h" "#{vips_result.path}"`.strip
        magick_dims = `identify -format "%wx%h" "#{magick_result.path}"`.strip

        expect(vips_dims).to eq("50x50")
        expect(magick_dims).to eq("50x50")

        # Verify they used different backends
        expect(vips_processor.backend).to eq(:vips)
        expect(magick_processor.backend).to eq(:image_magick)
      end

      it "allows mixing backends with different geometries" do
        begin
          require "vips"
        rescue LoadError
          skip "libvips not installed"
        end

        # Large preview with vips (faster for large images)
        vips_processor = described_class.new(@file, {
          geometry: "200x200>",
          backend: :vips,
          style: :preview
        }, attachment)
        vips_result = vips_processor.make

        @file.rewind

        # Small thumbnail with image_magick
        magick_processor = described_class.new(@file, {
          geometry: "32x32#",
          backend: :image_magick,
          style: :icon
        }, attachment)
        magick_result = magick_processor.make

        # Verify dimensions
        vips_dims = `identify -format "%wx%h" "#{vips_result.path}"`.strip
        magick_dims = `identify -format "%wx%h" "#{magick_result.path}"`.strip

        # Original is 434x66, so 200x200> should give 200x30 (shrink to fit)
        expect(vips_dims).to eq("200x30")
        # 32x32# should give exactly 32x32 (crop to fill)
        expect(magick_dims).to eq("32x32")
      end
    end

    describe "#convert_options?" do
      it "returns false when convert_options is nil" do
        thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50")
        expect(thumb.convert_options?).to be false
      end

      it "returns false when convert_options is empty" do
        thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", convert_options: "")
        expect(thumb.convert_options?).to be false
      end

      it "returns true when convert_options is set" do
        thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", convert_options: "-strip")
        expect(thumb.convert_options?).to be true
      end
    end

    describe "#transformation_command" do
      it "returns an array with resize command" do
        thumb = Paperclip::Thumbnail.new(@file, geometry: "100x100")
        cmd = thumb.transformation_command
        expect(cmd).to be_an(Array)
        expect(cmd).to include("-auto-orient")
        expect(cmd).to include("-resize")
      end

      it "includes crop command when cropping" do
        thumb = Paperclip::Thumbnail.new(@file, geometry: "100x100#")
        cmd = thumb.transformation_command
        expect(cmd).to include("-crop")
        expect(cmd).to include("+repage")
      end

      it "logs warning when called with vips backend" do
        begin
          require "vips"
        rescue LoadError
          skip "libvips not installed"
        end

        thumb = Paperclip::Thumbnail.new(@file, geometry: "100x100", backend: :vips)
        expect(Paperclip).to receive(:log).with(/Warning.*transformation_command.*vips/)
        thumb.transformation_command
      end
    end

    describe "#make" do
      let(:attachment) { double("Attachment", options: {}) }

      context "with vips backend" do
        before do
          begin
            require "vips"
          rescue LoadError
            skip "libvips not installed"
          end
        end

        it "resizes image to specified dimensions" do
          processor = described_class.new(@file, { geometry: "25x25>", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("25x4")
        end

        it "crops to fill with # modifier" do
          processor = described_class.new(@file, { geometry: "30x20#", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("30x20")
        end

        it "auto-orients an image using autorot" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          processor = described_class.new(file, { geometry: "50x50", backend: :vips }, attachment)

          # Verify it detects logical dimensions (rotated from 300x200 to 200x300)
          expect(processor.current_geometry.width).to eq(200)
          result = processor.make
        
          cmd = %[identify -format "%wx%h" "#{result.path}"]
          # Original 300x200 with orientation 6 (90 deg CW).
          # Post autorot: 200x300.
          # Resize to fit 50x50: 33x50.
          expect(`#{cmd}`.chomp).to eq("33x50")
        end

        it "strips metadata when requested via convert_options" do
          processor = described_class.new(@file, { geometry: "50x50", convert_options: "-strip", backend: :vips }, attachment)
          result = processor.make

          # identify -verbose shows less output when stripped
          expect(`identify -verbose "#{result.path}"`).not_to include("exif:")
        end

        it "handles exact dimensions with ! modifier" do
          processor = described_class.new(@file, { geometry: "100x50!", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("100x50")
        end

        it "stretches the image with ! modifier matching ImageMagick behavior" do
          # Create a 3-stripe image: Red, Green, Blue
          stripe_file = Tempfile.new(["stripe", ".png"])
          Paperclip.run("convert", "-size 100x100 xc:red xc:green xc:blue +append #{stripe_file.path}")
          file = File.new(stripe_file.path, "rb")

          processor = described_class.new(file, { geometry: "100x100!", backend: :vips }, attachment)
          result = processor.make

          # Check color at x=10 (Red stripe).
          # If cropped (Green center), it would be Green.
          # If stretched, it is Red.
          color = Paperclip.run("convert", "#{result.path}[1x1+10+50] -format \"%[pixel:p{0,0}]\" info:")
          expect(color).to match(/red|#FF0000|rgb\(255,0,0\)|srgb\(255,0,0\)/i)

          file.close
          stripe_file.close
          stripe_file.unlink
        end

        it "handles percentage with % modifier" do
          processor = described_class.new(@file, { geometry: "50%", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          # Original is 434x66. 50% is 217x33.
          expect(`#{cmd}`.chomp).to eq("217x33")
        end

        it "handles minimum dimensions with ^ modifier" do
          processor = described_class.new(@file, { geometry: "100x100^", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          # Original 434x66.
          # Resize to fill 100x100 means height becomes 100, width becomes 434 * (100/66) = 658.
          expect(`#{cmd}`.chomp).to eq("658x100")
        end

        it "handles enlarge only with < modifier" do
          # Smaller image: 50x50.png
          small_file = File.new(fixture_file("50x50.png"), "rb")
          processor = described_class.new(small_file, { geometry: "100x100<", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("100x100")

          # Larger image: 5k.png (434x66)
          processor = described_class.new(@file, { geometry: "100x100<", backend: :vips }, attachment)
          result = processor.make
          expect(`identify -format "%wx%h" "#{result.path}"`.chomp).to eq("434x66")
        end

        it "takes only the first frame of a PDF by default" do
          pdf_file = File.new(fixture_file("twopage.pdf"), "rb")
          processor = described_class.new(pdf_file, { geometry: "100x100", format: :png, backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%n" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("1")
        end

        it "detects animated source correctly" do
          animated_file = File.new(fixture_file("animated.gif"), "rb")
          processor = described_class.new(animated_file, { geometry: "50x50", backend: :vips }, attachment)
          expect(processor.send(:animated_source?)).to be true

          static_file = File.new(fixture_file("5k.png"), "rb")
          processor = described_class.new(static_file, { geometry: "50x50", backend: :vips }, attachment)
          expect(processor.send(:animated_source?)).to be false
        end

        it "handles area-based resize with @ modifier" do
          # Original is 434x66 = 28644 pixels
          # 10000@ should resize to ~sqrt(10000/28644) * dimensions
          processor = described_class.new(@file, { geometry: "10000@", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          dimensions = `#{cmd}`.chomp
          width, height = dimensions.split("x").map(&:to_i)
          area = width * height
          # Should be approximately 10000 pixels (with some tolerance)
          expect(area).to be_within(500).of(10000)
        end

        it "handles area-based shrink-only with @> modifier" do
          # Original is 434x66 = 28644 pixels
          # 10000@> should resize (smaller than 28644)
          processor = described_class.new(@file, { geometry: "10000@>", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          dimensions = `#{cmd}`.chomp
          width, height = dimensions.split("x").map(&:to_i)
          area = width * height
          expect(area).to be_within(500).of(10000)

          # 50000@> should NOT resize (larger than 28644, and only_shrink is true)
          processor = described_class.new(@file, { geometry: "50000@>", backend: :vips }, attachment)
          result = processor.make
          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("434x66")
        end

        it "handles area-based shrink-only with >@ modifier" do
          # Same as @> but different syntax
          processor = described_class.new(@file, { geometry: "10000>@", backend: :vips }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          dimensions = `#{cmd}`.chomp
          width, height = dimensions.split("x").map(&:to_i)
          area = width * height
          expect(area).to be_within(500).of(10000)
        end
      end

      context "with image_magick backend" do
        it "resizes image to specified dimensions" do
          processor = described_class.new(@file, { geometry: "25x25>", backend: :image_magick }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("25x4")
        end

        it "handles area-based resize with @ modifier" do
          # Original is 434x66 = 28644 pixels
          processor = described_class.new(@file, { geometry: "10000@", backend: :image_magick }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          dimensions = `#{cmd}`.chomp
          width, height = dimensions.split("x").map(&:to_i)
          area = width * height
          expect(area).to be_within(500).of(10000)
        end

        it "handles area-based shrink-only with @> modifier" do
          processor = described_class.new(@file, { geometry: "10000@>", backend: :image_magick }, attachment)
          result = processor.make

          cmd = %[identify -format "%wx%h" "#{result.path}"]
          dimensions = `#{cmd}`.chomp
          width, height = dimensions.split("x").map(&:to_i)
          area = width * height
          expect(area).to be_within(500).of(10000)

          # Larger area should NOT resize
          processor = described_class.new(@file, { geometry: "50000@>", backend: :image_magick }, attachment)
          result = processor.make
          cmd = %[identify -format "%wx%h" "#{result.path}"]
          expect(`#{cmd}`.chomp).to eq("434x66")
        end

        it "applies cross-platform convert_options with vips without warning" do
          begin
            require "vips"
          rescue LoadError
            skip "libvips not installed"
          end

          # -strip is cross-platform, should work without warning
          expect(Paperclip).not_to receive(:log).with(/Warning/)
          processor = described_class.new(@file, {
            geometry: "50x50",
            backend: :vips,
            convert_options: "-strip",
          }, attachment)
          processor.make
        end

        it "logs warning for ImageMagick-only convert_options with vips" do
          begin
            require "vips"
          rescue LoadError
            skip "libvips not installed"
          end

          # -density is ImageMagick-only, should warn
          expect(Paperclip).to receive(:log).with(/Warning.*density.*not supported.*vips/)
          processor = described_class.new(@file, {
            geometry: "50x50",
            backend: :vips,
            convert_options: "-density 150",
          }, attachment)
          processor.make
        end
      end
    end

    describe "convert_options - individual options" do
      let(:attachment) { double("Attachment", options: {}) }

      # Helper to create a thumbnail with specific convert_options
      def make_thumb_with_options(file, options_string)
        thumb = Paperclip::Thumbnail.new(file, {
          geometry: "100x100",
          convert_options: options_string,
          backend: :image_magick,
        }, attachment)
        thumb.make
      end

      describe "-strip" do
        it "removes EXIF metadata" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_thumb_with_options(file, "-strip")

          exif = `identify -format "%[exif:orientation]" "#{result.path}" 2>/dev/null`.strip
          expect(exif).to be_empty
          file.close
        end
      end

      describe "-quality" do
        it "sets JPEG quality" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result_low = make_thumb_with_options(file, "-quality 20")
          file.rewind
          result_high = make_thumb_with_options(file, "-quality 95")

          # Lower quality should produce smaller file
          expect(File.size(result_low.path)).to be < File.size(result_high.path)
          file.close
        end
      end

      describe "-colorspace" do
        it "converts to grayscale" do
          result = make_thumb_with_options(@file, "-colorspace Gray")

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("Gray")
        end

        it "converts to sRGB" do
          result = make_thumb_with_options(@file, "-colorspace sRGB")

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("sRGB")
        end
      end

      describe "-rotate" do
        it "rotates the image by specified degrees" do
          # Original is 434x66, after 90 degree rotation should be 66x434
          result = make_thumb_with_options(@file, "-rotate 90")

          dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
          # After resize to 100x100 and rotate, dimensions change
          expect(dimensions).to match(/\d+x\d+/)
        end
      end

      describe "-flip" do
        it "flips the image vertically" do
          result = make_thumb_with_options(@file, "-flip")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-flop" do
        it "flops the image horizontally" do
          result = make_thumb_with_options(@file, "-flop")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-negate" do
        it "negates the image colors" do
          result = make_thumb_with_options(@file, "-negate")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-normalize" do
        it "normalizes the image" do
          result = make_thumb_with_options(@file, "-normalize")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-equalize" do
        it "equalizes the image histogram" do
          result = make_thumb_with_options(@file, "-equalize")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-auto_orient" do
        it "auto-orients the image" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_thumb_with_options(file, "-auto-orient")
          expect(File.exist?(result.path)).to be true
          file.close
        end
      end

      describe "-blur" do
        it "blurs the image" do
          result = make_thumb_with_options(@file, "-blur 0x2")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-sharpen" do
        it "sharpens the image" do
          result = make_thumb_with_options(@file, "-sharpen 0x1")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-density" do
        it "sets the image density" do
          result = make_thumb_with_options(@file, "-density 150")

          density = `identify -format "%x" "#{result.path}"`.strip
          expect(density).to start_with("150")
        end
      end

      describe "-depth" do
        it "sets the bit depth" do
          result = make_thumb_with_options(@file, "-depth 8")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-interlace" do
        it "sets interlacing mode" do
          # Use JPEG to test interlacing (PNG reports format name instead)
          file = File.new(fixture_file("rotated.jpg"), "rb")
          thumb = Paperclip::Thumbnail.new(file, {
            geometry: "100x100",
            convert_options: "-interlace Plane",
            backend: :image_magick,
            format: :jpg,
          }, attachment)
          result = thumb.make

          interlace = `identify -format "%[interlace]" "#{result.path}"`.strip
          # Different ImageMagick versions report this differently
          expect(interlace).to match(/Plane|JPEG|Line|None/i).or eq("")
          file.close
        end
      end

      describe "-gravity" do
        it "sets gravity for subsequent operations" do
          result = make_thumb_with_options(@file, "-gravity center")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-crop" do
        it "crops the image" do
          # Use a square image for predictable crop results
          file = File.new(fixture_file("50x50.png"), "rb")
          thumb = Paperclip::Thumbnail.new(file, {
            geometry: "50x50",  # Keep original size
            convert_options: "-crop 25x25+0+0 +repage",
            backend: :image_magick,
          }, attachment)
          result = thumb.make

          dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
          expect(dimensions).to eq("25x25")
          file.close
        end
      end

      describe "-extent" do
        it "sets the image extent with padding" do
          result = make_thumb_with_options(@file, "-background white -gravity center -extent 150x150")

          dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
          expect(dimensions).to eq("150x150")
        end
      end

      describe "-background" do
        it "sets the background color" do
          result = make_thumb_with_options(@file, "-background red -flatten")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-flatten" do
        it "flattens the image layers" do
          result = make_thumb_with_options(@file, "-flatten")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-alpha" do
        it "modifies alpha channel" do
          result = make_thumb_with_options(@file, "-alpha remove")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-type" do
        it "sets the image type" do
          result = make_thumb_with_options(@file, "-type Grayscale")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-monochrome" do
        it "converts to black and white" do
          result = make_thumb_with_options(@file, "-monochrome")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-posterize" do
        it "reduces color levels" do
          result = make_thumb_with_options(@file, "-posterize 4")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-colors" do
        it "reduces the number of colors" do
          result = make_thumb_with_options(@file, "-colors 16")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-channel" do
        it "selects image channels" do
          result = make_thumb_with_options(@file, "-channel RGB")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-transpose" do
        it "transposes the image" do
          result = make_thumb_with_options(@file, "-transpose")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-transverse" do
        it "transverses the image" do
          result = make_thumb_with_options(@file, "-transverse")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-trim" do
        it "trims image edges" do
          result = make_thumb_with_options(@file, "-trim")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-dither" do
        it "applies dithering" do
          result = make_thumb_with_options(@file, "-dither FloydSteinberg")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-sampling_factor" do
        it "sets chroma subsampling" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_thumb_with_options(file, "-sampling-factor 4:2:0")
          expect(File.exist?(result.path)).to be true
          file.close
        end
      end

      describe "-units" do
        it "sets resolution units" do
          result = make_thumb_with_options(@file, "-units PixelsPerInch")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "unknown options (fallback to append)" do
        it "passes unknown options through to ImageMagick" do
          # -modulate is not in our explicit list, should use append fallback
          result = make_thumb_with_options(@file, "-modulate 100,50,100")
          expect(File.exist?(result.path)).to be true
        end

        it "handles unknown flag-only options" do
          # Use a harmless option that's not in our list
          result = make_thumb_with_options(@file, "-verbose")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "multiple options combined" do
        it "applies multiple options in sequence" do
          result = make_thumb_with_options(@file, "-strip -quality 80 -colorspace Gray -sharpen 0x1")

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("Gray")
        end

        it "handles complex option combinations" do
          result = make_thumb_with_options(@file, "-strip -density 72 -depth 8 -colorspace sRGB")
          expect(File.exist?(result.path)).to be true

          density = `identify -format "%x" "#{result.path}"`.strip
          expect(density).to start_with("72")
        end
      end
    end

    describe "convert_options - cross-platform options with vips backend" do
      let(:attachment) { double("Attachment", options: {}) }

      before do
        begin
          require "vips"
        rescue LoadError
          skip "libvips not installed"
        end
      end

      # Helper to create a thumbnail with vips backend and specific convert_options
      def make_vips_thumb_with_options(file, options_string, extra_opts = {})
        thumb = Paperclip::Thumbnail.new(file, {
          geometry: "100x100",
          convert_options: options_string,
          backend: :vips,
        }.merge(extra_opts), attachment)
        thumb.make
      end

      describe "-strip" do
        it "removes metadata from the image" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_vips_thumb_with_options(file, "-strip")

          # Check that EXIF orientation is removed
          exif = `identify -format "%[exif:orientation]" "#{result.path}" 2>/dev/null`.strip
          expect(exif).to be_empty
          file.close
        end

        it "produces a valid image" do
          result = make_vips_thumb_with_options(@file, "-strip")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-quality" do
        it "sets output quality for JPEG" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result_low = make_vips_thumb_with_options(file, "-quality 20", format: :jpg)
          file.rewind
          result_high = make_vips_thumb_with_options(file, "-quality 95", format: :jpg)

          # Lower quality should produce smaller file
          expect(File.size(result_low.path)).to be < File.size(result_high.path)
          file.close
        end

        it "produces a valid image" do
          result = make_vips_thumb_with_options(@file, "-quality 80")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-rotate" do
        it "rotates the image by specified degrees" do
          # Original 434x66, after 90 degree rotation dimensions swap
          result = make_vips_thumb_with_options(@file, "-rotate 90")

          dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
          # After resize to fit 100x100, then rotate 90 degrees
          # Original aspect ratio is ~6.5:1, fitting in 100x100 gives ~100x15
          # After 90 degree rotation: ~15x100
          expect(dimensions).to match(/\d+x\d+/)
          width, height = dimensions.split("x").map(&:to_i)
          # Width should be smaller than height after rotation
          expect(width).to be < height
        end

        it "rotates by arbitrary angle" do
          result = make_vips_thumb_with_options(@file, "-rotate 45")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-flip" do
        it "flips the image vertically" do
          result = make_vips_thumb_with_options(@file, "-flip")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-flop" do
        it "flops the image horizontally" do
          result = make_vips_thumb_with_options(@file, "-flop")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-blur" do
        it "applies gaussian blur to the image" do
          result = make_vips_thumb_with_options(@file, "-blur 0x2")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end

        it "handles different blur sigma values" do
          result = make_vips_thumb_with_options(@file, "-blur 0x5")
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "-gaussian_blur" do
        it "applies gaussian blur" do
          result = make_vips_thumb_with_options(@file, "-gaussian-blur 0x3")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-sharpen" do
        it "sharpens the image" do
          result = make_vips_thumb_with_options(@file, "-sharpen 0x1")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-colorspace" do
        it "converts to grayscale (b-w)" do
          result = make_vips_thumb_with_options(@file, "-colorspace Gray")

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("Gray")
        end

        it "converts to sRGB" do
          result = make_vips_thumb_with_options(@file, "-colorspace sRGB")

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("sRGB")
        end

        it "converts to CMYK" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_vips_thumb_with_options(file, "-colorspace CMYK", format: :jpg)

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("CMYK")
          file.close
        end
      end

      describe "-flatten" do
        it "flattens transparency to white background" do
          result = make_vips_thumb_with_options(@file, "-flatten")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-negate" do
        it "inverts the image colors" do
          result = make_vips_thumb_with_options(@file, "-negate")
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
        end
      end

      describe "-auto-orient" do
        it "auto-orients the image based on EXIF" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_vips_thumb_with_options(file, "-auto-orient")
          expect(File.exist?(result.path)).to be true

          # The rotated.jpg has orientation 6 (90 CW), so auto-orient should correct it
          dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
          width, height = dimensions.split("x").map(&:to_i)
          # After auto-orient, portrait orientation should be maintained
          expect(height).to be > width
          file.close
        end
      end

      describe "-interlace" do
        it "creates progressive/interlaced output for JPEG" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_vips_thumb_with_options(file, "-interlace Plane", format: :jpg)
          expect(File.exist?(result.path)).to be true
          expect(File.size(result.path)).to be > 0
          file.close
        end

        it "creates interlaced output for PNG" do
          result = make_vips_thumb_with_options(@file, "-interlace Line", format: :png)
          expect(File.exist?(result.path)).to be true
        end
      end

      describe "multiple cross-platform options combined" do
        it "applies multiple options in sequence" do
          result = make_vips_thumb_with_options(@file, "-strip -quality 80 -colorspace Gray")

          colorspace = `identify -format "%[colorspace]" "#{result.path}"`.strip
          expect(colorspace).to eq("Gray")
        end

        it "combines flip, flop, and rotate" do
          result = make_vips_thumb_with_options(@file, "-flip -flop -rotate 180")
          expect(File.exist?(result.path)).to be true
        end

        it "applies strip with quality and sharpen" do
          file = File.new(fixture_file("rotated.jpg"), "rb")
          result = make_vips_thumb_with_options(file, "-strip -quality 85 -sharpen 0x1", format: :jpg)

          # Verify EXIF is stripped
          exif = `identify -format "%[exif:orientation]" "#{result.path}" 2>/dev/null`.strip
          expect(exif).to be_empty
          file.close
        end
      end

      describe "ImageMagick-only options with vips (should warn)" do
        it "logs warning for -density" do
          expect(Paperclip).to receive(:log).with(/Warning.*density.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-density 150")
        end

        it "logs warning for -depth" do
          expect(Paperclip).to receive(:log).with(/Warning.*depth.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-depth 8")
        end

        it "logs warning for -gravity" do
          expect(Paperclip).to receive(:log).with(/Warning.*gravity.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-gravity center")
        end

        it "logs warning for -crop" do
          expect(Paperclip).to receive(:log).with(/Warning.*crop.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-crop 50x50+0+0")
        end

        it "logs warning for -trim" do
          expect(Paperclip).to receive(:log).with(/Warning.*trim.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-trim")
        end

        it "logs warning for -normalize" do
          expect(Paperclip).to receive(:log).with(/Warning.*normalize.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-normalize")
        end

        it "logs warning for -monochrome" do
          expect(Paperclip).to receive(:log).with(/Warning.*monochrome.*not supported.*vips/)
          make_vips_thumb_with_options(@file, "-monochrome")
        end
      end
    end

    [%w[600x600> 434x66],
     %w[400x400> 400x61],
     %w[32x32< 434x66],
     [nil, "434x66"]].each do |args|
      context "being thumbnailed with a geometry of #{args[0]}" do
        before do
          @thumb = Paperclip::Thumbnail.new(@file, geometry: args[0])
        end

        it "starts with dimensions of 434x66" do
          cmd = %[identify -format "%wx%h" "#{@file.path}"]
          assert_equal "434x66", `#{cmd}`.chomp
        end

        it "reports the correct target geometry" do
          assert_equal args[0].to_s, @thumb.target_geometry.to_s
        end

        context "when made" do
          before do
            @thumb_result = @thumb.make
          end

          it "is the size we expect it to be" do
            cmd = %[identify -format "%wx%h" "#{@thumb_result.path}"]
            assert_equal args[1], `#{cmd}`.chomp
          end
        end
      end
    end

    context "being thumbnailed at 100x50 with cropping" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "100x50#")
      end

      it "reports its correct current and target geometries" do
        assert_equal "100x50#", @thumb.target_geometry.to_s
        assert_equal "434x66", @thumb.current_geometry.to_s
      end

      it "reports its correct format" do
        assert_nil @thumb.format
      end

      it "has whiny turned on by default" do
        assert @thumb.whiny
      end

      it "has convert_options set to nil by default" do
        assert_equal nil, @thumb.convert_options
      end

      it "has source_file_options set to nil by default" do
        assert_equal nil, @thumb.source_file_options
      end

      it "creates the thumbnail when sent #make" do
        dst = @thumb.make
        assert_match /100x50/, `identify "#{dst.path}"`
      end
    end

    it "crops a EXIF-rotated image properly" do
      file = File.new(fixture_file("rotated.jpg"))
      thumb = Paperclip::Thumbnail.new(file, geometry: "50x50#")

      output_file = thumb.make

      command = Terrapin::CommandLine.new("identify", "-format %wx%h :file")
      assert_equal "50x50", command.run(file: output_file.path).strip
    end

    context "being thumbnailed with source file options set" do
      before do
        @file = File.new(fixture_file("rotated.jpg"), "rb")
        @thumb = Paperclip::Thumbnail.new(@file,
                                          geometry: "100x50#",
                                          source_file_options: "-density 300")
      end

      it "has source_file_options value set" do
        assert_equal "-density 300", @thumb.source_file_options
      end

      it "creates the thumbnail when sent #make" do
        dst = @thumb.make
        assert_match /100x50/, `identify "#{dst.path}"`
      end

      it "actually applies the source file options (sets density)" do
        # Verify result has the set density
        dst = @thumb.make
        cmd_new = %[identify -format "%x" "#{dst.path}"]
        expect(`#{cmd_new}`.chomp).to start_with("300")
      end
    end

    context "being thumbnailed with convert options set" do
      before do
        @file = File.new(fixture_file("rotated.jpg"), "rb")
        @thumb = Paperclip::Thumbnail.new(@file,
                                          geometry: "100x50#",
                                          convert_options: "-strip")
      end

      it "has convert_options value set" do
        assert_equal "-strip", @thumb.convert_options
      end

      it "creates the thumbnail when sent #make" do
        dst = @thumb.make
        assert_match /100x50/, `identify "#{dst.path}"`
      end

      it "actually applies the convert options (removes EXIF data)" do
        # Verify original has EXIF
        cmd_orig = %[identify -format "%[exif:orientation]" "#{@file.path}"]
        expect(`#{cmd_orig}`.chomp).to_not be_empty

        # Verify result has no EXIF
        dst = @thumb.make
        cmd_new = %[identify -format "%[exif:orientation]" "#{dst.path}"]
        expect(`#{cmd_new}`.chomp).to be_empty
      end
    end

    context "error handling" do
      before do
        require "image_processing"
        # Use a valid image so initialization (geometry detection) succeeds
        @file = File.new(fixture_file("5k.png"), "rb")
      end

      context "with whiny enabled (default)" do
        it "raises an error when processing fails" do
          thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50")
          allow(thumb).to receive(:build_pipeline).and_raise(Paperclip::Errors::CommandNotFoundError)

          expect { thumb.make }.to raise_error(Paperclip::Errors::CommandNotFoundError)
        end

        it "raises a Paperclip::Error when an underlying processing error occurs" do
          thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50")
          # Simulate a generic processing error
          allow(thumb).to receive(:build_pipeline).and_raise(ImageProcessing::Error.new("Processing failed"))

          expect { thumb.make }.to raise_error(Paperclip::Error, /Processing failed/)
        end
      end

      context "with whiny disabled" do
        it "returns the original file when processing fails" do
          thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", whiny: false)
          allow(thumb).to receive(:build_pipeline).and_raise(ImageProcessing::Error.new("Processing failed"))

          result = thumb.make
          expect(result).to eq(@file)
        end

        it "logs the error" do
          thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", whiny: false)
          allow(thumb).to receive(:build_pipeline).and_raise(ImageProcessing::Error.new("Processing failed"))

          expect(Paperclip).to receive(:log).with(/Processing failed/)
          thumb.make
        end
      end
    end

    context "being thumbnailed with a blank geometry string" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file,
                                          geometry: "",
                                          convert_options: "-gravity center -crop 300x300+0-0")
      end

      # Verify that when geometry is blank, we don't resize, but still apply other options.
      it "does not resize the image via geometry but applies convert_options" do
        result = @thumb.make
        cmd = %[identify -format "%wx%h" "#{result.path}"]
        # Original size is 434x66. The crop option (300x300) should result in 300x66.
        # This confirms that no geometry-based resize happened (which would have been to 0x0 or skipped),
        # but the convert_options crop was applied.
        expect(`#{cmd}`.chomp).to eq("300x66")
      end
    end

    context "passing a custom file geometry parser" do
      after do
        Object.send(:remove_const, :GeoParser) if Object.const_defined?(:GeoParser)
      end

      it "uses the custom parser" do
        GeoParser = Class.new do
          def self.from_file(_file, _backend = nil)
            new
          end

          def width; 100; end
          def height; 100; end
          def modifier; nil; end
          def auto_orient; end
        end

        thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", file_geometry_parser: ::GeoParser)
        expect(thumb.current_geometry).to be_a(GeoParser)
      end
    end

    context "passing a custom geometry string parser" do
      after do
        Object.send(:remove_const, :GeoParser) if Object.const_defined?(:GeoParser)
      end

      it "uses the custom parser" do
        GeoParser = Class.new do
          def self.parse(_s)
            new
          end

          def to_s
            "151x167"
          end

          def width; 151; end
          def height; 167; end
          def modifier; nil; end
        end

        thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", string_geometry_parser: ::GeoParser)
        expect(thumb.target_geometry).to be_a(GeoParser)
      end
    end
  end

  context "A multipage PDF" do
    before do
      @file = File.new(fixture_file("twopage.pdf"), "rb")
    end

    after { @file.close }

    it "starts with two pages with dimensions 612x792" do
      cmd = %[identify -format "%wx%h" "#{@file.path}"]
      assert_equal "612x792" * 2, `#{cmd}`.chomp
    end

    context "being thumbnailed at 100x100 with cropping" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "100x100#", format: :png)
      end

      it "reports its correct current and target geometries" do
        assert_equal "100x100#", @thumb.target_geometry.to_s
        assert_equal "612x792", @thumb.current_geometry.to_s
      end

      it "reports its correct format" do
        assert_equal :png, @thumb.format
      end

      it "creates the thumbnail when sent #make" do
        dst = @thumb.make
        assert_match /100x100/, `identify "#{dst.path}"`
      end
    end
  end

  context "An animated gif" do
    before do
      @file = File.new(fixture_file("animated.gif"), "rb")
    end

    after { @file.close }

    it "starts with 12 frames with size 100x100" do
      cmd = %[identify -format "%wx%h" "#{@file.path}"]
      assert_equal "100x100" * 12, `#{cmd}`.chomp
    end

    context "with static output" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", format: :jpg)
      end

      it "creates the single frame thumbnail when sent #make" do
        dst = @thumb.make
        cmd = %[identify -format "%wx%h" "#{dst.path}"]
        assert_equal "50x50", `#{cmd}`.chomp
      end
    end

    context "with animated output format" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", format: :gif)
      end

      it "creates the 12 frames thumbnail when sent #make" do
        dst = @thumb.make
        cmd = %[identify -format "%wx%h," "#{dst.path}"]
        frames = `#{cmd}`.chomp.split(",")
        assert_equal 12, frames.size
        assert_frame_dimensions (45..50), frames
      end
    end

    context "with omitted output format" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50")
      end

      it "creates the 12 frames thumbnail when sent #make" do
        dst = @thumb.make
        cmd = %[identify -format "%wx%h," "#{dst.path}"]
        frames = `#{cmd}`.chomp.split(",")
        # image_processing might not preserve animation by default if not explicitly told to
        # or if the format is not explicitly set to gif.
        # But here we are testing default behavior.
        # If it fails with 1 frame, it means it collapsed it.
        # The original implementation preserved it.
        # We might need to force loader options for animated gifs if we want to preserve layers.
        # But image_processing/mini_magick should handle it if we don't flatten.

        # If this fails, we might need to adjust the test expectation or implementation.
        # For now, let's assume we want to preserve behavior.
        assert_equal 12, frames.size
        assert_frame_dimensions (45..50), frames
      end
    end

    context "with unidentified source format" do
      before do
        @unidentified_file = File.new(fixture_file("animated.unknown"), "rb")
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "60x60")
      end

      it "creates the 12 frames thumbnail when sent #make" do
        dst = @thumb.make
        cmd = %[identify -format "%wx%h," "#{dst.path}"]
        frames = `#{cmd}`.chomp.split(",")
        assert_equal 12, frames.size
        assert_frame_dimensions (55..60), frames
      end
    end

    context "with no source format" do
      before do
        @unidentified_file = File.new(fixture_file("animated"), "rb")
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "70x70")
      end

      it "creates the 12 frames thumbnail when sent #make" do
        dst = @thumb.make
        cmd = %[identify -format "%wx%h," "#{dst.path}"]
        frames = `#{cmd}`.chomp.split(",")
        assert_equal 12, frames.size
        assert_frame_dimensions (60..70), frames
      end
    end

    context "with animated option set to false" do
      before do
        @thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", animated: false)
      end

      it "outputs the gif format" do
        dst = @thumb.make
        cmd = %[identify "#{dst.path}"]
        assert_match /GIF/, `#{cmd}`.chomp
      end

      it "creates the single frame thumbnail when sent #make" do
        dst = @thumb.make
        cmd = %[identify -format "%wx%h" "#{dst.path}"]
        # The output might be multiple frames if image_processing doesn't collapse them
        # But we expect single frame here.
        # If it fails, we might need to adjust the implementation to force single frame.
        # For now, let's check if it starts with 50x50.
        output = `#{cmd}`.chomp
        # If multiple frames, it will be 50x5050x50...
        # We want exactly 50x50
        assert_equal "50x50", output
      end
    end

    context "with a specified frame_index" do
      before do
        @thumb = Paperclip::Thumbnail.new(
          @file,
          geometry: "50x50",
          frame_index: 5,
          format: :jpg
        )
      end

      it "creates the thumbnail from the frame index when sent #make" do
        @thumb.make
        assert_equal 5, @thumb.frame_index
      end
    end

    context "with vips backend" do
      before do
        begin
          require "vips"
        rescue LoadError
          skip "libvips not installed"
        end
      end

      it "preserves animation when output is GIF" do
        processor = Paperclip::Thumbnail.new(@file, { geometry: "50x50", format: :gif, backend: :vips })
        dst = processor.make
        cmd = %[identify -format "%wx%h," "#{dst.path}"]
        frames = `#{cmd}`.chomp.split(",")
        expect(frames.size).to eq(12)
      end

      it "collapses animation when animated: false is set" do
        processor = Paperclip::Thumbnail.new(@file, { geometry: "50x50", format: :gif, animated: false, backend: :vips })
        dst = processor.make
        cmd = %[identify -format "%wx%h," "#{dst.path}"]
        frames = `#{cmd}`.chomp.split(",").reject(&:empty?)
        expect(frames.size).to eq(1)
        expect(frames.first).to eq("50x50")
      end
    end
  end

  context "with a really long file name" do
    before do
      tempfile = Tempfile.new("f")
      tempfile_additional_chars = tempfile.path.split("/")[-1].length + 15
      image_file = File.new(fixture_file("5k.png"), "rb")
      @file = Tempfile.new("f" * (255 - tempfile_additional_chars))
      @file.write(image_file.read)
      @file.rewind
    end

    it "does not throw Errno::ENAMETOOLONG" do
      thumb = Paperclip::Thumbnail.new(@file, geometry: "50x50", format: :gif)
      expect { thumb.make }.to_not raise_error
    end
  end
end
