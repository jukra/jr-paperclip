require "spec_helper"

describe Paperclip::Thumbnail do
  context "with ImageMagick specific + options" do
    before do
      @file = File.new(fixture_file("5k.png"), "rb")
      @attachment = double("Attachment", options: {})
    end

    after { @file.close }

    it "correctly applies options starting with +" do
      # The user's specific options - with Shellwords, quoted values are parsed correctly
      convert_options = '-coalesce +profile "!icc,*" +set date:modify +set date:create +set date:timestamp'

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      # Spy on the pipeline to verify the correct methods/arguments are called on it.
      allow(thumb).to receive(:apply_single_option).and_call_original
      expect { thumb.make }.not_to raise_error

      # With Shellwords parsing, the outer quotes are stripped from "!icc,*" -> !icc,*
      expect(thumb).to have_received(:apply_single_option).with(anything, "coalesce", nil, "-")
      expect(thumb).to have_received(:apply_single_option).with(anything, "profile", "!icc,*", "+")
      expect(thumb).to have_received(:apply_single_option).with(anything, "set", "date:modify", "+")
      expect(thumb).to have_received(:apply_single_option).with(anything, "set", "date:create", "+")
      expect(thumb).to have_received(:apply_single_option).with(anything, "set", "date:timestamp", "+")
    end
  end

  context "with convert_options having multiple arguments for a flag" do
    before do
      @file = File.new(fixture_file("5k.png"), "rb")
      @attachment = double("Attachment", options: {})
    end

    after { @file.close }

    it "handles -set with two arguments correctly" do
      # User provided example
      convert_options = "-coalesce -set my_prop 123123"

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      result = nil
      expect { result = thumb.make }.not_to raise_error

      # Verify property is set
      require "shellwords"
      output = `identify -verbose #{Shellwords.escape(result.path)}`
      expect(output).to include("my_prop: 123123")
    end
  end

  context "with convert_options having multiple arguments followed by other options" do
    before do
      @file = File.new(fixture_file("5k.png"), "rb")
      @attachment = double("Attachment", options: {})
    end

    after { @file.close }

    it "handles -set with two arguments followed by another option" do
      # User provided example scenario
      convert_options = "-set my_prop 123123 -auto-orient"

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      result = nil
      expect { result = thumb.make }.not_to raise_error

      require "shellwords"
      output = `identify -verbose #{Shellwords.escape(result.path)}`
      expect(output).to include("my_prop: 123123")
    end
  end

  context "with quoted values in convert_options (Shellwords parsing)" do
    before do
      @file = File.new(fixture_file("5k.png"), "rb")
      @attachment = double("Attachment", options: {})
    end

    after { @file.close }

    it "handles single-quoted values correctly" do
      # Shellwords should parse 'Hello World' as a single token
      convert_options = "-set my_comment 'Hello World'"

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      allow(thumb).to receive(:apply_single_option).and_call_original
      result = nil
      expect { result = thumb.make }.not_to raise_error

      # Verify that 'Hello World' was passed as a single value (without quotes)
      expect(thumb).to have_received(:apply_single_option).with(anything, "set", "my_comment", "-")

      # Check output includes the set property
      require "shellwords"
      output = `identify -verbose #{Shellwords.escape(result.path)}`
      expect(output).to include("my_comment: Hello World")
    end

    it "handles double-quoted values correctly" do
      convert_options = '-set my_comment "Hello World"'

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      result = nil
      expect { result = thumb.make }.not_to raise_error

      require "shellwords"
      output = `identify -verbose #{Shellwords.escape(result.path)}`
      expect(output).to include("my_comment: Hello World")
    end

    it "handles escaped spaces correctly" do
      convert_options = '-set my_comment Hello\ World'

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      result = nil
      expect { result = thumb.make }.not_to raise_error

      require "shellwords"
      output = `identify -verbose #{Shellwords.escape(result.path)}`
      expect(output).to include("my_comment: Hello World")
    end

    it "handles multiple quoted options correctly" do
      convert_options = "-set first_prop 'First Value' -set second_prop 'Second Value'"

      thumb = Paperclip::Thumbnail.new(@file, {
                                         geometry: "100x100",
                                         convert_options: convert_options,
                                         backend: :image_magick,
                                       }, @attachment)

      result = nil
      expect { result = thumb.make }.not_to raise_error

      require "shellwords"
      output = `identify -verbose #{Shellwords.escape(result.path)}`
      expect(output).to include("first_prop: First Value")
      expect(output).to include("second_prop: Second Value")
    end
  end
end
