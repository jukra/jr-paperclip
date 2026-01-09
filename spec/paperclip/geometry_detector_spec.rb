require "spec_helper"

describe Paperclip::GeometryDetector do
  [:image_magick, :vips].each do |backend|
    context "when configured to use #{backend}" do
      let(:original_backend) { Paperclip.options[:backend] }

      before do
        Paperclip.options[:backend] = backend
      end

      after do
        Paperclip.options[:backend] = original_backend
      end

      it "identifies an image and extract its dimensions" do
        allow_any_instance_of(Paperclip::GeometryParser).to receive(:make).and_return(:correct)
        file = fixture_file("5k.png")
        factory = Paperclip::GeometryDetector.new(file)

        output = factory.make

        expect(output).to eq :correct
      end

      it "identifies an image and extract its dimensions and orientation" do
        allow_any_instance_of(Paperclip::GeometryParser).to receive(:make).and_return(:correct)
        file = fixture_file("rotated.jpg")
        factory = Paperclip::GeometryDetector.new(file)

        output = factory.make

        expect(output).to eq :correct
      end

      it "avoids reading EXIF orientation if so configured" do
        begin
          Paperclip.options[:use_exif_orientation] = false
          allow_any_instance_of(Paperclip::GeometryParser).to receive(:make).and_return(:correct)
          file = fixture_file("rotated.jpg")
          factory = Paperclip::GeometryDetector.new(file)

          output = factory.make

          expect(output).to eq :correct
        ensure
          Paperclip.options[:use_exif_orientation] = true
        end
      end

      it "raises an exception with a message when the file is not an image" do
        file = fixture_file("text.txt")
        factory = Paperclip::GeometryDetector.new(file)

        expect do
          factory.make
        end.to raise_error(Paperclip::Errors::NotIdentifiedByBackendError, "Could not identify image size")
      end

      it "uses the correct backend to identify the image" do
        if backend == :vips
          begin
            require "vips"
          rescue LoadError
            skip "ruby-vips gem not available"
          end
          expect(Vips::Image).to receive(:new_from_file).and_call_original
          expect(Paperclip).not_to receive(:run).with(include("identify"), any_args)
        else
          expect(Paperclip).to receive(:run).with(include("identify"), any_args).and_call_original
        end

        file = fixture_file("5k.png")
        factory = Paperclip::GeometryDetector.new(file)

        geometry = factory.make
        expect(geometry.width).to eq(434)
        expect(geometry.height).to eq(66)
      end

      if backend == :vips
        it "raises CommandNotFoundError (and not NameError) when vips is missing" do
          hide_const("Vips")
          allow_any_instance_of(Paperclip::GeometryDetector).to receive(:require).with("vips").and_raise(LoadError)

          file = fixture_file("5k.png")
          factory = Paperclip::GeometryDetector.new(file)

          expect {
            factory.make
          }.to raise_error(Paperclip::Errors::CommandNotFoundError, /Could not load ruby-vips/)
        end
      end
    end
  end
end
