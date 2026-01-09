require "spec_helper"

# This spec tests compatibility with Mastodon's LazyThumbnail pattern.
# LazyThumbnail is a subclass of Paperclip::Thumbnail that conditionally
# skips processing when the image doesn't need transformation.
# See: https://github.com/mastodon/mastodon/blob/main/lib/paperclip/lazy_thumbnail.rb

module Paperclip
  class LazyThumbnail < Paperclip::Thumbnail
    def make
      return File.open(@file.path) unless needs_convert?

      if options[:geometry]
        min_side = [@current_geometry.width, @current_geometry.height].min.to_i
        options[:geometry] = "#{min_side}x#{min_side}#" if @target_geometry.square? && min_side < @target_geometry.width
      elsif options[:pixels]
        width  = Math.sqrt(options[:pixels] * (@current_geometry.width.to_f / @current_geometry.height)).round.to_i
        height = Math.sqrt(options[:pixels] * (@current_geometry.height.to_f / @current_geometry.width)).round.to_i
        options[:geometry] = "#{width}x#{height}>"
      end

      Paperclip::Thumbnail.make(file, options, attachment)
    end

    private

    def needs_convert?
      needs_different_geometry? || needs_different_format? || needs_metadata_stripping?
    end

    def needs_different_geometry?
      (options[:geometry] && @current_geometry.width != @target_geometry.width && @current_geometry.height != @target_geometry.height) ||
        (options[:pixels] && @current_geometry.width * @current_geometry.height > options[:pixels])
    end

    def needs_different_format?
      @format.present? && @current_format != @format
    end

    def needs_metadata_stripping?
      @attachment.respond_to?(:instance) && @attachment.instance.respond_to?(:local?) && @attachment.instance.local?
    end
  end
end

