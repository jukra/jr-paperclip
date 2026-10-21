# frozen_string_literal: true

require "spec_helper"

describe Paperclip::Thumbnail do
  describe "ImageMagick loader orientation" do
    [
      ["orients by default", {}, [33, 50]],
      ["honors auto_orient disabled", { auto_orient: false }, [50, 33]],
      ["honors explicit loader orientation disabled", { source_file_options: { auto_orient: false } }, [50, 33]],
      ["lets explicit loader orientation override the default",
       { auto_orient: false, source_file_options: { auto_orient: true } }, [33, 50]],
    ].each do |description, options, dimensions|
      it description do
        File.open(fixture_file("rotated.jpg"), "rb") do |file|
          processor = described_class.new(file, {
            backend: :image_magick, geometry: "50x50>", convert_options: "-strip"
          }.merge(options))
          result = processor.make
          begin
            expect(MiniMagick::Image.new(result.path).dimensions).to eq(dimensions)
          ensure
            result.close!
          end
        end
      end
    end
  end

  describe "vips file thumbnailing" do
    before do
      require "vips"
      @directory = Dir.mktmpdir
      @path = File.join(@directory, "source.jpg")
      red = Vips::Image.black(60, 40).new_from_image([255, 0, 0])
      green = red.new_from_image([0, 255, 0])
      blue = red.new_from_image([0, 0, 255])
      yellow = red.new_from_image([255, 255, 0])
      @image = red.join(green, :horizontal).join(blue.join(yellow, :horizontal), :vertical)
    end

    after { FileUtils.remove_entry(@directory) }

    def process_vips_image(options = {})
      File.open(@path) do |file|
        result = described_class.new(file,
                                     { backend: :vips, geometry: "60x40>",
                                       convert_options: "-strip" }.merge(options)).make
        begin
          yield Vips::Image.new_from_file(result.path), result
        ensure
          result.close!
        end
      end
    end

    # Expected corners after EXIF's rotations AND reflections, independently of autorot.
    { 1 => %w(R G B Y), 2 => %w(G R Y B), 3 => %w(Y B G R), 4 => %w(B Y R G),
      5 => %w(R B G Y), 6 => %w(B R Y G), 7 => %w(Y G B R), 8 => %w(G Y R B) }.each do |orientation, corners|
      it "shrinks and orients EXIF #{orientation}, then strips metadata" do
        @image.set_type(@image.get_typeof("width"), "orientation", orientation)
        @image.write_to_file(@path)
        process_vips_image do |image, _result|
          expect([image.width, image.height]).to eq(orientation < 5 ? [60, 40] : [27, 40])
          points = [[0.2, 0.2], [0.8, 0.2], [0.2, 0.8], [0.8, 0.8]]
          colors = { "R" => [255, 0, 0], "G" => [0, 255, 0], "B" => [0, 0, 255], "Y" => [255, 255, 0] }
          points.zip(corners).each do |(x, y), color|
            image.getpoint((image.width * x).to_i,
                           (image.height * y).to_i).zip(colors.fetch(color)).each do |actual, expected|
              expect(actual).to be_within(20).of(expected)
            end
          end
          expect(image.get_typeof("exif-data")).to eq(0)
          expect(image.get_typeof("orientation")).to eq(0)
        end
      end
    end

    it "uses native file thumbnailing rather than loading the full image first" do
      @image.write_to_file(@path)
      expect(Vips::Image).to receive(:thumbnail).with(@path, 60, height: 40, size: :down).and_call_original
      process_vips_image { |image, _result| expect([image.width, image.height]).to eq([60, 40]) }
    end

    it "retains explicit loader policies, even when equal to the old defaults" do
      @image.set_type(@image.get_typeof("width"), "orientation", 6)
      @image.write_to_file(@path)
      allow(Vips::Image).to receive(:new_from_file).and_call_original
      [{ access: :sequential }, { access: :random, fail_on: :error },
       { autorotate: true }, { autorotate: false }].each do |loader|
        expect(Vips::Image).not_to receive(:thumbnail)
        expect(Vips::Image).to receive(:new_from_file).with(@path,
                                                            **{ access: :sequential,
                                                                autorotate: true }.merge(loader)).and_call_original
        process_vips_image(source_file_options: loader) do |image, _result|
          expect([image.width, image.height]).to eq(loader[:autorotate] == false ? [60, 40] : [27, 40])
        end
      end
    end

    it "supports an explicit PNG loader with auto_orient disabled" do
      @path = File.join(@directory, "source.png")
      @image.write_to_file(@path)
      process_vips_image(auto_orient: false, source_file_options: { loader: :png }) do |image, _result|
        expect([image.width, image.height]).to eq([60, 40])
      end
    end

    it "lets explicit autorot override auto_orient disabled" do
      @image.set_type(@image.get_typeof("width"), "orientation", 6)
      @image.write_to_file(@path)
      process_vips_image(auto_orient: false, source_file_options: { autorot: true }) do |image, _result|
        expect([image.width, image.height]).to eq([27, 40])
      end
    end

    it "does not orient when auto_orient is false, with or without a resize" do
      @image.set_type(@image.get_typeof("width"), "orientation", 6)
      @image.write_to_file(@path)
      ["60x40>", ""].each do |geometry|
        process_vips_image(auto_orient: false, geometry: geometry) do |image, _result|
          expect([image.width, image.height]).to eq(geometry.empty? ? [120, 80] : [60, 40])
          expect(image.getpoint(5, 5).first).to be > 230
        end
      end
    end

    it "still orients when the geometry does not add a resize" do
      @image.set_type(@image.get_typeof("width"), "orientation", 6)
      @image.write_to_file(@path)
      ["", "60x40<"].each do |geometry|
        process_vips_image(geometry: geometry) do |image, _result|
          expect([image.width, image.height]).to eq([80, 120])
        end
      end
    end

    it "keeps nonzero frame selection and animation" do
      @path = File.join(@directory, "source.gif")
      red = @image.new_from_image([255, 0, 0])
      green = @image.new_from_image([0, 255, 0])
      red.join(green, :vertical).write_to_file(@path, page_height: 80)
      process_vips_image(animated: false, frame_index: 1) do |image, _result|
        expect([image.width, image.height]).to eq([60, 40])
        expect(image.getpoint(10, 10).first(3)).to eq([0, 255, 0])
      end
      process_vips_image do |image, _result|
        expect(image.get("n-pages")).to eq(2)
      end
    end

    it "keeps shrink-only geometry and still allows explicit upscaling" do
      @image.write_to_file(@path)
      { "240x160>" => [120, 80], "240x160" => [240, 160] }.each do |geometry, dimensions|
        process_vips_image(geometry: geometry) do |image, _result|
          expect([image.width, image.height]).to eq(dimensions)
        end
      end
    end

    it "retains PNG alpha and requested output format" do
      @path = File.join(@directory, "source.png")
      @image.bandjoin(128).write_to_file(@path)
      process_vips_image do |image, result|
        expect(File.extname(result.path)).to eq(".png")
        expect(image.getpoint(10, 10).last).to eq(128)
      end
      process_vips_image(format: :jpg) do |image, result|
        expect(File.extname(result.path)).to eq(".jpg")
        expect(image.bands).to eq(3)
      end
    end
  end

  describe "#parse_loader_options" do
    let(:file) { File.new(fixture_file("5k.png"), "rb") }
    let(:thumb) { Paperclip::Thumbnail.new(file, geometry: "50x50") }

    after { file.close }

    it "correctly parses positive numeric values" do
      options = "-density 300"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ density: "300" })
    end

    it "correctly parses negative numeric values" do
      # Some hypothetical loader option that might take a negative value
      options = "-something -90"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ something: "-90" })
    end

    it "still treats non-numeric tokens starting with - as new options" do
      options = "-density 300 -strip"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ density: "300", strip: true })
    end

    it "handles single-quoted values correctly" do
      options = "-comment 'Hello World'"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ comment: "Hello World" })
    end

    it "handles double-quoted values correctly" do
      options = '-path "/some/path with spaces"'
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ path: "/some/path with spaces" })
    end

    it "handles escaped spaces correctly" do
      options = '-label Hello\ World'
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ label: "Hello World" })
    end

    it "handles multiple options with quoted values" do
      options = "-first 'Value One' -second 'Value Two'"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ first: "Value One", second: "Value Two" })
    end
  end
end