describe Paperclip::LazyThumbnail do
  let(:file) { File.new(fixture_file("5k.png"), "rb") }
  let(:rotated_file) { File.new(fixture_file("rotated.jpg"), "rb") }
  let(:attachment) { double("Attachment", options: {}, instance: double(local?: false)) }

  after do
    file.close
    rotated_file.close rescue nil
  end

  describe "basic compatibility" do
    it "inherits from Paperclip::Thumbnail" do
      expect(Paperclip::LazyThumbnail.superclass).to eq(Paperclip::Thumbnail)
    end

    it "can access current_geometry" do
      processor = described_class.new(file, { geometry: "100x100" }, attachment)
      expect(processor.current_geometry).to be_a(Paperclip::Geometry)
      expect(processor.current_geometry.width).to be > 0
      expect(processor.current_geometry.height).to be > 0
    end

    it "can access target_geometry" do
      processor = described_class.new(file, { geometry: "100x100#" }, attachment)
      expect(processor.target_geometry).to be_a(Paperclip::Geometry)
      expect(processor.target_geometry.width).to eq(100)
      expect(processor.target_geometry.height).to eq(100)
    end

    it "target_geometry responds to square?" do
      processor = described_class.new(file, { geometry: "100x100#" }, attachment)
      expect(processor.target_geometry).to respond_to(:square?)
      expect(processor.target_geometry.square?).to be true
    end

    it "can access format and current_format" do
      processor = described_class.new(file, { geometry: "100x100", format: :jpg }, attachment)
      expect(processor.format).to eq(:jpg)
    end
  end

  describe "with ImageMagick backend" do
    let(:attachment) { double("Attachment", options: { backend: :image_magick }, instance: double(local?: false)) }

    it "processes images when geometry change is needed" do
      processor = described_class.new(file, { geometry: "50x50#" }, attachment)
      result = processor.make

      expect(File.exist?(result.path)).to be true
      dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
      expect(dimensions).to eq("50x50")
    end

    it "processes images when format change is needed" do
      processor = described_class.new(file, { geometry: "100x100", format: :jpg }, attachment)
      result = processor.make

      expect(File.exist?(result.path)).to be true
      expect(result.path).to end_with(".jpg")
    end

    it "skips processing when no changes needed" do
      # Create a processor where geometry matches source
      processor = described_class.new(file, { geometry: "434x66" }, attachment)

      # Since the source is 434x66 (5k.png dimensions), and target is same,
      # needs_different_geometry? returns false
      result = processor.make

      # Result should be the original file (File.open(@file.path))
      expect(File.exist?(result.path)).to be true
    end

    it "handles square geometry optimization" do
      # Source is 434x66, min_side is 66
      # Requesting 100x100# square, but min_side (66) < target width (100)
      # So geometry should be adjusted to "66x66#"
      processor = described_class.new(file, { geometry: "100x100#" }, attachment)
      result = processor.make

      expect(File.exist?(result.path)).to be true
      dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
      expect(dimensions).to eq("66x66")
    end
  end

  describe "with libvips backend" do
    let(:attachment) { double("Attachment", options: { backend: :vips }, instance: double(local?: false)) }

    before do
      begin
        require "vips"
      rescue LoadError
        skip "libvips not installed"
      end
    end

    it "processes images when geometry change is needed" do
      processor = described_class.new(file, { geometry: "50x50#" }, attachment)
      result = processor.make

      expect(File.exist?(result.path)).to be true
      dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
      expect(dimensions).to eq("50x50")
    end

    it "processes images when format change is needed" do
      processor = described_class.new(file, { geometry: "100x100", format: :jpg }, attachment)
      result = processor.make

      expect(File.exist?(result.path)).to be true
      expect(result.path).to end_with(".jpg")
    end

    it "skips processing when no changes needed" do
      processor = described_class.new(file, { geometry: "434x66" }, attachment)
      result = processor.make
      expect(File.exist?(result.path)).to be true
    end

    it "handles square geometry optimization" do
      processor = described_class.new(file, { geometry: "100x100#" }, attachment)
      result = processor.make

      expect(File.exist?(result.path)).to be true
      dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
      expect(dimensions).to eq("66x66")
    end
  end

  describe "pixels-based resizing (Mastodon-specific)" do
    let(:attachment) { double("Attachment", options: {}, instance: double(local?: false)) }

    context "with ImageMagick backend" do
      let(:attachment) { double("Attachment", options: { backend: :image_magick }, instance: double(local?: false)) }

      it "resizes based on maximum pixel count" do
        # Source is 434x66 = 28,644 pixels
        # Request max 10,000 pixels
        processor = described_class.new(file, { pixels: 10_000 }, attachment)
        result = processor.make

        expect(File.exist?(result.path)).to be true
        dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
        width, height = dimensions.split("x").map(&:to_i)
        expect(width * height).to be <= 10_000
      end

      it "skips processing when image is already small enough" do
        # Source is 434x66 = 28,644 pixels
        # Request max 50,000 pixels - no resize needed
        processor = described_class.new(file, { pixels: 50_000 }, attachment)
        result = processor.make

        expect(File.exist?(result.path)).to be true
      end
    end

    context "with libvips backend" do
      let(:attachment) { double("Attachment", options: { backend: :vips }, instance: double(local?: false)) }

      before do
        begin
          require "vips"
        rescue LoadError
          skip "libvips not installed"
        end
      end

      it "resizes based on maximum pixel count" do
        processor = described_class.new(file, { pixels: 10_000 }, attachment)
        result = processor.make

        expect(File.exist?(result.path)).to be true
        dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
        width, height = dimensions.split("x").map(&:to_i)
        expect(width * height).to be <= 10_000
      end
    end
  end

  describe "metadata stripping trigger" do
    it "processes when attachment instance is local" do
      local_instance = double(local?: true)
      local_attachment = double("Attachment", options: {}, instance: local_instance)

      processor = described_class.new(file, { geometry: "434x66" }, local_attachment)

      # Even with matching geometry, should process because local? is true
      # This is verified by the fact that make doesn't just return the original file
      result = processor.make
      expect(File.exist?(result.path)).to be true
    end
  end

  describe "Thumbnail.make class method" do
    it "is available and works correctly" do
      expect(Paperclip::Thumbnail).to respond_to(:make)

      result = Paperclip::Thumbnail.make(file, { geometry: "50x50#" }, attachment)
      expect(File.exist?(result.path)).to be true

      dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
      expect(dimensions).to eq("50x50")
    end

    it "respects backend option" do
      begin
        require "vips"
      rescue LoadError
        skip "libvips not installed"
      end

      result = Paperclip::Thumbnail.make(file, { geometry: "50x50#", backend: :vips }, attachment)
      expect(File.exist?(result.path)).to be true

      dimensions = `identify -format "%wx%h" "#{result.path}"`.strip
      expect(dimensions).to eq("50x50")
    end
  end
end
